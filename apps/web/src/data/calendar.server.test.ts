import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("@/data/read-only.server", () => ({
  serverReadOnlyReader: { select: vi.fn() },
}));

import { getCalendarData } from "@/data/calendar.server";
import { calendarPostsQuery } from "@/data/query-specifications";
import { calendarQueryBounds } from "@/data/calendar";
import { compileSelectSpecification } from "@/data/database-query";
import { createAuthorizedReader } from "@/data/read-only";
import { UnauthenticatedError } from "@/auth/errors";

const scheduled = {
  buffer_post_id: "one",
  platform: "tiktok",
  channel_name: "Sample",
  post_text: "Sample caption",
  external_link: "javascript:alert(1)",
  due_at: "2026-09-13T16:00:00Z",
  internal_title: "Clip name",
};
const published = {
  buffer_post_id: "two",
  platform: "youtube",
  channel_name: "Sample",
  post_text: "Published caption",
  external_link: null,
  published_at_utc: "2026-09-06T18:00:00Z",
  clip_group: null,
};

describe("calendar read boundary", () => {
  it("compiles minimal, parameterized month reads without proposal or write access", () => {
    for (const status of ["scheduled", "published"] as const) {
      const query = calendarPostsQuery(
        status,
        calendarQueryBounds("2026-09"),
        1,
      );
      const compiled = compileSelectSpecification(query);
      expect(query.range).toEqual({ from: 500, to: 999 });
      expect(compiled.text).toContain('from "creator_app".');
      expect(compiled.text).not.toContain("2026-09");
      expect(compiled.parameters[0]).toBe(
        status === "published" ? "sent" : "scheduled",
      );
      expect(query.columns).not.toMatch(/\*|raw_|proposal/);
    }
  });

  it("maps names and captions, strips unsafe links, and filters the UTC margin by local month", async () => {
    const data = await getCalendarData({
      month: "2026-09",
      reader: {
        select: async (query) =>
          query.relation === "dashboard_posts"
            ? [
                scheduled,
                {
                  ...scheduled,
                  buffer_post_id: "edge",
                  due_at: "2026-10-01T05:59:00Z",
                },
                {
                  ...scheduled,
                  buffer_post_id: "outside",
                  due_at: "2026-10-01T06:00:00Z",
                },
              ]
            : [published],
      },
    });
    expect(data.posts.map((post) => post.key)).toEqual(["one", "edge", "two"]);
    expect(data.posts[0]).toMatchObject({
      title: "Clip name",
      caption: "Sample caption",
      externalLink: null,
      status: "scheduled",
    });
    expect(data.posts[2]).toMatchObject({
      title: "Published caption",
      status: "published",
    });
    expect(data.partialErrors).toEqual([]);
  });

  it("paginates beyond 500 rows with authorization on every read", async () => {
    const authorize = vi.fn(async () => undefined);
    const execute = vi.fn(async (query) =>
      query.relation === "looker_dashboard_posts"
        ? []
        : query.range.from === 0
          ? Array.from({ length: 500 }, (_, index) => ({
              ...scheduled,
              buffer_post_id: String(index),
            }))
          : [{ ...scheduled, buffer_post_id: "500" }],
    );
    const data = await getCalendarData({
      month: "2026-09",
      reader: createAuthorizedReader({ authorize, execute }),
    });
    expect(data.posts).toHaveLength(501);
    expect(authorize).toHaveBeenCalledTimes(3);
    expect(execute).toHaveBeenCalledTimes(3);
  });

  it("keeps failures distinct from empty days and never exposes database errors", async () => {
    const data = await getCalendarData({
      month: "2026-09",
      reader: {
        select: async (query) => {
          if (query.relation === "dashboard_posts")
            throw new Error("private connection detail");
          return [published];
        },
      },
    });
    expect(data.posts).toHaveLength(1);
    expect(data.partialErrors[0].section).toBe("Scheduled posts");
    expect(JSON.stringify(data)).not.toContain("private connection detail");
    const malformed = await getCalendarData({
      month: "2026-09",
      reader: { select: async () => [{ ...scheduled, due_at: "not a date" }] },
    });
    expect(malformed.posts).toEqual([]);
    expect(malformed.partialErrors).toHaveLength(2);
  });

  it("does not silently truncate a very large month or retain half a failed section", async () => {
    const data = await getCalendarData({
      month: "2026-09",
      reader: {
        select: async (query) =>
          query.relation === "looker_dashboard_posts"
            ? []
            : Array.from({ length: 500 }, (_, index) => ({
                ...scheduled,
                buffer_post_id: `${query.range?.from}-${index}`,
              })),
      },
    });
    expect(data.posts).toEqual([]);
    expect(data.partialErrors).toHaveLength(1);
  });

  it("deduplicates a post that publishes between reads, keeping the published record", async () => {
    const data = await getCalendarData({
      month: "2026-09",
      reader: {
        select: async (query) =>
          query.relation === "dashboard_posts"
            ? [scheduled]
            : [{ ...published, buffer_post_id: "one" }],
      },
    });
    expect(data.posts).toHaveLength(1);
    expect(data.posts[0].status).toBe("published");
  });

  it("propagates authorization failure rather than rendering an empty calendar", async () => {
    const execute = vi.fn(async () => []);
    const reader = createAuthorizedReader({
      authorize: async () => {
        throw new UnauthenticatedError();
      },
      execute,
    });
    await expect(
      getCalendarData({ month: "2026-09", reader }),
    ).rejects.toBeInstanceOf(UnauthenticatedError);
    expect(execute).not.toHaveBeenCalled();
  });
});
