import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("@/data/read-only.server", () => ({
  serverReadOnlyReader: { select: vi.fn() },
}));

import { UnauthenticatedError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import { getRecentPerformanceData } from "@/data/dashboard.server";
import {
  dashboardPostQuery,
  postThumbnailsQuery,
} from "@/data/query-specifications";
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
    const select = vi.fn(async (query) =>
      query.relation === "post_thumbnails" ? [] : [row],
    );
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
      query.relation === "post_thumbnails"
        ? []
        : query.range.from === 0
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
    expect(authorize).toHaveBeenCalledTimes(3);
    expect(execute).toHaveBeenCalledWith({
      ...dashboardPostQuery,
      range: { from: 500, to: 999 },
    });
  });

  it("joins safe thumbnails by post ID and keeps unrelated/raw media out of the model", async () => {
    const safeUrl = "https://images.buffer.com/thumbnail/example?url=sample";
    const select = vi.fn(async (query) =>
      query.relation === "post_thumbnails"
        ? [
            {
              buffer_post_id: "sample",
              thumbnail_url: safeUrl,
              raw_data: "private",
            },
            {
              buffer_post_id: "unsafe",
              thumbnail_url: "https://evil.invalid/image",
            },
            { buffer_post_id: "unrelated", thumbnail_url: safeUrl },
          ]
        : [
            row,
            { ...row, buffer_post_id: "unsafe" },
            { ...row, buffer_post_id: "missing" },
          ],
    );
    const data = await getRecentPerformanceData({ select });
    expect(select).toHaveBeenCalledWith({
      ...postThumbnailsQuery,
      range: { from: 0, to: 499 },
    });
    expect(data.posts.map((post) => post.thumbnailUrl)).toEqual([
      safeUrl,
      null,
      null,
    ]);
    expect(JSON.stringify(data)).not.toMatch(
      /private|raw_data|unrelated|evil[.]invalid/,
    );
    expect(data.partialErrors).toEqual([]);
  });

  it("keeps metrics available when thumbnail reads fail, but never swallows authorization failures", async () => {
    const data = await getRecentPerformanceData({
      select: async (query) => {
        if (query.relation === "post_thumbnails")
          throw new Error("private connection detail");
        return [row];
      },
    });
    expect(data.posts[0]).toMatchObject({ views: 12345, thumbnailUrl: null });
    expect(data.partialErrors).toEqual([
      {
        section: "Post thumbnails",
        message: "Post thumbnails is temporarily unavailable.",
      },
    ]);
    await expect(
      getRecentPerformanceData({
        select: async (query) => {
          if (query.relation === "post_thumbnails")
            throw new UnauthenticatedError();
          return [row];
        },
      }),
    ).rejects.toBeInstanceOf(UnauthenticatedError);
  });

  it("paginates thumbnails independently and performs no image reads for empty post results", async () => {
    const select = vi.fn(async (query) =>
      query.relation === "looker_dashboard_posts"
        ? [row]
        : query.range.from === 0
          ? Array.from({ length: 500 }, (_, index) => ({
              buffer_post_id: String(index),
              thumbnail_url: null,
            }))
          : [
              {
                buffer_post_id: "sample",
                thumbnail_url: "https://images.buffer.com/thumbnail/last",
              },
            ],
    );
    const data = await getRecentPerformanceData({ select });
    expect(data.posts[0].thumbnailUrl).toBe(
      "https://images.buffer.com/thumbnail/last",
    );
    expect(select).toHaveBeenCalledWith({
      ...postThumbnailsQuery,
      range: { from: 500, to: 999 },
    });
    const empty = vi.fn(async () => []);
    await getRecentPerformanceData({ select: empty });
    expect(empty).toHaveBeenCalledTimes(1);
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
