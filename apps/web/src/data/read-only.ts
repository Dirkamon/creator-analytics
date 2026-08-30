export const readOnlyRelations = [
  "dashboard_posts",
  "looker_dashboard_posts",
  "looker_daily_growth",
  "looker_posting_time_summary",
  "looker_content_performance_summary",
  "looker_schedule_change_proposals",
  "unlabeled_posts_queue",
  "pending_label_queue_exports",
  "pending_schedule_proposal_exports",
  "schedule_change_application_preflight",
  "approved_schedule_changes_ready_to_apply",
  "looker_joint_posting_recommendations",
  "looker_content_aware_fallback_preview",
  "looker_scheduling_cadence_settings",
  "looker_weekly_slot_plan",
  "looker_content_aware_proposal_preview_summary",
] as const;

export type ReadOnlyRelation = (typeof readOnlyRelations)[number];

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
