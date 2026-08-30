import { z } from "zod";

import {
  cadenceSettingRowSchema,
  mapCadenceSettings,
  numericValue,
  type CadenceSettingRow,
} from "@/data/analytics";
import type {
  FreshnessState,
  PartialDataError,
  SystemStatusData,
} from "@/data/models";

export { cadenceSettingRowSchema };

export const systemPostFreshnessRowSchema = z.object({
  platform: z.string(),
  status: z.string(),
  last_synced_at: z.string().nullable(),
  latest_metric_captured_at: z.string().nullable(),
});

export const systemProposalErrorRowSchema = z.object({
  platform: z.string(),
  updated_at: z.string(),
});

export const systemBlockedApprovedRowSchema = z.object({
  platform: z.string(),
  blocking_reasons: z.array(z.string()).nullable(),
  is_ready: z.literal(false),
});

export const systemPreviewReadinessRowSchema = z.object({
  platform: z.string(),
  preview_rows: numericValue,
  ready_to_create: numericValue,
  blocked_rows: numericValue,
  blocked_by_active_proposal: numericValue,
  content_specific_rows: numericValue,
  platform_overall_fallback_rows: numericValue,
  guardrail_pass_rows: numericValue,
  first_proposed_at_local: z.string().nullable(),
  last_proposed_at_local: z.string().nullable(),
  blocked_by_same_channel_reservation: numericValue,
  blocked_by_channel_identity: numericValue,
  blocked_by_configuration: numericValue,
  blocked_by_daily_capacity: numericValue,
  blocked_by_weekly_capacity: numericValue,
});

export const systemBacklogRowSchema = z.object({
  buffer_post_id: z.string(),
});

type PostFreshnessRow = z.infer<typeof systemPostFreshnessRowSchema>;
type ProposalErrorRow = z.infer<typeof systemProposalErrorRowSchema>;
type BlockedApprovedRow = z.infer<typeof systemBlockedApprovedRowSchema>;
type PreviewReadinessRow = z.infer<typeof systemPreviewReadinessRowSchema>;
type BacklogRow = z.infer<typeof systemBacklogRowSchema>;

function isOldOrMissing(
  value: string | null,
  now: Date,
  thresholdHours: number,
): { stale: boolean; missing: boolean; timestamp: number | null } {
  if (!value) return { stale: false, missing: true, timestamp: null };
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) {
    return { stale: false, missing: true, timestamp: null };
  }
  return {
    stale: now.getTime() - timestamp > thresholdHours * 3_600_000,
    missing: false,
    timestamp,
  };
}

function newestIso(timestamps: number[]): string | null {
  return timestamps.length > 0
    ? new Date(Math.max(...timestamps)).toISOString()
    : null;
}

function groupFreshness(options: {
  rows: PostFreshnessRow[];
  now: Date;
  thresholdHours: number;
  timestamp: "last_synced_at" | "latest_metric_captured_at";
  sentOnly?: boolean;
}) {
  const groups = new Map<
    string,
    {
      observed: number;
      outsideThreshold: number;
      missing: number;
      timestamps: number[];
    }
  >();

  for (const row of options.rows) {
    if (options.sentOnly && row.status.toLowerCase() !== "sent") continue;
    const group = groups.get(row.platform) ?? {
      observed: 0,
      outsideThreshold: 0,
      missing: 0,
      timestamps: [],
    };
    const state = isOldOrMissing(
      row[options.timestamp],
      options.now,
      options.thresholdHours,
    );
    group.observed += 1;
    if (state.stale) group.outsideThreshold += 1;
    if (state.missing) group.missing += 1;
    if (state.timestamp !== null) group.timestamps.push(state.timestamp);
    groups.set(row.platform, group);
  }

  return [...groups.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([platform, group]) => {
      const latest = newestIso(group.timestamps);
      const latestState = isOldOrMissing(
        latest,
        options.now,
        options.thresholdHours,
      );
      const state: FreshnessState = latestState.missing
        ? "Missing"
        : latestState.stale
          ? "Stale"
          : "Fresh";

      return {
        platform,
        observed: group.observed,
        recordsWithTimestamp: group.timestamps.length,
        outsideThreshold: group.outsideThreshold,
        missing: group.missing,
        latest,
        state,
      };
    });
}

