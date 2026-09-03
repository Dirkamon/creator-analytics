import "server-only";

import { z } from "zod";

import { isAuthorizationError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import type {
  DashboardData,
  PartialDataError,
  ReportingPost,
  TopPostsData,
} from "@/data/models";
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
  buffer_post_id: z.string(),
  platform: z.string(),
  channel_name: z.string().nullable(),
  status: z.string(),
  post_text: z.string().nullable(),
  external_link: z.string().nullable(),
  published_at_utc: z.string().nullable(),
  publish_day_name: z.string().nullable(),
  publish_hour: numericValue.nullable(),
  label_status: z.string(),
  clip_group: z.string().nullable(),
  game: z.string().nullable(),
  content_type: z.string().nullable(),
  vibe: z.string().nullable(),
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

type DashboardPostRow = z.infer<typeof dashboardPostSchema>;

function mapReportingPost(post: DashboardPostRow): ReportingPost {
  return {
    key: post.buffer_post_id,
    platform: post.platform,
    channelName: post.channel_name,
    caption: post.post_text?.trim() || "Untitled post",
    externalLink: sanitizeExternalUrl(post.external_link),
    publishedAt: post.published_at_utc,
    publishDay: post.publish_day_name?.trim() || null,
    publishHour: post.publish_hour,
    labelStatus: post.label_status,
    clipGroup: post.clip_group,
    game: post.game,
    contentType: post.content_type,
    vibe: post.vibe,
    views: post.views,
    reactions: post.reactions ?? 0,
    comments: post.comments ?? 0,
    shares: post.shares ?? 0,
    saves: post.saves ?? 0,
    interactionRate: post.calculated_interaction_rate,
  };
}

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

function readReportingPosts(reader: ReadOnlyReader) {
  return readSection({
    reader,
    specification: dashboardPostQuery,
    schema: dashboardPostSchema,
    section: "Post performance",
    paginate: true,
  });
}

export async function getTopPostsData(
  reader: ReadOnlyReader = serverReadOnlyReader,
): Promise<TopPostsData> {
  const result = await readReportingPosts(reader);

  return {
    posts: result.data.map(mapReportingPost),
    partialErrors: result.error ? [result.error] : [],
  };
}

export async function getDashboardData(
  reader: ReadOnlyReader = serverReadOnlyReader,
): Promise<DashboardData> {
  const [postsResult, growthResult, timesResult, contentResult] =
    await Promise.all([
      readReportingPosts(reader),
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
  const filterablePosts = posts.map(mapReportingPost);
  const totalViews = posts.reduce((sum, post) => sum + (post.views ?? 0), 0);
  const totalReactions = posts.reduce(
    (sum, post) => sum + (post.reactions ?? 0),
    0,
  );
  const totalComments = posts.reduce(
    (sum, post) => sum + (post.comments ?? 0),
    0,
  );
  const totalShares = posts.reduce((sum, post) => sum + (post.shares ?? 0), 0);
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
      totalReactions,
      totalComments,
      totalShares,
      averageViews: posts.length === 0 ? 0 : totalViews / posts.length,
      averageInteractionRate:
        interactionRates.length === 0
          ? null
          : interactionRates.reduce((sum, value) => sum + value, 0) /
            interactionRates.length,
    },
    filterablePosts,
    recentPosts: filterablePosts.slice(0, 6).map((post) => ({
      platform: post.platform,
      channelName: post.channelName,
      caption: post.caption,
      externalLink: post.externalLink,
      publishedAt: post.publishedAt,
      labelStatus: post.labelStatus,
      clipGroup: post.clipGroup,
      views: post.views,
      interactions: post.reactions + post.comments + post.shares + post.saves,
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
