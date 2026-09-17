import { notFound } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function DesignPreview({
  searchParams,
}: {
  searchParams: Promise<{ view?: string; month?: string }>;
}) {
  // Sample UI only. Production requests must never enter this route.
  if (process.env.NODE_ENV !== "development") notFound();

  const { view = "dashboard", month } = await searchParams;
  const { AppShell } = await import("@/components/shell/app-shell");
  const fixtures = await import("@/test/fixtures");
  const { previewDashboard } = await import("@/test/design-preview");
  let content;
  switch (view) {
    case "recent-performance": {
      const { RecentPerformanceView } =
        await import("@/components/recent-performance/recent-performance-view");
      const { sanitizeThumbnailUrl } = await import("@/lib/thumbnail-url");
      // A development-only trial supplied at launch, never committed media URLs.
      const trialThumbnail = sanitizeThumbnailUrl(
        process.env.CREATOR_ANALYTICS_PREVIEW_THUMBNAIL_URL,
      );
      content = (
        <>
          {trialThumbnail && (
            <p className="text-secondary mb-5 text-sm">
              Thumbnail trial · The first two cards use your actual Buffer clip
              image. Post details and metrics are sample data; the live site is
              unchanged.
            </p>
          )}
          <RecentPerformanceView
            data={{
              posts: previewDashboard.filterablePosts.map((post, index) => ({
                ...post,
                thumbnailUrl: index < 2 ? trialThumbnail : null,
                ...(trialThumbnail && index < 2
                  ? { clipGroup: "Halo clip · Thumbnail trial", game: "Halo" }
                  : {}),
                latestMetricDate:
                  index === 4
                    ? null
                    : index === 3
                      ? "2026-09-01"
                      : "2026-09-06",
                views: index === 4 ? null : post.views,
                reactions: index === 4 ? null : post.reactions,
                comments: index === 4 ? null : post.comments,
                shares: index === 4 ? null : post.shares,
                saves: index === 4 ? null : post.saves,
                interactionRate: index === 4 ? null : post.interactionRate,
              })),
              partialErrors: [],
            }}
            now={new Date("2026-09-07T12:00:00Z")}
          />
        </>
      );
      break;
    }
    case "scheduling-preferences": {
      const { PostingPreferencesPreview } =
        await import("@/components/preferences/posting-preferences-preview");
      content = <PostingPreferencesPreview />;
      break;
    }
    case "calendar": {
      const { CalendarView } =
        await import("@/components/calendar/calendar-view");
      const { calendarPreview } = await import("@/test/calendar-preview");
      const data = calendarPreview(month);
      content = <CalendarView key={data.month} data={data} preview />;
      break;
    }
    case "top-posts": {
      const { TopPostsView } =
        await import("@/components/top-posts/top-posts-view");
      content = (
        <TopPostsView
          data={{ posts: previewDashboard.filterablePosts, partialErrors: [] }}
        />
      );
      break;
    }
    case "upcoming-posts": {
      const { UpcomingPostsView } =
        await import("@/components/upcoming/upcoming-posts-view");
      content = <UpcomingPostsView data={fixtures.upcomingPostsFixture} />;
      break;
    }
    case "label-queue": {
      const { LabelQueueView } =
        await import("@/components/label-queue/label-queue-view");
      content = <LabelQueueView data={fixtures.labelQueueFixture} />;
      break;
    }
    case "schedule-approvals": {
      const { ScheduleApprovalsView } =
        await import("@/components/schedule-approvals/schedule-approvals-view");
      content = (
        <ScheduleApprovalsView data={fixtures.scheduleApprovalsFixture} />
      );
      break;
    }
    case "analytics": {
      const { AnalyticsView } =
        await import("@/components/analytics/analytics-view");
      content = <AnalyticsView data={fixtures.analyticsFixture} />;
      break;
    }
    case "system-status": {
      const { SystemStatusView } =
        await import("@/components/system-status/system-status-view");
      content = <SystemStatusView data={fixtures.systemStatusFixture} />;
      break;
    }
    case "dashboard": {
      const { DashboardView } =
        await import("@/components/dashboard/dashboard-view");
      content = (
        <DashboardView
          data={previewDashboard}
          now={new Date("2026-09-07T12:00:00Z")}
          preview
        />
      );
      break;
    }
    default:
      notFound();
  }
  return (
    <AppShell userEmail="creator@example.invalid" previewPath={`/${view}`}>
      {content}
    </AppShell>
  );
}
