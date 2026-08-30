import { z } from "zod";

import type { AnalyticsData, PartialDataError } from "@/data/models";

export const numericValue = z
  .union([z.number(), z.string()])
  .transform((value) => Number(value))
  .refine(Number.isFinite);

export const analyticsContentPerformanceRowSchema = z.object({
  platform: z.string(),
  game: z.string().nullable(),
  content_type: z.string().nullable(),
  vibe: z.string().nullable(),
  hook_type: z.string().nullable(),
  post_count: numericValue,
  average_views: numericValue,
  median_views: numericValue,
  average_calculated_interaction_rate: numericValue.nullable(),
});

export const analyticsPostingTimeRowSchema = z.object({
  platform: z.string(),
  channel_name: z.string().nullable(),
  publish_day_name: z.string(),
  publish_hour: numericValue,
  post_count: numericValue,
  average_views: numericValue,
  median_views: numericValue,
  average_calculated_interaction_rate: numericValue.nullable(),
});

export const analyticsJointRecommendationRowSchema = z.object({
  platform: z.string(),
  recommendation_rank: numericValue,
  recommended_slot: z.string(),
  post_count: numericValue,
  platform_post_count: numericValue,
  avg_views: numericValue,
  median_views: numericValue,
  recommendation_score: numericValue,
  confidence: z.string(),
  latest_metric_date: z.string().nullable(),
  metrics_age_days: numericValue.nullable(),
  metrics_status: z.string(),
  recommendation_ready_for_approval_mode: z.boolean(),
});

export const analyticsFallbackRowSchema = z.object({
  platform: z.string(),
  game: z.string().nullable(),
  content_type: z.string().nullable(),
  vibe: z.string().nullable(),
  selected_model_level: z.string(),
  selected_model_priority: numericValue,
  group_sample_size: numericValue,
  minimum_sample_size: numericValue,
  recommended_slot: z.string(),
  recommendation_score: numericValue,
  confidence: z.string(),
  metrics_status: z.string(),
  recommendation_ready_for_preview: z.boolean(),
  fallback_reason: z.string(),
});

export const cadenceSettingRowSchema = z.object({
  platform: z.string(),
  content_format: z.string(),
  posts_per_week: numericValue,
  max_posts_per_day: numericValue,
  min_gap_hours: numericValue,
  protected_hours: numericValue,
  minimum_sample_size: numericValue,
  metrics_freshness_limit_days: numericValue,
  timezone_name: z.string(),
  is_active: z.boolean(),
  updated_at: z.string(),
});

export const weeklySlotRowSchema = z.object({
  platform: z.string(),
  content_format: z.string(),
  slot_rank: numericValue,
  publish_day_name: z.string(),
  scheduled_hour_local: numericValue,
  scheduled_time_local: z.string(),
  recommended_window: z.string(),
  recommendation_score: numericValue,
  confidence: z.string(),
  supporting_sample_size: numericValue,
  metrics_status: z.string(),
  timezone_name: z.string(),
});

type ContentPerformanceRow = z.infer<
  typeof analyticsContentPerformanceRowSchema
>;
type PostingTimeRow = z.infer<typeof analyticsPostingTimeRowSchema>;
type JointRecommendationRow = z.infer<
  typeof analyticsJointRecommendationRowSchema
>;
type FallbackRow = z.infer<typeof analyticsFallbackRowSchema>;
export type CadenceSettingRow = z.infer<typeof cadenceSettingRowSchema>;
type WeeklySlotRow = z.infer<typeof weeklySlotRowSchema>;

export function mapCadenceSettings(
  rows: CadenceSettingRow[],
): AnalyticsData["cadenceSettings"] {
  return rows.map((row) => ({
    platform: row.platform,
    contentFormat: row.content_format,
    postsPerWeek: row.posts_per_week,
    maxPostsPerDay: row.max_posts_per_day,
    minGapHours: row.min_gap_hours,
    protectedHours: row.protected_hours,
    minimumSampleSize: row.minimum_sample_size,
    metricsFreshnessLimitDays: row.metrics_freshness_limit_days,
    timezoneName: row.timezone_name,
    isActive: row.is_active,
    updatedAt: row.updated_at,
  }));
}

export function buildAnalyticsData(options: {
  contentPerformance: ContentPerformanceRow[];
  postingWindows: PostingTimeRow[];
  recommendations: JointRecommendationRow[];
  fallbackSelections: FallbackRow[];
  cadenceSettings: CadenceSettingRow[];
  weeklySlots: WeeklySlotRow[];
  partialErrors: PartialDataError[];
}): AnalyticsData {
  return {
    contentPerformance: options.contentPerformance.map((row) => ({
      platform: row.platform,
      game: row.game,
      contentType: row.content_type,
      vibe: row.vibe,
      hookType: row.hook_type,
      postCount: row.post_count,
      averageViews: row.average_views,
      medianViews: row.median_views,
      averageInteractionRate: row.average_calculated_interaction_rate,
    })),
    postingWindows: options.postingWindows.map((row) => ({
      platform: row.platform,
      channelName: row.channel_name?.trim() || "Unnamed channel",
      day: row.publish_day_name,
      hour: row.publish_hour,
      postCount: row.post_count,
      averageViews: row.average_views,
      medianViews: row.median_views,
      averageInteractionRate: row.average_calculated_interaction_rate,
    })),
    recommendations: options.recommendations.map((row) => ({
      platform: row.platform,
      rank: row.recommendation_rank,
      recommendedSlot: row.recommended_slot,
      sampleSize: row.post_count,
      platformSampleSize: row.platform_post_count,
      averageViews: row.avg_views,
      medianViews: row.median_views,
      score: row.recommendation_score,
      confidence: row.confidence,
      latestMetricDate: row.latest_metric_date,
      metricsAgeDays: row.metrics_age_days,
      metricsStatus: row.metrics_status,
      readyForApprovalMode: row.recommendation_ready_for_approval_mode,
    })),
    fallbackSelections: options.fallbackSelections.map((row) => ({
      platform: row.platform,
      game: row.game,
      contentType: row.content_type,
      vibe: row.vibe,
      selectedModelLevel: row.selected_model_level,
      selectedModelPriority: row.selected_model_priority,
      groupSampleSize: row.group_sample_size,
      minimumSampleSize: row.minimum_sample_size,
      recommendedSlot: row.recommended_slot,
      score: row.recommendation_score,
      confidence: row.confidence,
      metricsStatus: row.metrics_status,
      readyForPreview: row.recommendation_ready_for_preview,
      fallbackReason: row.fallback_reason,
    })),
    cadenceSettings: mapCadenceSettings(options.cadenceSettings),
    weeklySlots: options.weeklySlots.map((row) => ({
      platform: row.platform,
      contentFormat: row.content_format,
      slotRank: row.slot_rank,
      day: row.publish_day_name,
      hour: row.scheduled_hour_local,
      localTime: row.scheduled_time_local,
      recommendedWindow: row.recommended_window,
      score: row.recommendation_score,
      confidence: row.confidence,
      sampleSize: row.supporting_sample_size,
      metricsStatus: row.metrics_status,
      timezoneName: row.timezone_name,
    })),
    partialErrors: options.partialErrors,
  };
}
