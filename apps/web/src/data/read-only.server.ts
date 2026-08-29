import "server-only";

import { requireAuthorizedUser } from "@/auth/authorization.server";
import {
  createAuthorizedReader,
  type SelectSpecification,
} from "@/data/read-only";
import { createServerDataClient } from "@/lib/supabase/server-data";

class ReadOnlyQueryError extends Error {
  constructor(relation: string) {
    super(`The read-only query for ${relation} could not be completed.`);
    this.name = "ReadOnlyQueryError";
  }
}

async function executeSelect(
  specification: SelectSpecification,
): Promise<unknown[]> {
  const supabase = createServerDataClient();
  let query = supabase
    .from(specification.relation)
    .select(specification.columns);

  for (const filter of specification.filters ?? []) {
    if (filter.operator === "in") {
      query = query.in(filter.column, [...filter.value]);
    } else if (filter.operator === "eq") {
      query = query.eq(filter.column, filter.value);
    } else if (filter.operator === "gte") {
      query = query.gte(filter.column, filter.value);
    } else {
      query = query.lte(filter.column, filter.value);
    }
  }

  for (const order of specification.order ?? []) {
    query = query.order(order.column, { ascending: order.ascending });
  }

  if (specification.limit) {
    query = query.limit(specification.limit);
  }

  if (specification.range) {
    query = query.range(specification.range.from, specification.range.to);
  }

  const { data, error } = await query;

  if (error || !data) {
    throw new ReadOnlyQueryError(specification.relation);
  }

  return data;
}

export const serverReadOnlyReader = createAuthorizedReader({
  authorize: requireAuthorizedUser,
  execute: executeSelect,
});
