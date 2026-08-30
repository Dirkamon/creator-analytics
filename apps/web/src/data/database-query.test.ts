import { describe, expect, it } from "vitest";

import {
  compileSelectSpecification,
  InvalidReadOnlyQueryError,
} from "@/data/database-query";
import type { SelectSpecification } from "@/data/read-only";

describe("restricted database query compiler", () => {
  it("qualifies the private schema and parameterizes every value", () => {
    const compiled = compileSelectSpecification({
      relation: "dashboard_posts",
      columns: "buffer_post_id,platform,due_at",
      filters: [
        { operator: "eq", column: "status", value: "scheduled" },
        {
          operator: "gte",
          column: "due_at",
          value: "2026-08-30T12:00:00.000Z",
        },
      ],
      order: [{ column: "due_at", ascending: true }],
      limit: 25,
    });

    expect(compiled).toEqual({
      text: 'select "buffer_post_id", "platform", "due_at" from "creator_app"."dashboard_posts" where "status" = $1 and "due_at" >= $2 order by "due_at" asc limit $3',
      parameters: ["scheduled", "2026-08-30T12:00:00.000Z", 25],
    });
    expect(compiled.text).not.toContain("scheduled");
  });

  it("parameterizes IN filters without interpolating identifiers or values", () => {
    const compiled = compileSelectSpecification({
      relation: "pending_schedule_proposal_exports",
      columns: "proposal_id",
      filters: [
        {
          operator: "in",
          column: "proposal_id",
          value: [
            "00000000-0000-4000-8000-000000000001",
            "00000000-0000-4000-8000-000000000002",
          ],
        },
      ],
    });

    expect(compiled.text).toBe(
      'select "proposal_id" from "creator_app"."pending_schedule_proposal_exports" where "proposal_id" in ($1, $2)',
    );
    expect(compiled.parameters).toHaveLength(2);
  });

  it.each([
    {
      name: "unknown relation",
      specification: {
        relation: "posts",
        columns: "buffer_post_id",
      },
    },
    {
      name: "unknown selected column",
      specification: {
        relation: "dashboard_posts",
        columns: "raw_data",
      },
    },
    {
      name: "unknown filter column",
      specification: {
        relation: "dashboard_posts",
        columns: "platform",
        filters: [{ operator: "eq", column: "raw_data", value: "x" }],
      },
    },
    {
      name: "unknown ordering column",
      specification: {
        relation: "dashboard_posts",
        columns: "platform",
        order: [{ column: "post_text", ascending: true }],
      },
    },
  ])("rejects $name", ({ specification }) => {
    expect(() =>
      compileSelectSpecification(
        specification as unknown as SelectSpecification,
      ),
    ).toThrow(InvalidReadOnlyQueryError);
  });

  it("bounds list, limit, and range expansion", () => {
    expect(() =>
      compileSelectSpecification({
        relation: "dashboard_posts",
        columns: "platform",
        limit: 501,
      }),
    ).toThrow(InvalidReadOnlyQueryError);

    expect(() =>
      compileSelectSpecification({
        relation: "dashboard_posts",
        columns: "platform",
        range: { from: 0, to: 500 },
      }),
    ).toThrow(InvalidReadOnlyQueryError);

    expect(() =>
      compileSelectSpecification({
        relation: "looker_schedule_change_proposals",
        columns: "proposal_id",
        filters: [{ operator: "in", column: "buffer_post_id", value: [] }],
      }),
    ).toThrow(InvalidReadOnlyQueryError);
  });
});
