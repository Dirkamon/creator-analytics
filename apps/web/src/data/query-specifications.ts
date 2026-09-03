import type { SelectSpecification } from "@/data/read-only";

export const dashboardPostQuery = {
  relation: "looker_dashboard_posts",
  columns: [
    "buffer_post_id",
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

export const analyticsContentPerformanceQuery = {
  relation: "looker_content_performance_summary",
  columns:
    "platform,game,content_type,vibe,hook_type,post_count,average_views,median_views,average_calculated_interaction_rate",
  order: [{ column: "average_views", ascending: false }],
  limit: 60,
} satisfies SelectSpecification;

export const analyticsPostingTimeQuery = {
  relation: "looker_posting_time_summary",
  columns:
    "platform,channel_name,publish_day_name,publish_hour,post_count,average_views,median_views,average_calculated_interaction_rate",
  order: [{ column: "average_views", ascending: false }],
  limit: 120,
} satisfies SelectSpecification;

export const analyticsJointRecommendationsQuery = {
  relation: "looker_joint_posting_recommendations",
  columns:
    "platform,recommendation_rank,recommended_slot,post_count,platform_post_count,avg_views,median_views,recommendation_score,confidence,latest_metric_date,metrics_age_days,metrics_status,recommendation_ready_for_approval_mode",
  filters: [{ operator: "lte", column: "recommendation_rank", value: 3 }],
  order: [
    { column: "platform", ascending: true },
    { column: "recommendation_rank", ascending: true },
  ],
} satisfies SelectSpecification;

export const analyticsFallbackQuery = {
  relation: "looker_content_aware_fallback_preview",
  columns:
    "platform,game,content_type,vibe,selected_model_level,selected_model_priority,group_sample_size,minimum_sample_size,recommended_slot,recommendation_score,confidence,metrics_status,recommendation_ready_for_preview,fallback_reason",
  order: [
    { column: "platform", ascending: true },
    { column: "selected_model_priority", ascending: true },
    { column: "group_sample_size", ascending: false },
  ],
  limit: 160,
} satisfies SelectSpecification;

export const cadenceSettingsQuery = {
  relation: "looker_scheduling_cadence_settings",
  columns:
    "platform,content_format,posts_per_week,max_posts_per_day,min_gap_hours,protected_hours,minimum_sample_size,metrics_freshness_limit_days,timezone_name,is_active,updated_at",
  order: [
    { column: "platform", ascending: true },
    { column: "content_format", ascending: true },
  ],
} satisfies SelectSpecification;

export const weeklySlotPlanQuery = {
  relation: "looker_weekly_slot_plan",
  columns:
    "platform,content_format,slot_rank,publish_day_name,scheduled_hour_local,scheduled_time_local,recommended_window,recommendation_score,confidence,supporting_sample_size,metrics_status,timezone_name",
  order: [
    { column: "platform", ascending: true },
    { column: "content_format", ascending: true },
    { column: "slot_rank", ascending: true },
  ],
} satisfies SelectSpecification;

export const systemPostFreshnessQuery = {
  relation: "dashboard_posts",
  columns: "platform,status,last_synced_at,latest_metric_captured_at",
  order: [
    { column: "last_synced_at", ascending: false },
    { column: "buffer_post_id", ascending: true },
  ],
} satisfies SelectSpecification;

export const systemProposalErrorsQuery = {
  relation: "looker_schedule_change_proposals",
  columns: "platform,updated_at",
  filters: [{ operator: "eq", column: "approval_status", value: "Error" }],
  order: [
    { column: "updated_at", ascending: false },
    { column: "proposal_id", ascending: false },
  ],
} satisfies SelectSpecification;

export const systemBlockedApprovedQuery = {
  relation: "schedule_change_application_preflight",
  columns: "platform,blocking_reasons,is_ready",
  filters: [{ operator: "eq", column: "is_ready", value: false }],
  order: [{ column: "proposed_due_at_utc", ascending: true }],
} satisfies SelectSpecification;

export const systemPreviewReadinessQuery = {
  relation: "looker_content_aware_proposal_preview_summary",
  columns: [
    "platform",
    "preview_rows",
    "ready_to_create",
    "blocked_rows",
    "blocked_by_active_proposal",
    "content_specific_rows",
    "platform_overall_fallback_rows",
    "guardrail_pass_rows",
    "first_proposed_at_local",
    "last_proposed_at_local",
    "blocked_by_same_channel_reservation",
    "blocked_by_channel_identity",
    "blocked_by_configuration",
    "blocked_by_daily_capacity",
    "blocked_by_weekly_capacity",
  ].join(","),
  order: [{ column: "platform", ascending: true }],
} satisfies SelectSpecification;

export const systemUnlinkedBacklogQuery = {
  relation: "unlabeled_posts_queue",
  columns: "buffer_post_id",
  order: [{ column: "buffer_post_id", ascending: true }],
} satisfies SelectSpecification;

export const systemPendingLabelExportQuery = {
  relation: "pending_label_queue_exports",
  columns: "buffer_post_id",
  order: [{ column: "buffer_post_id", ascending: true }],
} satisfies SelectSpecification;
