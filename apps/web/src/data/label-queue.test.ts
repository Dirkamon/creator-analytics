import { describe, expect, it } from "vitest";

import {
  buildLabelQueueData,
  clipGroupRelationshipRowSchema,
  pendingLabelExportRowSchema,
  unlabeledQueueRowSchema,
} from "@/data/label-queue";

describe("Label Queue data mapping", () => {
  it("derives pending and exported-but-unlinked from the two queue views", () => {
    const unlabeledRows = [
      {
        buffer_post_id: "SANITIZED_POST_A",
        platform: "tiktok",
        channel_name: "Sample channel",
        status: "sent",
        post_text: "Sanitized pending export",
        external_link: "https://example.invalid/a",
        published_at_local: "2026-08-28T14:00:00",
        views: 100,
        latest_metric_date: "2026-08-29",
      },
      {
        buffer_post_id: "SANITIZED_POST_B",
        platform: "youtube",
        channel_name: "Sample channel",
        status: "sent",
        post_text: "Sanitized prior export",
        external_link: null,
        published_at_local: "2026-08-27T14:00:00",
        views: "200",
        latest_metric_date: "2026-08-29",
      },
    ].map((row) => unlabeledQueueRowSchema.parse(row));

    const result = buildLabelQueueData({
      unlabeledRows,
      pendingRows: [
        pendingLabelExportRowSchema.parse({
          buffer_post_id: "SANITIZED_POST_A",
        }),
      ],
      pendingStateAvailable: true,
      clipRows: [
        clipGroupRelationshipRowSchema.parse({
          platform: "tiktok",
          post_text: "Sanitized linked post",
          external_link: null,
          published_at_utc: "2026-08-26T20:00:00Z",
          clip_group: "Shared Sample",
          game: "Sample Game",
          content_type: "Highlight",
          vibe: "Chaotic",
        }),
      ],
      partialErrors: [],
    });

    expect(result.summary).toEqual({
      unlinked: 2,
      pendingExport: 1,
      exportedStillUnlinked: 1,
    });
    expect(result.items.map((item) => item.queueState)).toEqual([
      "pending_export",
      "exported_unlinked",
    ]);
    expect(result.items.map((item) => item.bufferPostId)).toEqual([
      "SANITIZED_POST_A",
      "SANITIZED_POST_B",
    ]);
    expect(result.clipGroups[0]).toMatchObject({
      name: "Shared Sample",
      platforms: ["tiktok"],
      postCount: 1,
      vibe: "Chaotic",
    });
  });

  it("does not infer export state when its owning view fails", () => {
    const row = unlabeledQueueRowSchema.parse({
      buffer_post_id: "SANITIZED_POST",
      platform: "tiktok",
      channel_name: null,
      status: "sent",
      post_text: null,
      external_link: null,
      published_at_local: null,
      views: null,
      latest_metric_date: null,
    });

    const result = buildLabelQueueData({
      unlabeledRows: [row],
      pendingRows: [],
      pendingStateAvailable: false,
      clipRows: [],
      partialErrors: [],
    });

    expect(result.summary.pendingExport).toBeNull();
    expect(result.summary.exportedStillUnlinked).toBeNull();
    expect(result.items[0].queueState).toBe("export_state_unavailable");
  });
});
