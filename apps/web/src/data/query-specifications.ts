import type { SelectSpecification } from "@/data/read-only";

export const dashboardPostQuery = {
  relation: "looker_dashboard_posts",
  columns: [
    "platform",
    "channel_name",
    "status",
    "post_text",
    "external_link",
    "published_at_utc",
    "label_status",
    "clip_group",
    "game",
    "content_type",
    "latest_metric_date",
    "views",
    "reactions",
    "comments",
    "shares",
    "saves",
    "calculated_interaction_rate",
  ].join(","),
  filters: [{ operator: "eq", column: "status", value: "sent" }],
  order: [
    { column: "published_at_utc", ascending: false },
    { column: "buffer_post_id", ascending: true },
  ],
} satisfies SelectSpecification;

export const dailyGrowthQuery = {
  relation: "looker_daily_growth",
  columns:
    "platform,captured_on,views_gained,reactions_gained,comments_gained,shares_gained",
  order: [{ column: "captured_on", ascending: false }],
  limit: 60,
} satisfies SelectSpecification;

export const postingTimeQuery = {
  relation: "looker_posting_time_summary",
  columns:
    "platform,publish_day_name,publish_hour,post_count,average_views,average_calculated_interaction_rate",
  order: [{ column: "average_views", ascending: false }],
  limit: 8,
} satisfies SelectSpecification;

export const contentPerformanceQuery = {
  relation: "looker_content_performance_summary",
  columns:
    "platform,game,content_type,vibe,post_count,average_views,average_calculated_interaction_rate",
  order: [{ column: "average_views", ascending: false }],
  limit: 8,
} satisfies SelectSpecification;

export function upcomingPostsQuery(nowIso: string): SelectSpecification {
  return {
    relation: "dashboard_posts",
    columns: [
      "buffer_post_id",
      "platform",
      "channel_name",
      "channel_display_name",
      "status",
      "post_text",
      "external_link",
      "due_at",
      "label_status",
      "internal_title",
      "game",
      "content_type",
      "last_synced_at",
    ].join(","),
    filters: [
      { operator: "eq", column: "status", value: "scheduled" },
      { operator: "gte", column: "due_at", value: nowIso },
    ],
    order: [{ column: "due_at", ascending: true }],
  };
}

export function proposalStatusQuery(
  bufferPostIds: readonly string[],
): SelectSpecification {
  return {
    relation: "looker_schedule_change_proposals",
    columns:
      "buffer_post_id,approval_status,proposed_due_at_utc,confidence,metrics_status,updated_at",
    filters: [
      {
        operator: "in",
        column: "buffer_post_id",
        value: bufferPostIds,
      },
    ],
    order: [{ column: "updated_at", ascending: false }],
  };
}

export const unlabeledPostsQueueQuery = {
  relation: "unlabeled_posts_queue",
  columns: [
    "buffer_post_id",
    "platform",
    "channel_name",
    "status",
    "post_text",
    "external_link",
    "published_at_local",
    "views",
    "latest_metric_date",
  ].join(","),
  order: [
    { column: "published_at_local", ascending: false },
    { column: "buffer_post_id", ascending: true },
  ],
} satisfies SelectSpecification;

export const pendingLabelQueueExportQuery = {
  relation: "pending_label_queue_exports",
  columns: "buffer_post_id",
  order: [{ column: "buffer_post_id", ascending: true }],
} satisfies SelectSpecification;

export const clipGroupRelationshipsQuery = {
  relation: "looker_dashboard_posts",
  columns:
    "platform,post_text,external_link,published_at_utc,clip_group,game,content_type",
  filters: [{ operator: "eq", column: "label_status", value: "labeled" }],
  order: [{ column: "published_at_utc", ascending: false }],
  limit: 300,
} satisfies SelectSpecification;

export const scheduleProposalHistoryQuery = {
  relation: "looker_schedule_change_proposals",
  columns: [
    "proposal_id",
    "buffer_post_id",
    "platform",
    "content_format",
    "post_text",
    "external_link",
    "current_due_at_utc",
    "proposed_due_at_utc",
    "slot_rank",
    "source_recommendation_rank",
    "recommendation_score",
    "confidence",
    "supporting_sample_size",
    "metrics_status",
    "timezone_name",
    "approval_status",
    "approved_at",
    "applied_at",
    "generated_at",
    "updated_at",
  ].join(","),
  order: [
    { column: "generated_at", ascending: false },
    { column: "proposal_id", ascending: false },
  ],
  limit: 200,
} satisfies SelectSpecification;

export function pendingScheduleProposalExportQuery(
  proposalIds: readonly string[],
): SelectSpecification {
  return {
    relation: "pending_schedule_proposal_exports",
    columns: "proposal_id",
    filters: [{ operator: "in", column: "proposal_id", value: proposalIds }],
  };
}

export function scheduleApplicationPreflightQuery(
  proposalIds: readonly string[],
): SelectSpecification {
  return {
    relation: "schedule_change_application_preflight",
    columns: "proposal_id,post_last_synced_at,blocking_reasons,is_ready",
    filters: [{ operator: "in", column: "proposal_id", value: proposalIds }],
  };
}

export function readyScheduleChangesQuery(
  proposalIds: readonly string[],
): SelectSpecification {
  return {
    relation: "approved_schedule_changes_ready_to_apply",
    columns: "proposal_id",
    filters: [{ operator: "in", column: "proposal_id", value: proposalIds }],
  };
}

export function proposalPostSyncQuery(
  bufferPostIds: readonly string[],
): SelectSpecification {
  return {
    relation: "dashboard_posts",
    columns: "buffer_post_id,due_at,last_synced_at",
    filters: [
      {
        operator: "in",
        column: "buffer_post_id",
        value: bufferPostIds,
      },
    ],
  };
}
