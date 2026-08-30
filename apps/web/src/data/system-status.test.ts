import { describe, expect, it } from "vitest";

import {
  buildSystemStatusData,
  systemBacklogRowSchema,
  systemBlockedApprovedRowSchema,
  systemPostFreshnessRowSchema,
} from "@/data/system-status";

type PostRowInput = {
  platform: string;
  status: string;
  last_synced_at: string | null;
  latest_metric_captured_at: string | null;
};

function buildStatus(options: {
  rows?: PostRowInput[];
  postSyncStaleHours?: number;
  metricsStaleHours?: number;
  blockedApproved?: ReturnType<typeof systemBlockedApprovedRowSchema.parse>[];
  unlinkedIds?: string[];
  pendingIds?: string[];
  postRowsAvailable?: boolean;
}) {
  return buildSystemStatusData({
    now: new Date("2026-08-29T18:00:00Z"),
    postSyncStaleHours: options.postSyncStaleHours ?? 15,
    metricsStaleHours: options.metricsStaleHours ?? 48,
    postRows: (options.rows ?? []).map((row) =>
      systemPostFreshnessRowSchema.parse(row),
    ),
    postRowsAvailable: options.postRowsAvailable ?? true,
    proposalErrors: [],
    proposalErrorsAvailable: true,
    blockedApproved: options.blockedApproved ?? [],
    blockedApprovedAvailable: true,
    previewReadiness: [],
    cadenceSettings: [],
    unlinkedRows: (options.unlinkedIds ?? []).map((buffer_post_id) =>
      systemBacklogRowSchema.parse({ buffer_post_id }),
    ),
    unlinkedAvailable: true,
    pendingExportRows: (options.pendingIds ?? []).map((buffer_post_id) =>
      systemBacklogRowSchema.parse({ buffer_post_id }),
    ),
    pendingExportAvailable: true,
    partialErrors: [],
  });
}

