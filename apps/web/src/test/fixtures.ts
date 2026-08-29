import type { DashboardData, UpcomingPostsData } from "@/data/models";

export const dashboardFixture: DashboardData = {
  summary: {
    postCount: 2,
    totalViews: 15_400,
    averageViews: 7_700,
    averageInteractionRate: 6.25,
  },
  recentPosts: [
    {
      platform: "tiktok",
      channelName: "sample-channel",
      caption: "A sanitized gameplay moment with a surprising ending",
      externalLink: "https://example.invalid/posts/sample-one",
      publishedAt: "2026-08-27T20:00:00.000Z",
      labelStatus: "labeled",
      clipGroup: "Sample Clip Alpha",
      views: 9_200,
      interactions: 735,
    },
    {
      platform: "youtube",
      channelName: "sample-channel",
      caption: "A second sanitized highlight for test coverage",
      externalLink: null,
      publishedAt: "2026-08-26T19:00:00.000Z",
      labelStatus: "unlabeled",
      clipGroup: null,
      views: 6_200,
      interactions: 320,
    },
  ],
  growth: [
    { platform: "tiktok", capturedOn: "2026-08-28", viewsGained: 2_400 },
    { platform: "youtube", capturedOn: "2026-08-28", viewsGained: 1_100 },
  ],
  topTimes: [
    {
      platform: "tiktok",
      day: "Monday",
      hour: 14,
      postCount: 8,
      averageViews: 8_400,
    },
  ],
  topContent: [
    {
      platform: "tiktok",
      game: "Sample Game",
      contentType: "Highlight",
      vibe: "Chaotic",
      postCount: 5,
      averageViews: 8_900,
    },
  ],
  latestMetricDate: "2026-08-28",
  partialErrors: [],
};

export const upcomingPostsFixture: UpcomingPostsData = {
  posts: [
    {
      key: "SANITIZED_POST_A",
      platform: "tiktok",
      channelName: "Sample TikTok Channel",
      caption: "A sanitized scheduled caption for a gameplay clip",
      externalLink: "https://example.invalid/posts/scheduled-one",
      dueAt: "2026-08-31T20:00:00.000Z",
      labelStatus: "labeled",
      clipGroup: "Sample Clip Beta",
      game: "Sample Game",
      contentType: "Highlight",
      lastSyncedAt: "2026-08-29T15:00:00.000Z",
      proposal: {
        status: "Pending",
        proposedDueAt: "2026-09-01T01:30:00.000Z",
        confidence: "Moderate",
        metricsStatus: "Fresh",
      },
    },
    {
      key: "SANITIZED_POST_B",
      platform: "youtube",
      channelName: "Sample YouTube Channel",
      caption: "Another sanitized scheduled caption",
      externalLink: null,
      dueAt: "2026-09-01T18:00:00.000Z",
      labelStatus: "unlabeled",
      clipGroup: null,
      game: null,
      contentType: null,
      lastSyncedAt: null,
      proposal: null,
    },
  ],
  partialErrors: [],
};
