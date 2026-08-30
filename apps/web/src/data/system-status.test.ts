import { describe, expect, it } from "vitest";

import { cadenceSettingRowSchema } from "@/data/analytics";
import {
  buildSystemStatusData,
  systemBacklogRowSchema,
  systemBlockedApprovedRowSchema,
  systemPostFreshnessRowSchema,
  systemPreviewReadinessRowSchema,
  systemProposalErrorRowSchema,
} from "@/data/system-status";

describe("System Status data mapping", () => {
  it("derives threshold attention and exported-but-unlinked database state", () => {
    const result = buildSystemStatusData({
      now: new Date("2026-08-29T18:00:00Z"),
      postSyncStaleHours: 6,
      metricsStaleHours: 48,
      postRows: [
        systemPostFreshnessRowSchema.parse({
          platform: "tiktok",
          status: "sent",
          last_synced_at: "2026-08-29T17:00:00Z",
          latest_metric_captured_at: "2026-08-29T16:00:00Z",
        }),
        systemPostFreshnessRowSchema.parse({
          platform: "tiktok",
          status: "scheduled",
          last_synced_at: "2026-08-29T10:00:00Z",
          latest_metric_captured_at: null,
        }),
        systemPostFreshnessRowSchema.parse({
          platform: "youtube",
          status: "sent",
          last_synced_at: null,
          latest_metric_captured_at: "2026-08-26T12:00:00Z",
        }),
      ],
      postRowsAvailable: true,
      proposalErrors: [
        systemProposalErrorRowSchema.parse({
          platform: "tiktok",
          updated_at: "2026-08-29T17:00:00Z",
        }),
      ],
      proposalErrorsAvailable: true,
      blockedApproved: [
        systemBlockedApprovedRowSchema.parse({
          platform: "tiktok",
          blocking_reasons: ["Same-channel gap conflict"],
          is_ready: false,
        }),
      ],
      blockedApprovedAvailable: true,
      previewReadiness: [
        systemPreviewReadinessRowSchema.parse({
          platform: "tiktok",
          preview_rows: 2,
          ready_to_create: 1,
          blocked_rows: 1,
          blocked_by_active_proposal: 0,
          content_specific_rows: 1,
          platform_overall_fallback_rows: 1,
          guardrail_pass_rows: 1,
          first_proposed_at_local: "2026-08-31T14:00:00",
          last_proposed_at_local: "2026-09-01T14:00:00",
          blocked_by_same_channel_reservation: 1,
          blocked_by_channel_identity: 0,
          blocked_by_configuration: 0,
          blocked_by_daily_capacity: 0,
          blocked_by_weekly_capacity: 0,
        }),
      ],
      cadenceSettings: [
        cadenceSettingRowSchema.parse({
          platform: "tiktok",
          content_format: "short_form",
          posts_per_week: 5,
          max_posts_per_day: 2,
          min_gap_hours: 4,
          protected_hours: 24,
          minimum_sample_size: 12,
          metrics_freshness_limit_days: 4,
          timezone_name: "America/Denver",
          is_active: true,
          updated_at: "2026-08-29T12:00:00Z",
        }),
      ],
      unlinkedRows: [
        systemBacklogRowSchema.parse({ buffer_post_id: "POST_A" }),
        systemBacklogRowSchema.parse({ buffer_post_id: "POST_B" }),
      ],
      unlinkedAvailable: true,
      pendingExportRows: [
        systemBacklogRowSchema.parse({ buffer_post_id: "POST_A" }),
      ],
      pendingExportAvailable: true,
      partialErrors: [],
    });

    expect(result.summary).toMatchObject({
      observedPosts: 3,
      stalePostSyncs: 2,
      observedSentMetrics: 2,
      staleMetrics: 1,
      proposalErrors: 1,
      blockedApprovedProposals: 1,
      unlinkedPosts: 2,
      pendingLabelExports: 1,
      exportedStillUnlinked: 1,
    });
    expect(result.blockedReasons).toEqual([
      { reason: "Same-channel gap conflict", count: 1 },
    ]);
    expect(result.automationTelemetry.available).toBe(false);
  });

  it("does not present partial source counts as complete", () => {
    const result = buildSystemStatusData({
      now: new Date("2026-08-29T18:00:00Z"),
      postSyncStaleHours: 6,
      metricsStaleHours: 48,
      postRows: [],
      postRowsAvailable: false,
      proposalErrors: [],
      proposalErrorsAvailable: false,
      blockedApproved: [],
      blockedApprovedAvailable: false,
      previewReadiness: [],
      cadenceSettings: [],
      unlinkedRows: [],
      unlinkedAvailable: false,
      pendingExportRows: [],
      pendingExportAvailable: false,
      partialErrors: [],
    });

    expect(result.summary.observedPosts).toBeNull();
    expect(result.summary.proposalErrors).toBeNull();
    expect(result.summary.exportedStillUnlinked).toBeNull();
  });
});
