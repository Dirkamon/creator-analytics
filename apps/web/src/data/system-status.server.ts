import "server-only";

import { z } from "zod";

import { isAuthorizationError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import { getServerEnvironment } from "@/config/env-server";
import { cadenceSettingRowSchema } from "@/data/analytics";
import type { PartialDataError, SystemStatusData } from "@/data/models";
import {
  cadenceSettingsQuery,
  systemBlockedApprovedQuery,
  systemPendingLabelExportQuery,
  systemPostFreshnessQuery,
  systemPreviewReadinessQuery,
  systemProposalErrorsQuery,
  systemUnlinkedBacklogQuery,
} from "@/data/query-specifications";
import type { ReadOnlyReader, SelectSpecification } from "@/data/read-only";
import { serverReadOnlyReader } from "@/data/read-only.server";
import {
  buildSystemStatusData,
  systemBacklogRowSchema,
  systemBlockedApprovedRowSchema,
  systemPostFreshnessRowSchema,
  systemPreviewReadinessRowSchema,
  systemProposalErrorRowSchema,
} from "@/data/system-status";

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

async function readAllRows<T>(options: {
  reader: ReadOnlyReader;
  specification: SelectSpecification;
  schema: z.ZodType<T>;
  section: string;
}): Promise<ReadResult<T>> {
  const pageSize = 500;
  const maximumPages = 100;
  const rows: T[] = [];

  try {
    for (let page = 0; page < maximumPages; page += 1) {
      const pageRows = z.array(options.schema).parse(
        await options.reader.select({
          ...options.specification,
          range: {
            from: page * pageSize,
            to: (page + 1) * pageSize - 1,
          },
        }),
      );
      rows.push(...pageRows);
      if (pageRows.length < pageSize) return { rows, error: null };
    }

    return {
      rows,
      error: {
        section: options.section,
        message: `${options.section} exceeded the read-only page limit.`,
      },
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

export async function getSystemStatusData(
  reader: ReadOnlyReader = serverReadOnlyReader,
  now = new Date(),
): Promise<SystemStatusData> {
  const environment = getServerEnvironment();
  const [posts, errors, blocked, preview, cadence, unlinked, pending] =
    await Promise.all([
      readAllRows({
        reader,
        specification: systemPostFreshnessQuery,
        schema: systemPostFreshnessRowSchema,
        section: "Post and metrics freshness",
      }),
      readAllRows({
        reader,
        specification: systemProposalErrorsQuery,
        schema: systemProposalErrorRowSchema,
        section: "Proposal errors",
      }),
      readAllRows({
        reader,
        specification: systemBlockedApprovedQuery,
        schema: systemBlockedApprovedRowSchema,
        section: "Blocked approved proposals",
      }),
      readRows({
        reader,
        specification: systemPreviewReadinessQuery,
        schema: systemPreviewReadinessRowSchema,
        section: "Proposal preview readiness",
      }),
      readRows({
        reader,
        specification: cadenceSettingsQuery,
        schema: cadenceSettingRowSchema,
        section: "Channel cadence configuration",
      }),
      readAllRows({
        reader,
        specification: systemUnlinkedBacklogQuery,
        schema: systemBacklogRowSchema,
        section: "Unlinked label backlog",
      }),
      readAllRows({
        reader,
        specification: systemPendingLabelExportQuery,
        schema: systemBacklogRowSchema,
        section: "Pending label exports",
      }),
    ]);

  const partialErrors = [
    posts.error,
    errors.error,
    blocked.error,
    preview.error,
    cadence.error,
    unlinked.error,
    pending.error,
  ].filter((error): error is PartialDataError => error !== null);

  return buildSystemStatusData({
    now,
    postSyncStaleHours: environment.CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS,
    metricsStaleHours: environment.CREATOR_ANALYTICS_METRICS_STALE_HOURS,
    postRows: posts.rows,
    postRowsAvailable: posts.error === null,
    proposalErrors: errors.rows,
    proposalErrorsAvailable: errors.error === null,
    blockedApproved: blocked.rows,
    blockedApprovedAvailable: blocked.error === null,
    previewReadiness: preview.rows,
    cadenceSettings: cadence.rows,
    unlinkedRows: unlinked.rows,
    unlinkedAvailable: unlinked.error === null,
    pendingExportRows: pending.rows,
    pendingExportAvailable: pending.error === null,
    partialErrors,
  });
}
