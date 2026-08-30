import { describe, expect, it } from "vitest";

import {
  analyticsContentPerformanceRowSchema,
  analyticsFallbackRowSchema,
  analyticsJointRecommendationRowSchema,
  analyticsPostingTimeRowSchema,
  buildAnalyticsData,
  cadenceSettingRowSchema,
  weeklySlotRowSchema,
} from "@/data/analytics";

describe("Analytics data mapping", () => {
  it("maps database-computed evidence without recalculating recommendations", () => {
    const result = buildAnalyticsData({
      contentPerformance: [
        analyticsContentPerformanceRowSchema.parse({
          platform: "tiktok",
          game: "Sample Game",
          content_type: "Highlight",
          vibe: "Chaotic",
          hook_type: null,
          post_count: "8",
          average_views: "8400.5",
          median_views: "8100",
          average_calculated_interaction_rate: "6.2",
        }),
      ],
      postingWindows: [
        analyticsPostingTimeRowSchema.parse({
          platform: "youtube",
          channel_name: "Sample Channel",
          publish_day_name: "Wednesday",
          publish_hour: 18,
          post_count: 3,
          average_views: 2200,
          median_views: 2000,
          average_calculated_interaction_rate: null,
        }),
      ],
      recommendations: [
        analyticsJointRecommendationRowSchema.parse({
          platform: "tiktok",
          recommendation_rank: 1,
          recommended_slot: "Monday · 2 PM–6 PM",
          post_count: 8,
          platform_post_count: 48,
          avg_views: 8400,
          median_views: 8100,
          recommendation_score: 0.88,
          confidence: "Medium",
          latest_metric_date: "2026-08-28",
          metrics_age_days: 1,
          metrics_status: "Fresh",
          recommendation_ready_for_approval_mode: true,
        }),
      ],
      fallbackSelections: [
        analyticsFallbackRowSchema.parse({
          platform: "tiktok",
          game: "Sample Game",
          content_type: "Highlight",
          vibe: "Chaotic",
          selected_model_level: "Game + Content Type",
          selected_model_priority: 3,
          group_sample_size: 14,
          minimum_sample_size: 12,
          recommended_slot: "Monday · 2 PM–6 PM",
          recommendation_score: 0.8,
          confidence: "High",
          metrics_status: "Fresh",
          recommendation_ready_for_preview: true,
          fallback_reason: "Database-selected fallback",
        }),
      ],
      cadenceSettings: [
        cadenceSettingRowSchema.parse({
          platform: "tiktok",
          content_format: "short_form",
          posts_per_week: 5,
          max_posts_per_day: 2,
          min_gap_hours: 4,
          protected_hours: 24,
          minimum_sample_size: 12,
          metrics_freshness_limit_days: 4,
          timezone_name: "America/Denver",
          is_active: true,
          updated_at: "2026-08-29T12:00:00Z",
        }),
      ],
      weeklySlots: [
        weeklySlotRowSchema.parse({
          platform: "tiktok",
          content_format: "short_form",
          slot_rank: 1,
          publish_day_name: "Monday",
          scheduled_hour_local: 14,
          scheduled_time_local: "14:00:00",
          recommended_window: "2 PM–6 PM",
          recommendation_score: 0.88,
          confidence: "Medium",
          supporting_sample_size: 8,
          metrics_status: "Fresh",
          timezone_name: "America/Denver",
        }),
      ],
      partialErrors: [],
    });

    expect(result.contentPerformance[0]).toMatchObject({
      postCount: 8,
      averageViews: 8400.5,
    });
    expect(result.recommendations[0]).toMatchObject({
      recommendedSlot: "Monday · 2 PM–6 PM",
      sampleSize: 8,
      score: 0.88,
    });
    expect(result.fallbackSelections[0].fallbackReason).toBe(
      "Database-selected fallback",
    );
    expect(result.weeklySlots[0].hour).toBe(14);
  });
});
