export type PartialDataError = {
  section: string;
  message: string;
};

export type FreshnessState = "Fresh" | "Stale" | "Missing";

export type ReportingPost = {
  key: string;
  platform: string;
  channelName: string | null;
  caption: string;
  externalLink: string | null;
  publishedAt: string | null;
  publishDay: string | null;
  publishHour: number | null;
  labelStatus: string;
  clipGroup: string | null;
  game: string | null;
  contentType: string | null;
  vibe: string | null;
  views: number | null;
  reactions: number;
  comments: number;
  shares: number;
  saves: number;
  interactionRate: number | null;
};

export type DashboardData = {
  summary: {
    postCount: number;
    totalViews: number;
    totalReactions: number;
    totalComments: number;
    totalShares: number;
    averageViews: number;
    averageInteractionRate: number | null;
  };
  filterablePosts: ReportingPost[];
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

export type TopPostsData = {
  posts: ReportingPost[];
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
    bufferPostId: string;
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
    vibe: string | null;
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

export type AnalyticsData = {
  contentPerformance: {
    platform: string;
    game: string | null;
    contentType: string | null;
    vibe: string | null;
    hookType: string | null;
    postCount: number;
    averageViews: number;
    medianViews: number;
    averageInteractionRate: number | null;
  }[];
  postingWindows: {
    platform: string;
    channelName: string;
    day: string;
    hour: number;
    postCount: number;
    averageViews: number;
    medianViews: number;
    averageInteractionRate: number | null;
  }[];
  recommendations: {
    platform: string;
    rank: number;
    recommendedSlot: string;
    sampleSize: number;
    platformSampleSize: number;
    averageViews: number;
    medianViews: number;
    score: number;
    confidence: string;
    latestMetricDate: string | null;
    metricsAgeDays: number | null;
    metricsStatus: string;
    readyForApprovalMode: boolean;
  }[];
  fallbackSelections: {
    platform: string;
    game: string | null;
    contentType: string | null;
    vibe: string | null;
    selectedModelLevel: string;
    selectedModelPriority: number;
    groupSampleSize: number;
    minimumSampleSize: number;
    recommendedSlot: string;
    score: number;
    confidence: string;
    metricsStatus: string;
    readyForPreview: boolean;
    fallbackReason: string;
  }[];
  cadenceSettings: {
    platform: string;
    contentFormat: string;
    postsPerWeek: number;
    maxPostsPerDay: number;
    minGapHours: number;
    protectedHours: number;
    minimumSampleSize: number;
    metricsFreshnessLimitDays: number;
    timezoneName: string;
    isActive: boolean;
    updatedAt: string;
  }[];
  weeklySlots: {
    platform: string;
    contentFormat: string;
    slotRank: number;
    day: string;
    hour: number;
    localTime: string;
    recommendedWindow: string;
    score: number;
    confidence: string;
    sampleSize: number;
    metricsStatus: string;
    timezoneName: string;
  }[];
  partialErrors: PartialDataError[];
};

export type SystemStatusData = {
  thresholds: {
    postSyncStaleHours: number;
    metricsStaleHours: number;
  };
  summary: {
    observedPosts: number | null;
    postSyncPlatformsNeedingAttention: number | null;
    observedSentMetrics: number | null;
    metricsPlatformsNeedingAttention: number | null;
    proposalErrors: number | null;
    blockedApprovedProposals: number | null;
    unlinkedPosts: number | null;
    pendingLabelExports: number | null;
    exportedStillUnlinked: number | null;
  };
  postSyncFreshness: {
    platform: string;
    state: FreshnessState;
    observedPosts: number;
    recordsWithTimestamp: number;
    historicalRowsOutsideThreshold: number;
    missingTimestamps: number;
    latestSyncedAt: string | null;
  }[];
  metricsFreshness: {
    platform: string;
    state: FreshnessState;
    observedSentPosts: number;
    recordsWithTimestamp: number;
    historicalRowsOutsideThreshold: number;
    missingTimestamps: number;
    latestCapturedAt: string | null;
  }[];
  cadenceSettings: AnalyticsData["cadenceSettings"];
  previewReadiness: {
    platform: string;
    previewRows: number;
    readyRows: number;
    blockedRows: number;
    activeProposalBlocks: number;
    contentSpecificRows: number;
    platformFallbackRows: number;
    guardrailPassRows: number;
    firstProposedAtLocal: string | null;
    lastProposedAtLocal: string | null;
    sameChannelBlocks: number;
    channelIdentityBlocks: number;
    configurationBlocks: number;
    dailyCapacityBlocks: number;
    weeklyCapacityBlocks: number;
  }[];
  blockedReasons: {
    reason: string;
    count: number;
  }[];
  recentProposalErrors: {
    platform: string;
    updatedAt: string;
  }[];
  automationTelemetry: {
    available: false;
    explanation: string;
  };
  partialErrors: PartialDataError[];
};
