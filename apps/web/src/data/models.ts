export type PartialDataError = {
  section: string;
  message: string;
};

export type DashboardData = {
  summary: {
    postCount: number;
    totalViews: number;
    averageViews: number;
    averageInteractionRate: number | null;
  };
  recentPosts: {
    platform: string;
    channelName: string | null;
    caption: string;
    externalLink: string | null;
    publishedAt: string | null;
    labelStatus: string;
    clipGroup: string | null;
    views: number | null;
    interactions: number;
  }[];
  growth: {
    platform: string;
    capturedOn: string;
    viewsGained: number;
  }[];
  topTimes: {
    platform: string;
    day: string;
    hour: number;
    postCount: number;
    averageViews: number;
  }[];
  topContent: {
    platform: string;
    game: string | null;
    contentType: string | null;
    vibe: string | null;
    postCount: number;
    averageViews: number;
  }[];
  latestMetricDate: string | null;
  partialErrors: PartialDataError[];
};

export type UpcomingPost = {
  key: string;
  platform: string;
  channelName: string;
  caption: string;
  externalLink: string | null;
  dueAt: string;
  labelStatus: string;
  clipGroup: string | null;
  game: string | null;
  contentType: string | null;
  lastSyncedAt: string | null;
  proposal: {
    status: string;
    proposedDueAt: string;
    confidence: string | null;
    metricsStatus: string | null;
  } | null;
};

export type UpcomingPostsData = {
  posts: UpcomingPost[];
  partialErrors: PartialDataError[];
};

export type LabelQueueState =
  "pending_export" | "exported_unlinked" | "export_state_unavailable";

export type LabelQueueData = {
  summary: {
    unlinked: number;
    pendingExport: number | null;
    exportedStillUnlinked: number | null;
  };
  items: {
    platform: string;
    channelName: string;
    sourceStatus: string;
    caption: string;
    externalLink: string | null;
    publishedAtLocal: string | null;
    views: number | null;
    latestMetricDate: string | null;
    queueState: LabelQueueState;
  }[];
  clipGroups: {
    name: string;
    game: string | null;
    contentType: string | null;
    platforms: string[];
    postCount: number;
    recentPosts: {
      platform: string;
      caption: string;
      externalLink: string | null;
      publishedAt: string | null;
    }[];
  }[];
  partialErrors: PartialDataError[];
};

export type ProposalApplicationState =
  | "pending"
  | "approved_blocked"
  | "ready_for_make"
  | "applied_awaiting_sync"
  | "synchronized"
  | "error"
  | "rejected"
  | "readiness_unavailable";

export type ProposalExportState =
  "pending_export" | "exported" | "not_observable" | "unavailable";

export type ScheduleApprovalsData = {
  proposals: {
    platform: string;
    contentFormat: string;
    caption: string;
    externalLink: string | null;
    currentDueAt: string;
    proposedDueAt: string;
    approvalStatus: string;
    applicationState: ProposalApplicationState;
    confidence: string | null;
    metricsStatus: string | null;
    timezoneName: string;
    recommendationScore: number | null;
    recommendationRank: number | null;
    slotRank: number | null;
    supportingSampleSize: number | null;
    generatedAt: string;
    updatedAt: string;
    approvedAt: string | null;
    appliedAt: string | null;
    exportState: ProposalExportState;
    lastSyncedAt: string | null;
    blockingReasons: string[];
  }[];
  partialErrors: PartialDataError[];
};
