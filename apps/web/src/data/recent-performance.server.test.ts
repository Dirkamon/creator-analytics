import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("@/data/read-only.server", () => ({
  serverReadOnlyReader: { select: vi.fn() },
}));

import { UnauthenticatedError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import { getRecentPerformanceData } from "@/data/dashboard.server";
import { dashboardPostQuery } from "@/data/query-specifications";
import { createAuthorizedReader } from "@/data/read-only";

const row = {
  buffer_post_id: "sample",
  platform: "tiktok",
  channel_name: "Sample channel",
  status: "sent",
  post_text: "A caption",
  external_link: "javascript:alert(1)",
  published_at_utc: "2026-09-16T18:00:00Z",
  label_status: "labeled",
  clip_group: "Sample clip",
  game: "Sample game",
  content_type: "Highlight",
  latest_metric_date: "2026-09-17",
  views: "12345",
  reactions: null,
  comments: "0",
  shares: "42",
  saves: null,
  calculated_interaction_rate: "8.75",
};

describe("recent performance read boundary", () => {
  it("uses the existing sent-post read model with explicit safe fields and stable order", async () => {
    const select = vi.fn(async () => [row]);
    const data = await getRecentPerformanceData({ select });
    expect(select).toHaveBeenCalledWith({
      ...dashboardPostQuery,
      range: { from: 0, to: 499 },
    });
    expect(dashboardPostQuery.relation).toBe("looker_dashboard_posts");
    expect(dashboardPostQuery.filters).toEqual([
      { operator: "eq", column: "status", value: "sent" },
    ]);
    expect(dashboardPostQuery.columns).not.toMatch(/\*|raw_|proposal|token/);
    expect(dashboardPostQuery.order).toEqual([
      { column: "published_at_utc", ascending: false },
      { column: "buffer_post_id", ascending: true },
    ]);
    expect(data.posts[0]).toMatchObject({
      key: "sample",
      views: 12345,
      reactions: null,
      comments: 0,
      shares: 42,
      saves: null,
      interactionRate: 8.75,
      externalLink: null,
      latestMetricDate: "2026-09-17",
    });
    expect(data.partialErrors).toEqual([]);
  });

  it("preserves missing metrics and dates, caption fallback and valid links", async () => {
    const data = await getRecentPerformanceData({
      select: async () => [
        {
          ...row,
          post_text: " ",
          external_link: "https://example.invalid/post",
          views: null,
          comments: null,
          shares: null,
          calculated_interaction_rate: null,
          latest_metric_date: null,
        },
      ],
    });
    expect(data.posts[0]).toMatchObject({
      caption: "Untitled post",
      externalLink: "https://example.invalid/post",
      views: null,
      reactions: null,
      comments: null,
      shares: null,
      saves: null,
      interactionRate: null,
      latestMetricDate: null,
    });
  });

  it("reads beyond 500 posts with authorization for every page", async () => {
    const authorize = vi.fn(async () => undefined);
    const execute = vi.fn(async (query) =>
      query.range.from === 0
        ? Array.from({ length: 500 }, (_, index) => ({
            ...row,
            buffer_post_id: String(index),
          }))
        : [{ ...row, buffer_post_id: "500" }],
    );
    const data = await getRecentPerformanceData(
      createAuthorizedReader({ authorize, execute }),
    );
    expect(data.posts).toHaveLength(501);
    expect(authorize).toHaveBeenCalledTimes(2);
    expect(execute).toHaveBeenLastCalledWith({
      ...dashboardPostQuery,
      range: { from: 500, to: 999 },
    });
  });

  it("discards partial reads and sanitizes failures rather than showing incomplete metrics", async () => {
    const data = await getRecentPerformanceData({
      select: async (query) => {
        if (query.range?.from === 0)
          return Array.from({ length: 500 }, (_, index) => ({
            ...row,
            buffer_post_id: String(index),
          }));
        throw new Error("private database connection detail");
      },
    });
    expect(data.posts).toEqual([]);
    expect(data.partialErrors).toEqual([
      {
        section: "Post performance",
        message: "Post performance is temporarily unavailable.",
      },
    ]);
    expect(JSON.stringify(data)).not.toContain("private database");
    const invalid = await getRecentPerformanceData({
      select: async () => [{ ...row, views: "invalid" }],
    });
    expect(invalid.posts).toEqual([]);
    expect(invalid.partialErrors).toHaveLength(1);
  });

  it("propagates auth and configuration failures", async () => {
    for (const error of [
      new UnauthenticatedError(),
      new ConfigurationError("Missing configuration"),
    ]) {
      const execute = vi.fn(async () => []);
      const reader = createAuthorizedReader({
        authorize: async () => {
          throw error;
        },
        execute,
      });
      await expect(getRecentPerformanceData(reader)).rejects.toBe(error);
      expect(execute).not.toHaveBeenCalled();
    }
  });
});
