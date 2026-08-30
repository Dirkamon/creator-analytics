import {
  readOnlyRelationPolicies,
  type SelectSpecification,
} from "@/data/read-only";

const maximumRowsPerQuery = 500;

export class InvalidReadOnlyQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidReadOnlyQueryError";
  }
}

export type CompiledReadOnlyQuery = {
  text: string;
  parameters: readonly (string | number | boolean)[];
};

function quoteIdentifier(identifier: string): string {
  return `"${identifier.replaceAll('"', '""')}"`;
}

function requireAllowedColumn(
  column: string,
  allowedColumns: readonly string[],
  context: string,
) {
  if (!allowedColumns.includes(column)) {
    throw new InvalidReadOnlyQueryError(
      `${context} is not permitted by the read-only query contract.`,
    );
  }
}

export function compileSelectSpecification(
  specification: SelectSpecification,
): CompiledReadOnlyQuery {
  if (!Object.hasOwn(readOnlyRelationPolicies, specification.relation)) {
    throw new InvalidReadOnlyQueryError(
      "The requested relation is not permitted by the read-only query contract.",
    );
  }

  const policy = readOnlyRelationPolicies[specification.relation];
  const selectedColumns = specification.columns
    .split(",")
    .map((column) => column.trim())
    .filter(Boolean);

  if (
    selectedColumns.length === 0 ||
    new Set(selectedColumns).size !== selectedColumns.length
  ) {
    throw new InvalidReadOnlyQueryError(
      "A read-only query must select unique named columns.",
    );
  }

  selectedColumns.forEach((column) =>
    requireAllowedColumn(column, policy.selectableColumns, "Selected column"),
  );

  const parameters: (string | number | boolean)[] = [];
  const clauses: string[] = [];

  for (const filter of specification.filters ?? []) {
    requireAllowedColumn(filter.column, policy.filterColumns, "Filter column");
    const quotedColumn = quoteIdentifier(filter.column);

    if (filter.operator === "in") {
      if (
        filter.value.length === 0 ||
        filter.value.length > maximumRowsPerQuery
      ) {
        throw new InvalidReadOnlyQueryError(
          "An IN filter must contain between 1 and 500 values.",
        );
      }

      const placeholders = filter.value.map((value) => {
        parameters.push(value);
        return `$${parameters.length}`;
      });
      clauses.push(`${quotedColumn} in (${placeholders.join(", ")})`);
      continue;
    }

    parameters.push(filter.value);
    const operator =
      filter.operator === "eq" ? "=" : filter.operator === "gte" ? ">=" : "<=";
    clauses.push(`${quotedColumn} ${operator} $${parameters.length}`);
  }

  const orderClauses = (specification.order ?? []).map((order) => {
    requireAllowedColumn(order.column, policy.orderColumns, "Order column");
    return `${quoteIdentifier(order.column)} ${order.ascending ? "asc" : "desc"}`;
  });

  if (specification.limit !== undefined && specification.range !== undefined) {
    throw new InvalidReadOnlyQueryError(
      "A read-only query cannot combine limit and range.",
    );
  }

  let rowWindow = "";
  if (specification.limit !== undefined) {
    if (
      !Number.isInteger(specification.limit) ||
      specification.limit < 1 ||
      specification.limit > maximumRowsPerQuery
    ) {
      throw new InvalidReadOnlyQueryError(
        "A read-only query limit must be between 1 and 500.",
      );
    }
    parameters.push(specification.limit);
    rowWindow = ` limit $${parameters.length}`;
  }

  if (specification.range !== undefined) {
    const { from, to } = specification.range;
    const count = to - from + 1;
    if (
      !Number.isInteger(from) ||
      !Number.isInteger(to) ||
      from < 0 ||
      to < from ||
      count > maximumRowsPerQuery
    ) {
      throw new InvalidReadOnlyQueryError(
        "A read-only query range must request between 1 and 500 rows.",
      );
    }
    parameters.push(count, from);
    rowWindow = ` limit $${parameters.length - 1} offset $${parameters.length}`;
  }

  return {
    text:
      [
        `select ${selectedColumns.map(quoteIdentifier).join(", ")}`,
        `from ${quoteIdentifier("creator_app")}.${quoteIdentifier(specification.relation)}`,
        clauses.length > 0 ? `where ${clauses.join(" and ")}` : "",
        orderClauses.length > 0 ? `order by ${orderClauses.join(", ")}` : "",
      ]
        .filter(Boolean)
        .join(" ") + rowWindow,
    parameters,
  };
}