export function buildSystemStatusData(options: {
  now: Date;
  postSyncStaleHours: number;
  metricsStaleHours: number;
  postRows: PostFreshnessRow[];
  postRowsAvailable: boolean;
  proposalErrors: ProposalErrorRow[];
  proposalErrorsAvailable: boolean;
  blockedApproved: BlockedApprovedRow[];
  blockedApprovedAvailable: boolean;
  previewReadiness: PreviewReadinessRow[];
  cadenceSettings: CadenceSettingRow[];
  unlinkedRows: BacklogRow[];
  unlinkedAvailable: boolean;
  pendingExportRows: BacklogRow[];
  pendingExportAvailable: boolean;
  partialErrors: PartialDataError[];
}): SystemStatusData {
  const sync = groupFreshness({
    rows: options.postRows,
    now: options.now,
    thresholdHours: options.postSyncStaleHours,
    timestamp: "last_synced_at",
  });
  const metrics = groupFreshness({
    rows: options.postRows,
    now: options.now,
    thresholdHours: options.metricsStaleHours,
    timestamp: "latest_metric_captured_at",
    sentOnly: true,
  });
  const pendingIds = new Set(
    options.pendingExportRows.map((row) => row.buffer_post_id),
  );
  const exportedStillUnlinked = options.unlinkedRows.filter(
    (row) => !pendingIds.has(row.buffer_post_id),
  ).length;
  const reasons = new Map<string, number>();
  for (const row of options.blockedApproved) {
    for (const reason of row.blocking_reasons ?? [
      "Blocked without a database-provided reason",
    ]) {
      reasons.set(reason, (reasons.get(reason) ?? 0) + 1);
    }
  }

  return {
    thresholds: {
      postSyncStaleHours: options.postSyncStaleHours,
      metricsStaleHours: options.metricsStaleHours,
    },
    summary: {
      observedPosts: options.postRowsAvailable ? options.postRows.length : null,
      postSyncPlatformsNeedingAttention: options.postRowsAvailable
        ? sync.filter((group) => group.state !== "Fresh").length
        : null,
      observedSentMetrics: options.postRowsAvailable
        ? metrics.reduce((total, group) => total + group.observed, 0)
        : null,
      metricsPlatformsNeedingAttention: options.postRowsAvailable
        ? metrics.filter((group) => group.state !== "Fresh").length
        : null,
      proposalErrors: options.proposalErrorsAvailable
        ? options.proposalErrors.length
        : null,
      blockedApprovedProposals: options.blockedApprovedAvailable
        ? options.blockedApproved.length
        : null,
      unlinkedPosts: options.unlinkedAvailable
        ? options.unlinkedRows.length
        : null,
      pendingLabelExports: options.pendingExportAvailable
        ? options.pendingExportRows.length
        : null,
      exportedStillUnlinked:
        options.unlinkedAvailable && options.pendingExportAvailable
          ? exportedStillUnlinked
          : null,
    },
    postSyncFreshness: sync.map((group) => ({
      platform: group.platform,
      state: group.state,
      observedPosts: group.observed,
      recordsWithTimestamp: group.recordsWithTimestamp,
      historicalRowsOutsideThreshold: group.outsideThreshold,
      missingTimestamps: group.missing,
      latestSyncedAt: group.latest,
    })),
    metricsFreshness: metrics.map((group) => ({
      platform: group.platform,
      state: group.state,
      observedSentPosts: group.observed,
      recordsWithTimestamp: group.recordsWithTimestamp,
      historicalRowsOutsideThreshold: group.outsideThreshold,
      missingTimestamps: group.missing,
      latestCapturedAt: group.latest,
    })),
    cadenceSettings: mapCadenceSettings(options.cadenceSettings),
    previewReadiness: options.previewReadiness.map((row) => ({
      platform: row.platform,
      previewRows: row.preview_rows,
      readyRows: row.ready_to_create,
      blockedRows: row.blocked_rows,
      activeProposalBlocks: row.blocked_by_active_proposal,
      contentSpecificRows: row.content_specific_rows,
      platformFallbackRows: row.platform_overall_fallback_rows,
      guardrailPassRows: row.guardrail_pass_rows,
      firstProposedAtLocal: row.first_proposed_at_local,
      lastProposedAtLocal: row.last_proposed_at_local,
      sameChannelBlocks: row.blocked_by_same_channel_reservation,
      channelIdentityBlocks: row.blocked_by_channel_identity,
      configurationBlocks: row.blocked_by_configuration,
      dailyCapacityBlocks: row.blocked_by_daily_capacity,
      weeklyCapacityBlocks: row.blocked_by_weekly_capacity,
    })),
    blockedReasons: [...reasons.entries()]
      .map(([reason, count]) => ({ reason, count }))
      .sort((left, right) => right.count - left.count),
    recentProposalErrors: options.proposalErrors.slice(0, 8).map((row) => ({
      platform: row.platform,
      updatedAt: row.updated_at,
    })),
    automationTelemetry: {
      available: false,
      explanation:
        "The repository defines automation_runs but contains no writer for it, and live population has not been confirmed. Make, Buffer, and Google Sheets health are therefore outside this database-observed status page.",
    },
    partialErrors: options.partialErrors,
  };
}
