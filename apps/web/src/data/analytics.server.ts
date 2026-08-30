import "server-only";

import { z } from "zod";

import { isAuthorizationError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import {
  analyticsContentPerformanceRowSchema,
  analyticsFallbackRowSchema,
  analyticsJointRecommendationRowSchema,
  analyticsPostingTimeRowSchema,
  buildAnalyticsData,
  cadenceSettingRowSchema,
  weeklySlotRowSchema,
} from "@/data/analytics";
import type { AnalyticsData, PartialDataError } from "@/data/models";
import {
  analyticsContentPerformanceQuery,
  analyticsFallbackQuery,
  analyticsJointRecommendationsQuery,
  analyticsPostingTimeQuery,
  cadenceSettingsQuery,
  weeklySlotPlanQuery,
} from "@/data/query-specifications";
import type { ReadOnlyReader, SelectSpecification } from "@/data/read-only";
import { serverReadOnlyReader } from "@/data/read-only.server";

type ReadResult<T> = { rows: T[]; error: PartialDataError | null };

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

export async function getAnalyticsData(
  reader: ReadOnlyReader = serverReadOnlyReader,
): Promise<AnalyticsData> {
  const [content, posting, recommendations, fallback, cadence, weekly] =
    await Promise.all([
      readRows({
        reader,
        specification: analyticsContentPerformanceQuery,
        schema: analyticsContentPerformanceRowSchema,
        section: "Content performance",
      }),
      readRows({
        reader,
        specification: analyticsPostingTimeQuery,
        schema: analyticsPostingTimeRowSchema,
        section: "Posting windows",
      }),
      readRows({
        reader,
        specification: analyticsJointRecommendationsQuery,
        schema: analyticsJointRecommendationRowSchema,
        section: "Platform recommendations",
      }),
      readRows({
        reader,
        specification: analyticsFallbackQuery,
        schema: analyticsFallbackRowSchema,
        section: "Recommendation hierarchy",
      }),
      readRows({
        reader,
        specification: cadenceSettingsQuery,
        schema: cadenceSettingRowSchema,
        section: "Cadence settings",
      }),
      readRows({
        reader,
        specification: weeklySlotPlanQuery,
        schema: weeklySlotRowSchema,
        section: "Weekly slot plan",
      }),
    ]);

  return buildAnalyticsData({
    contentPerformance: content.rows,
    postingWindows: posting.rows,
    recommendations: recommendations.rows,
    fallbackSelections: fallback.rows,
    cadenceSettings: cadence.rows,
    weeklySlots: weekly.rows,
    partialErrors: [
      content.error,
      posting.error,
      recommendations.error,
      fallback.error,
      cadence.error,
      weekly.error,
    ].filter((error): error is PartialDataError => error !== null),
  });
}
