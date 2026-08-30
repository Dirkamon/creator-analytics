import { readdirSync, readFileSync } from "node:fs";
import { extname, join } from "node:path";

import { describe, expect, it, vi } from "vitest";

import {
  contentPerformanceQuery,
  clipGroupRelationshipsQuery,
  dailyGrowthQuery,
  dashboardPostQuery,
  pendingLabelQueueExportQuery,
  pendingScheduleProposalExportQuery,
  postingTimeQuery,
  proposalPostSyncQuery,
  proposalStatusQuery,
  readyScheduleChangesQuery,
  scheduleApplicationPreflightQuery,
  scheduleProposalHistoryQuery,
  unlabeledPostsQueueQuery,
  upcomingPostsQuery,
} from "@/data/query-specifications";
import { createAuthorizedReader, readOnlyRelations } from "@/data/read-only";

function sourceFiles(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory()
      ? sourceFiles(path)
      : extname(entry.name) === ".ts"
        ? [path]
        : [];
  });
}

describe("read-only data boundary", () => {
  it("authorizes before every SELECT execution", async () => {
    const events: string[] = [];
    const authorize = vi.fn(async () => {
      events.push("authorize");
    });
    const execute = vi.fn(async () => {
      events.push("select");
      return [];
    });
    const reader = createAuthorizedReader({ authorize, execute });

    await reader.select(dashboardPostQuery);
    await reader.select(dailyGrowthQuery);

    expect(events).toEqual(["authorize", "select", "authorize", "select"]);
    expect(authorize).toHaveBeenCalledTimes(2);
  });

  it("never executes a denied request", async () => {
    const execute = vi.fn(async () => []);
    const reader = createAuthorizedReader({
      authorize: async () => {
        throw new Error("denied");
      },
      execute,
    });

    await expect(reader.select(dashboardPostQuery)).rejects.toThrow("denied");
    expect(execute).not.toHaveBeenCalled();
  });

  it("uses named, minimal columns against the approved read surfaces", () => {
    const specifications = [
      dashboardPostQuery,
      dailyGrowthQuery,
      postingTimeQuery,
      contentPerformanceQuery,
      upcomingPostsQuery("2026-08-29T12:00:00.000Z"),
      proposalStatusQuery(["SANITIZED_POST"]),
      unlabeledPostsQueueQuery,
      pendingLabelQueueExportQuery,
      clipGroupRelationshipsQuery,
      scheduleProposalHistoryQuery,
      pendingScheduleProposalExportQuery([
        "00000000-0000-4000-8000-000000000001",
      ]),
      scheduleApplicationPreflightQuery([
        "00000000-0000-4000-8000-000000000001",
      ]),
      readyScheduleChangesQuery(["00000000-0000-4000-8000-000000000001"]),
      proposalPostSyncQuery(["SANITIZED_POST"]),
    ];

    for (const specification of specifications) {
      expect(readOnlyRelations).toContain(specification.relation);
      expect(specification.columns).not.toContain("*");
      expect(specification.columns).not.toMatch(/raw_(data|metrics)/i);
      expect(specification.columns).not.toContain("buffer_organization_id");
      expect(specification.columns).not.toContain("buffer_channel_id");
      expect(specification.columns).not.toMatch(/raw_(data|metrics)/i);
    }
  });

  it("keeps heavy scheduling diagnostics page-local", () => {
    const pageOwnedRelations = [
      scheduleProposalHistoryQuery.relation,
      scheduleApplicationPreflightQuery([
        "00000000-0000-4000-8000-000000000001",
      ]).relation,
      readyScheduleChangesQuery(["00000000-0000-4000-8000-000000000001"])
        .relation,
    ];

    expect(pageOwnedRelations).toEqual([
      "looker_schedule_change_proposals",
      "schedule_change_application_preflight",
      "approved_schedule_changes_ready_to_apply",
    ]);
    expect(readOnlyRelations).not.toContain(
      "looker_content_aware_proposal_preview",
    );
  });

  it("contains no database mutation or RPC calls in the data layer", () => {
    const dataDirectory = join(process.cwd(), "src", "data");
    const source = sourceFiles(dataDirectory)
      .filter((path) => !path.endsWith(".test.ts"))
      .map((path) => readFileSync(path, "utf8"))
      .join("\n");

    expect(source).not.toMatch(/\.(insert|update|upsert|delete|rpc)\s*\(/);
    expect(source).not.toMatch(/select\s*\(\s*["']\*["']/);
  });
});
