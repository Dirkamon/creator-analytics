import "server-only";

import { requireAuthorizedUser } from "@/auth/authorization.server";
import {
  createAuthorizedReader,
  type SelectSpecification,
} from "@/data/read-only";
import { compileSelectSpecification } from "@/data/database-query";
import { getServerDataClient } from "@/lib/database/server-data";

class ReadOnlyQueryError extends Error {
  constructor(relation: string) {
    super(`The read-only query for ${relation} could not be completed.`);
    this.name = "ReadOnlyQueryError";
  }
}

async function executeSelect(
  specification: SelectSpecification,
): Promise<unknown[]> {
  const compiledQuery = compileSelectSpecification(specification);

  try {
    const database = getServerDataClient();
    const rows = await database.unsafe(
      compiledQuery.text,
      [...compiledQuery.parameters],
      { prepare: false },
    );
    return [...rows];
  } catch {
    throw new ReadOnlyQueryError(specification.relation);
  }
}

export const serverReadOnlyReader = createAuthorizedReader({
  authorize: requireAuthorizedUser,
  execute: executeSelect,
});
