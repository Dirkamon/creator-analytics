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
