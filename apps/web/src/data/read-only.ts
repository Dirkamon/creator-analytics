type RelationPolicy = {
  selectableColumns: readonly string[];
  filterColumns: readonly string[];
  orderColumns: readonly string[];
};

export const readOnlyRelationPolicies = {
  dashboard_posts: {
    selectableColumns: [
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
      "latest_metric_captured_at",
    ],
    filterColumns: ["status", "due_at", "buffer_post_id"],
    orderColumns: ["due_at", "last_synced_at", "buffer_post_id"],
  },
  looker_dashboard_posts: {
    selectableColumns: [
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
      "vibe",
    ],
    filterColumns: ["status", "label_status", "published_at_utc"],
    orderColumns: ["published_at_utc", "buffer_post_id"],
  },
  looker_daily_growth: {
    selectableColumns: [
      "platform",
      "captured_on",
      "views_gained",
      "reactions_gained",
      "comments_gained",
      "shares_gained",
    ],
    filterColumns: [],
    orderColumns: ["captured_on"],
  },
  looker_posting_time_summary: {
    selectableColumns: [
      "platform",
      "channel_name",
      "publish_day_name",
      "publish_hour",
      "post_count",
      "average_views",
      "median_views",
      "average_calculated_interaction_rate",
    ],
    filterColumns: [],
    orderColumns: ["average_views"],
  },
  looker_content_performance_summary: {
    selectableColumns: [
      "platform",
      "game",
      "content_type",
      "vibe",
      "hook_type",
      "post_count",
      "average_views",
      "median_views",
      "average_calculated_interaction_rate",
    ],
    filterColumns: [],
    orderColumns: ["average_views"],
  },
  looker_schedule_change_proposals: {
    selectableColumns: [
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
    ],
    filterColumns: ["buffer_post_id", "approval_status"],
    orderColumns: ["updated_at", "generated_at", "proposal_id"],
  },
  unlabeled_posts_queue: {
    selectableColumns: [
      "buffer_post_id",
      "platform",
      "channel_name",
      "status",
      "post_text",
      "external_link",
      "published_at_local",
      "views",
      "latest_metric_date",
    ],
    filterColumns: [],
    orderColumns: ["published_at_local", "buffer_post_id"],
  },
  pending_label_queue_exports: {
    selectableColumns: ["buffer_post_id", "queue_state", "claimed_at"],
    filterColumns: ["queue_state"],
    orderColumns: ["buffer_post_id"],
  },
  pending_schedule_proposal_exports: {
    selectableColumns: ["proposal_id", "queue_state", "claimed_at"],
    filterColumns: ["proposal_id"],
    orderColumns: [],
  },
  schedule_change_application_preflight: {
    selectableColumns: [
      "proposal_id",
      "post_last_synced_at",
      "blocking_reasons",
      "is_ready",
      "platform",
      "proposed_due_at_utc",
    ],
    filterColumns: ["proposal_id", "is_ready"],
    orderColumns: ["proposed_due_at_utc"],
  },
  approved_schedule_changes_ready_to_apply: {
    selectableColumns: ["proposal_id"],
    filterColumns: ["proposal_id"],
    orderColumns: [],
  },
  looker_joint_posting_recommendations: {
    selectableColumns: [
      "platform",
      "recommendation_rank",
      "recommended_slot",
      "post_count",
      "platform_post_count",
      "avg_views",
      "median_views",
      "recommendation_score",
      "confidence",
      "latest_metric_date",
      "metrics_age_days",
      "metrics_status",
      "recommendation_ready_for_approval_mode",
    ],
    filterColumns: ["recommendation_rank"],
    orderColumns: ["platform", "recommendation_rank"],
  },
  looker_content_aware_fallback_preview: {
    selectableColumns: [
      "platform",
      "game",
      "content_type",
      "vibe",
      "selected_model_level",
      "selected_model_priority",
      "group_sample_size",
      "minimum_sample_size",
      "recommended_slot",
      "recommendation_score",
      "confidence",
      "metrics_status",
      "recommendation_ready_for_preview",
      "fallback_reason",
    ],
    filterColumns: [],
    orderColumns: ["platform", "selected_model_priority", "group_sample_size"],
  },
  looker_scheduling_cadence_settings: {
    selectableColumns: [
      "platform",
      "content_format",
      "posts_per_week",
      "max_posts_per_day",
      "min_gap_hours",
      "protected_hours",
      "minimum_sample_size",
      "metrics_freshness_limit_days",
      "timezone_name",
      "is_active",
      "updated_at",
    ],
    filterColumns: [],
    orderColumns: ["platform", "content_format"],
  },
  looker_weekly_slot_plan: {
    selectableColumns: [
      "platform",
      "content_format",
      "slot_rank",
      "publish_day_name",
      "scheduled_hour_local",
      "scheduled_time_local",
      "recommended_window",
      "recommendation_score",
      "confidence",
      "supporting_sample_size",
      "metrics_status",
      "timezone_name",
    ],
    filterColumns: [],
    orderColumns: ["platform", "content_format", "slot_rank"],
  },
  looker_content_aware_proposal_preview_summary: {
    selectableColumns: [
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
    ],
    filterColumns: [],
    orderColumns: ["platform"],
  },
} as const satisfies Record<string, RelationPolicy>;

export type ReadOnlyRelation = keyof typeof readOnlyRelationPolicies;

export const readOnlyRelations = Object.freeze(
  Object.keys(readOnlyRelationPolicies) as ReadOnlyRelation[],
);

type EqualityFilter = {
  operator: "eq" | "gte" | "lte";
  column: string;
  value: string | number | boolean;
};

type InFilter = {
  operator: "in";
  column: string;
  value: readonly string[];
};

export type SelectSpecification = {
  relation: ReadOnlyRelation;
  columns: string;
  filters?: readonly (EqualityFilter | InFilter)[];
  order?: readonly {
    column: string;
    ascending: boolean;
  }[];
  limit?: number;
  range?: {
    from: number;
    to: number;
  };
};

export type ReadOnlyReader = {
  select: (specification: SelectSpecification) => Promise<unknown[]>;
};

export function createAuthorizedReader(options: {
  authorize: () => Promise<unknown>;
  execute: (specification: SelectSpecification) => Promise<unknown[]>;
}): ReadOnlyReader {
  return {
    async select(specification) {
      await options.authorize();
      return options.execute(specification);
    },
  };
}
