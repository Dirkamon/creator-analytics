import "server-only";

import { z } from "zod";

import { isAuthorizationError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import {
  buildLabelQueueData,
  clipGroupRelationshipRowSchema,
  pendingLabelExportRowSchema,
  unlabeledQueueRowSchema,
} from "@/data/label-queue";
import type { LabelQueueData, PartialDataError } from "@/data/models";
import {
  clipGroupRelationshipsQuery,
  pendingLabelQueueExportQuery,
  unlabeledPostsQueueQuery,
} from "@/data/query-specifications";
import type { ReadOnlyReader, SelectSpecification } from "@/data/read-only";
import { serverReadOnlyReader } from "@/data/read-only.server";

type ReadResult<T> = {
  rows: T[];
  error: PartialDataError | null;
};

async function readRows<T>(options: {
  reader: ReadOnlyReader;
  specification: SelectSpecification;
  schema: z.ZodType<T>;
  section: string;
  paginate?: boolean;
}): Promise<ReadResult<T>> {
  try {
    const rows: unknown[] = [];
    const pageSize = 500;

    if (options.paginate) {
      for (let page = 0; page < 20; page += 1) {
        const pageRows = await options.reader.select({
          ...options.specification,
          range: {
            from: page * pageSize,
            to: page * pageSize + pageSize - 1,
          },
        });
        rows.push(...pageRows);
        if (pageRows.length < pageSize) break;
      }
    } else {
      rows.push(...(await options.reader.select(options.specification)));
    }

    return { rows: z.array(options.schema).parse(rows), error: null };
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

export async function getLabelQueueData(
  reader: ReadOnlyReader = serverReadOnlyReader,
): Promise<LabelQueueData> {
  const [unlabeledResult, pendingResult, clipResult] = await Promise.all([
    readRows({
      reader,
      specification: unlabeledPostsQueueQuery,
      schema: unlabeledQueueRowSchema,
      section: "Unlinked posts",
      paginate: true,
    }),
    readRows({
      reader,
      specification: pendingLabelQueueExportQuery,
      schema: pendingLabelExportRowSchema,
      section: "Label export state",
      paginate: true,
    }),
    readRows({
      reader,
      specification: clipGroupRelationshipsQuery,
      schema: clipGroupRelationshipRowSchema,
      section: "Clip Group relationships",
    }),
  ]);

  return buildLabelQueueData({
    unlabeledRows: unlabeledResult.rows,
    pendingRows: pendingResult.rows,
    pendingStateAvailable: pendingResult.error === null,
    clipRows: clipResult.rows,
    partialErrors: [
      unlabeledResult.error,
      pendingResult.error,
      clipResult.error,
    ].filter((error): error is PartialDataError => error !== null),
  });
}
