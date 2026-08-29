export const readOnlyRelations = [
  "dashboard_posts",
  "looker_dashboard_posts",
  "looker_daily_growth",
  "looker_posting_time_summary",
  "looker_content_performance_summary",
  "looker_schedule_change_proposals",
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
