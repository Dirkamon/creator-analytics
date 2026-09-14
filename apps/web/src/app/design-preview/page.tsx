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
