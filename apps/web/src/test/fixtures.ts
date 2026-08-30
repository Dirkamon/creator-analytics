import type {
  DashboardData,
  LabelQueueData,
  ScheduleApprovalsData,
  UpcomingPostsData,
} from "@/data/models";

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

export const labelQueueFixture: LabelQueueData = {
  summary: {
    unlinked: 2,
    pendingExport: 1,
    exportedStillUnlinked: 1,
  },
  items: [
    {
      platform: "tiktok",
      channelName: "Sample TikTok Channel",
      sourceStatus: "sent",
      caption: "A sanitized unlabeled clip awaiting export",
      externalLink: "https://example.invalid/posts/queue-one",
      publishedAtLocal: "2026-08-28T14:00:00",
      views: 4_200,
      latestMetricDate: "2026-08-29",
      queueState: "pending_export",
    },
    {
      platform: "youtube",
      channelName: "Sample YouTube Channel",
      sourceStatus: "sent",
      caption: "A sanitized exported clip that remains unlinked",
      externalLink: null,
      publishedAtLocal: "2026-08-27T13:30:00",
      views: 1_800,
      latestMetricDate: "2026-08-29",
      queueState: "exported_unlinked",
    },
  ],
  clipGroups: [
    {
      name: "Sample Shared Clip",
      game: "Sample Game",
      contentType: "Highlight",
      platforms: ["tiktok", "youtube"],
      postCount: 2,
      recentPosts: [
        {
          platform: "tiktok",
          caption: "A sanitized linked TikTok post",
          externalLink: null,
          publishedAt: "2026-08-26T20:00:00.000Z",
        },
      ],
    },
  ],
  partialErrors: [],
};

const baseProposal: ScheduleApprovalsData["proposals"][number] = {
  platform: "tiktok",
  contentFormat: "short_form",
  caption: "A sanitized schedule proposal",
  externalLink: "https://example.invalid/posts/proposal-one",
  currentDueAt: "2026-09-01T01:30:00.000Z",
  proposedDueAt: "2026-09-01T20:00:00.000Z",
  approvalStatus: "Pending",
  applicationState: "pending",
  confidence: "Moderate",
  metricsStatus: "Fresh",
  timezoneName: "America/Denver",
  recommendationScore: 0.82,
  recommendationRank: 1,
  slotRank: 2,
  supportingSampleSize: 18,
  generatedAt: "2026-08-29T09:10:00.000Z",
  updatedAt: "2026-08-29T09:10:00.000Z",
  approvedAt: null,
  appliedAt: null,
  exportState: "pending_export",
  lastSyncedAt: "2026-08-29T09:00:00.000Z",
  blockingReasons: [],
};

export const scheduleApprovalsFixture: ScheduleApprovalsData = {
  proposals: [
    baseProposal,
    {
      ...baseProposal,
      caption: "A sanitized approved proposal ready for Make",
      approvalStatus: "Approved",
      applicationState: "ready_for_make",
      approvedAt: "2026-08-29T10:00:00.000Z",
      exportState: "not_observable",
    },
    {
      ...baseProposal,
      caption: "A sanitized approved proposal blocked at preflight",
      approvalStatus: "Approved",
      applicationState: "approved_blocked",
      approvedAt: "2026-08-29T10:05:00.000Z",
      blockingReasons: [
        "Blocked: current schedule changed after proposal generation",
      ],
    },
    {
      ...baseProposal,
      caption: "A sanitized applied proposal awaiting synchronization",
      approvalStatus: "Applied",
      applicationState: "applied_awaiting_sync",
      appliedAt: "2026-08-29T10:10:00.000Z",
    },
    {
      ...baseProposal,
      caption: "A sanitized applied and synchronized proposal",
      approvalStatus: "Applied",
      applicationState: "synchronized",
      appliedAt: "2026-08-29T10:15:00.000Z",
      lastSyncedAt: "2026-08-29T10:30:00.000Z",
    },
    {
      ...baseProposal,
      caption: "A sanitized proposal with an application error",
      approvalStatus: "Error",
      applicationState: "error",
    },
  ],
  partialErrors: [],
};
