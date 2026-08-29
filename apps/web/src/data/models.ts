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
