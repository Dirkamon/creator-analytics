import "server-only";

import { z } from "zod";

import { isAuthorizationError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import type { PartialDataError, ScheduleApprovalsData } from "@/data/models";
import {
  pendingScheduleProposalExportQuery,
  proposalPostSyncQuery,
  readyScheduleChangesQuery,
  scheduleApplicationPreflightQuery,
  scheduleProposalHistoryQuery,
} from "@/data/query-specifications";
import type { ReadOnlyReader, SelectSpecification } from "@/data/read-only";
import { serverReadOnlyReader } from "@/data/read-only.server";
import {
  applicationPreflightRowSchema,
  buildScheduleApprovalsData,
  proposalPostSyncRowSchema,
  readyScheduleChangeRowSchema,
  scheduleProposalExportRowSchema,
  scheduleProposalRowSchema,
} from "@/data/schedule-approvals";

type ReadResult<T> = {
  rows: T[];
  error: PartialDataError | null;
};

async function readRows<T>(options: {
  reader: ReadOnlyReader;
  specification: SelectSpecification;
  schema: z.ZodType<T>;
  section: string;
}): Promise<ReadResult<T>> {
  try {
    return {
      rows: z
        .array(options.schema)
        .parse(await options.reader.select(options.specification)),
      error: null,
    };
  } catch (error) {
    if (isAuthorizationError(error) || error instanceof ConfigurationError) {
      throw error;
    }

    return {
      rows: [],
      error: {
        section: options.section,
        message: `${options.section} is temporarily unavailable.`,
      },
    };
  }
}

export async function getScheduleApprovalsData(
  reader: ReadOnlyReader = serverReadOnlyReader,
): Promise<ScheduleApprovalsData> {
  const proposalResult = await readRows({
    reader,
    specification: scheduleProposalHistoryQuery,
    schema: scheduleProposalRowSchema,
    section: "Proposal history",
  });

  if (proposalResult.rows.length === 0) {
    return {
      proposals: [],
      partialErrors: proposalResult.error ? [proposalResult.error] : [],
    };
  }

  const proposalIds = proposalResult.rows.map((row) => row.proposal_id);
  const approvedIds = proposalResult.rows
    .filter((row) => row.approval_status === "Approved")
    .map((row) => row.proposal_id);
  const bufferPostIds = Array.from(
    new Set(proposalResult.rows.map((row) => row.buffer_post_id)),
  );

  const [exportResult, preflightResult, readyResult, postResult] =
    await Promise.all([
      readRows({
        reader,
        specification: pendingScheduleProposalExportQuery(proposalIds),
        schema: scheduleProposalExportRowSchema,
        section: "Proposal export state",
      }),
      approvedIds.length === 0
        ? Promise.resolve({ rows: [], error: null })
        : readRows({
            reader,
            specification: scheduleApplicationPreflightQuery(approvedIds),
            schema: applicationPreflightRowSchema,
            section: "Application preflight",
          }),
      approvedIds.length === 0
        ? Promise.resolve({ rows: [], error: null })
        : readRows({
            reader,
            specification: readyScheduleChangesQuery(approvedIds),
            schema: readyScheduleChangeRowSchema,
            section: "Make application readiness",
          }),
      readRows({
        reader,
        specification: proposalPostSyncQuery(bufferPostIds),
        schema: proposalPostSyncRowSchema,
        section: "Post synchronization state",
      }),
    ]);

  const partialErrors = [
    proposalResult.error,
    exportResult.error,
    preflightResult.error,
    readyResult.error,
    postResult.error,
  ].filter((error): error is PartialDataError => error !== null);

  return buildScheduleApprovalsData({
    proposals: proposalResult.rows,
    exports: exportResult.rows,
    preflightRows: preflightResult.rows,
    readyRows: readyResult.rows,
    postRows: postResult.rows,
    exportStateAvailable: exportResult.error === null,
    preflightAvailable: preflightResult.error === null,
    readyStateAvailable: readyResult.error === null,
    partialErrors,
  });
}
