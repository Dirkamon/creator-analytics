import "server-only";

import { z } from "zod";

import { isAuthorizationError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import type { DashboardData, PartialDataError } from "@/data/models";
import {
  contentPerformanceQuery,
  dailyGrowthQuery,
  dashboardPostQuery,
  postingTimeQuery,
} from "@/data/query-specifications";
import type { ReadOnlyReader, SelectSpecification } from "@/data/read-only";
import { serverReadOnlyReader } from "@/data/read-only.server";
import { sanitizeExternalUrl } from "@/lib/format";

const numericValue = z
  .union([z.number(), z.string()])
  .transform((value) => Number(value))
  .refine(Number.isFinite);

const dashboardPostSchema = z.object({
  platform: z.string(),
  channel_name: z.string().nullable(),
  status: z.string(),
  post_text: z.string().nullable(),
  external_link: z.string().nullable(),
  published_at_utc: z.string().nullable(),
  label_status: z.string(),
  clip_group: z.string().nullable(),
  game: z.string().nullable(),
  content_type: z.string().nullable(),
  latest_metric_date: z.string().nullable(),
  views: numericValue.nullable(),
  reactions: numericValue.nullable(),
  comments: numericValue.nullable(),
  shares: numericValue.nullable(),
  saves: numericValue.nullable(),
  calculated_interaction_rate: numericValue.nullable(),
});

const dailyGrowthSchema = z.object({
  platform: z.string(),
  captured_on: z.string(),
  views_gained: numericValue,
  reactions_gained: numericValue,
  comments_gained: numericValue,
  shares_gained: numericValue,
});

const postingTimeSchema = z.object({
  platform: z.string(),
  publish_day_name: z.string(),
  publish_hour: numericValue,
  post_count: numericValue,
  average_views: numericValue,
  average_calculated_interaction_rate: numericValue.nullable(),
});

const contentPerformanceSchema = z.object({
  platform: z.string(),
  game: z.string().nullable(),
  content_type: z.string().nullable(),
  vibe: z.string().nullable(),
  post_count: numericValue,
  average_views: numericValue,
  average_calculated_interaction_rate: numericValue.nullable(),
});

type SectionResult<T> = {
  data: T[];
  error: PartialDataError | null;
};

async function readSection<T>(options: {
  reader: ReadOnlyReader;
  specification: SelectSpecification;
  schema: z.ZodType<T>;
  section: string;
  paginate?: boolean;
}): Promise<SectionResult<T>> {
  try {
    const pageSize = 500;
    const rows: unknown[] = [];

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

    return {
      data: z.array(options.schema).parse(rows),
      error: null,
    };
  } catch (error) {
    if (isAuthorizationError(error) || error instanceof ConfigurationError) {
      throw error;
    }

    return {
      data: [],
      error: {
        section: options.section,
        message: `${options.section} is temporarily unavailable.`,
      },
    };
  }
}

export async function getDashboardData(
  reader: ReadOnlyReader = serverReadOnlyReader,
): Promise<DashboardData> {
  const [postsResult, growthResult, timesResult, contentResult] =
    await Promise.all([
      readSection({
        reader,
        specification: dashboardPostQuery,
        schema: dashboardPostSchema,
        section: "Post performance",
        paginate: true,
      }),
      readSection({
        reader,
        specification: dailyGrowthQuery,
        schema: dailyGrowthSchema,
        section: "Daily growth",
      }),
      readSection({
        reader,
        specification: postingTimeQuery,
        schema: postingTimeSchema,
        section: "Posting-time performance",
      }),
      readSection({
        reader,
        specification: contentPerformanceQuery,
        schema: contentPerformanceSchema,
        section: "Content performance",
      }),
    ]);

  const posts = postsResult.data;
  const totalViews = posts.reduce((sum, post) => sum + (post.views ?? 0), 0);
  const interactionRates = posts
    .map((post) => post.calculated_interaction_rate)
    .filter((value): value is number => value !== null);
  const metricDates = posts
    .map((post) => post.latest_metric_date)
    .filter((value): value is string => value !== null)
    .sort();

  return {
    summary: {
      postCount: posts.length,
      totalViews,
      averageViews: posts.length === 0 ? 0 : totalViews / posts.length,
      averageInteractionRate:
        interactionRates.length === 0
          ? null
          : interactionRates.reduce((sum, value) => sum + value, 0) /
            interactionRates.length,
    },
    recentPosts: posts.slice(0, 6).map((post) => ({
      platform: post.platform,
      channelName: post.channel_name,
      caption: post.post_text?.trim() || "Untitled post",
      externalLink: sanitizeExternalUrl(post.external_link),
      publishedAt: post.published_at_utc,
      labelStatus: post.label_status,
      clipGroup: post.clip_group,
      views: post.views,
      interactions:
        (post.reactions ?? 0) +
        (post.comments ?? 0) +
        (post.shares ?? 0) +
        (post.saves ?? 0),
    })),
    growth: growthResult.data.slice(0, 24).map((row) => ({
      platform: row.platform,
      capturedOn: row.captured_on,
      viewsGained: row.views_gained,
    })),
    topTimes: timesResult.data.map((row) => ({
      platform: row.platform,
      day: row.publish_day_name.trim(),
      hour: row.publish_hour,
      postCount: row.post_count,
      averageViews: row.average_views,
    })),
    topContent: contentResult.data.map((row) => ({
      platform: row.platform,
      game: row.game,
      contentType: row.content_type,
      vibe: row.vibe,
      postCount: row.post_count,
      averageViews: row.average_views,
    })),
    latestMetricDate: metricDates.at(-1) ?? null,
    partialErrors: [
      postsResult.error,
      growthResult.error,
      timesResult.error,
      contentResult.error,
    ].filter((error): error is PartialDataError => error !== null),
  };
}