describe("System Status freshness semantics", () => {
  it("uses a fresh newest timestamp even when historical rows are old", () => {
    const result = buildStatus({
      rows: [
        {
          platform: "tiktok",
          status: "sent",
          last_synced_at: "2026-08-20T12:00:00Z",
          latest_metric_captured_at: "2026-08-20T12:00:00Z",
        },
        {
          platform: "tiktok",
          status: "sent",
          last_synced_at: "2026-08-29T17:00:00Z",
          latest_metric_captured_at: "2026-08-29T16:00:00Z",
        },
      ],
    });

    expect(result.postSyncFreshness[0]).toMatchObject({
      platform: "tiktok",
      state: "Fresh",
      observedPosts: 2,
      historicalRowsOutsideThreshold: 1,
      latestSyncedAt: "2026-08-29T17:00:00.000Z",
    });
    expect(result.metricsFreshness[0]).toMatchObject({
      state: "Fresh",
      observedSentPosts: 2,
      historicalRowsOutsideThreshold: 1,
      latestCapturedAt: "2026-08-29T16:00:00.000Z",
    });
    expect(result.summary.postSyncPlatformsNeedingAttention).toBe(0);
    expect(result.summary.metricsPlatformsNeedingAttention).toBe(0);
  });

  it("marks a platform stale when its newest timestamp is outside the threshold", () => {
    const result = buildStatus({
      rows: [
        {
          platform: "tiktok",
          status: "sent",
          last_synced_at: "2026-08-28T20:00:00Z",
          latest_metric_captured_at: "2026-08-26T12:00:00Z",
        },
        {
          platform: "tiktok",
          status: "sent",
          last_synced_at: "2026-08-20T12:00:00Z",
          latest_metric_captured_at: "2026-08-20T12:00:00Z",
        },
      ],
    });

    expect(result.postSyncFreshness[0].state).toBe("Stale");
    expect(result.metricsFreshness[0].state).toBe("Stale");
    expect(result.summary.postSyncPlatformsNeedingAttention).toBe(1);
    expect(result.summary.metricsPlatformsNeedingAttention).toBe(1);
  });

  it("marks a platform missing when no valid observation exists", () => {
    const result = buildStatus({
      rows: [
        {
          platform: "youtube",
          status: "sent",
          last_synced_at: null,
          latest_metric_captured_at: null,
        },
      ],
    });

    expect(result.postSyncFreshness[0]).toMatchObject({
      state: "Missing",
      recordsWithTimestamp: 0,
      missingTimestamps: 1,
      latestSyncedAt: null,
    });
    expect(result.metricsFreshness[0]).toMatchObject({
      state: "Missing",
      recordsWithTimestamp: 0,
      missingTimestamps: 1,
      latestCapturedAt: null,
    });
  });

  it("treats the exact threshold as fresh and the next second as stale", () => {
    const exactBoundary = buildStatus({
      rows: [
        {
          platform: "tiktok",
          status: "sent",
          last_synced_at: "2026-08-29T03:00:00Z",
          latest_metric_captured_at: "2026-08-27T18:00:00Z",
        },
      ],
    });
    const outsideBoundary = buildStatus({
      rows: [
        {
          platform: "tiktok",
          status: "sent",
          last_synced_at: "2026-08-29T02:59:59Z",
          latest_metric_captured_at: "2026-08-27T17:59:59Z",
        },
      ],
    });

    expect(exactBoundary.postSyncFreshness[0].state).toBe("Fresh");
    expect(exactBoundary.metricsFreshness[0].state).toBe("Fresh");
    expect(outsideBoundary.postSyncFreshness[0].state).toBe("Stale");
    expect(outsideBoundary.metricsFreshness[0].state).toBe("Stale");
  });

  it("keeps platform health independent and uses only sent posts for metrics", () => {
    const result = buildStatus({
      rows: [
        {
          platform: "tiktok",
          status: "sent",
          last_synced_at: "2026-08-29T17:00:00Z",
          latest_metric_captured_at: "2026-08-29T16:00:00Z",
        },
        {
          platform: "youtube",
          status: "sent",
          last_synced_at: "2026-08-28T20:00:00Z",
          latest_metric_captured_at: "2026-08-26T12:00:00Z",
        },
        {
          platform: "youtube",
          status: "scheduled",
          last_synced_at: "2026-08-29T17:30:00Z",
          latest_metric_captured_at: "2026-08-29T17:30:00Z",
        },
      ],
    });

    expect(result.postSyncFreshness).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ platform: "tiktok", state: "Fresh" }),
        expect.objectContaining({ platform: "youtube", state: "Fresh" }),
      ]),
    );
    expect(result.metricsFreshness).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ platform: "tiktok", state: "Fresh" }),
        expect.objectContaining({ platform: "youtube", state: "Stale" }),
      ]),
    );
    expect(result.summary.postSyncPlatformsNeedingAttention).toBe(0);
    expect(result.summary.metricsPlatformsNeedingAttention).toBe(1);
  });

  it("preserves blocked-approved and exported-but-unlinked totals", () => {
    const result = buildStatus({
      blockedApproved: [
        systemBlockedApprovedRowSchema.parse({
          platform: "tiktok",
          blocking_reasons: ["Same-channel gap conflict"],
          is_ready: false,
        }),
      ],
      unlinkedIds: ["POST_A", "POST_B"],
      pendingIds: ["POST_A"],
    });

    expect(result.summary.blockedApprovedProposals).toBe(1);
    expect(result.summary.exportedStillUnlinked).toBe(1);
    expect(result.blockedReasons).toEqual([
      { reason: "Same-channel gap conflict", count: 1 },
    ]);
  });

  it("does not present unavailable source counts as complete", () => {
    const result = buildStatus({ postRowsAvailable: false });

    expect(result.summary.observedPosts).toBeNull();
    expect(result.summary.postSyncPlatformsNeedingAttention).toBeNull();
    expect(result.summary.metricsPlatformsNeedingAttention).toBeNull();
  });
});
