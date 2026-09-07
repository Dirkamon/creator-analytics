"use client";

import {
  ArrowUpRight,
  BarChart3,
  CalendarDays,
  CalendarCheck2,
  Eye,
  Film,
  Gauge,
  Heart,
  Layers3,
  MessageCircle,
  Share2,
  Tags,
} from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";

import { ReportFilters } from "@/components/reporting/report-filters";
import {
  EmptyState,
  PartialErrorState,
  StaleNotice,
} from "@/components/states/feedback-states";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/page-header";
import { SectionCard } from "@/components/ui/section-card";
import type { DashboardData, ReportingPost } from "@/data/models";
import {
  EMPTY_REPORT_FILTERS,
  filterReportingPosts,
  hasActiveReportFilters,
  reportFilterOptions,
} from "@/data/report-filters";
import {
  DEFAULT_DISPLAY_TIMEZONE,
  formatCompactNumber,
  formatDateTime,
  formatHour,
  formatPercentage,
  formatShortDate,
  isCalendarDateStale,
} from "@/lib/format";

function MetricCard({
  label,
  value,
  detail,
  icon: Icon,
}: {
  label: string;
  value: string;
  detail: string;
  icon: typeof Eye;
}) {
  return (
    <div className="metric-card">
      <div className="flex items-start justify-between gap-4">
        <p className="text-secondary text-sm font-medium">{label}</p>
        <div className="border-accent/15 bg-accent/[0.08] text-accent rounded-lg border p-2">
          <Icon aria-hidden size={16} />
        </div>
      </div>
      <p className="text-foreground mt-5 text-3xl font-semibold tracking-tight tabular-nums sm:text-4xl">
        {value}
      </p>
      <p className="text-muted mt-1 text-xs">{detail}</p>
    </div>
  );
}

function summarizePosts(posts: readonly ReportingPost[]) {
  const totalViews = posts.reduce((sum, post) => sum + (post.views ?? 0), 0);
  const interactionRates = posts
    .map((post) => post.interactionRate)
    .filter((value): value is number => value !== null);

  return {
    postCount: posts.length,
    totalViews,
    totalReactions: posts.reduce((sum, post) => sum + post.reactions, 0),
    totalComments: posts.reduce((sum, post) => sum + post.comments, 0),
    totalShares: posts.reduce((sum, post) => sum + post.shares, 0),
    averageViews: posts.length === 0 ? 0 : totalViews / posts.length,
    averageInteractionRate:
      interactionRates.length === 0
        ? null
        : interactionRates.reduce((sum, value) => sum + value, 0) /
          interactionRates.length,
  };
}

function strongestTimes(posts: readonly ReportingPost[]) {
  const groups = new Map<
    string,
    {
      platform: string;
      day: string;
      hour: number;
      views: number;
      count: number;
    }
  >();

  for (const post of posts) {
    if (
      post.publishDay === null ||
      post.publishHour === null ||
      post.views === null
    )
      continue;
    const key = `${post.platform}\u0000${post.publishDay}\u0000${post.publishHour}`;
    const current = groups.get(key) ?? {
      platform: post.platform,
      day: post.publishDay,
      hour: post.publishHour,
      views: 0,
      count: 0,
    };
    current.views += post.views;
    current.count += 1;
    groups.set(key, current);
  }

  return Array.from(groups.values())
    .map((group) => ({
      platform: group.platform,
      day: group.day,
      hour: group.hour,
      postCount: group.count,
      averageViews: group.views / group.count,
    }))
    .sort((left, right) => right.averageViews - left.averageViews);
}

function strongestContent(posts: readonly ReportingPost[]) {
  const groups = new Map<
    string,
    {
      platform: string;
      game: string | null;
      contentType: string | null;
      vibe: string | null;
      views: number;
      count: number;
    }
  >();

  for (const post of posts) {
    if (post.clipGroup === null || post.views === null) continue;
    const key = JSON.stringify([
      post.platform,
      post.game,
      post.contentType,
      post.vibe,
    ]);
    const current = groups.get(key) ?? {
      platform: post.platform,
      game: post.game,
      contentType: post.contentType,
      vibe: post.vibe,
      views: 0,
      count: 0,
    };
    current.views += post.views;
    current.count += 1;
    groups.set(key, current);
  }

  return Array.from(groups.values())
    .map((group) => ({
      platform: group.platform,
      game: group.game,
      contentType: group.contentType,
      vibe: group.vibe,
      postCount: group.count,
      averageViews: group.views / group.count,
    }))
    .sort((left, right) => right.averageViews - left.averageViews);
}

export function DashboardView({
  data,
  now = new Date(),
  preview = false,
}: {
  data: DashboardData;
  now?: Date;
  preview?: boolean;
}) {
  const [filters, setFilters] = useState(EMPTY_REPORT_FILTERS);
  const options = useMemo(
    () => reportFilterOptions(data.filterablePosts),
    [data.filterablePosts],
  );
  const filteredPosts = useMemo(
    () => filterReportingPosts(data.filterablePosts, filters),
    [data.filterablePosts, filters],
  );
  const hasDetailedRows = data.filterablePosts.length > 0;
  const summary = hasDetailedRows
    ? summarizePosts(filteredPosts)
    : data.summary;
  const recentPosts = hasDetailedRows
    ? filteredPosts.slice(0, 6).map((post) => ({
        platform: post.platform,
        channelName: post.channelName,
        caption: post.caption,
        externalLink: post.externalLink,
        publishedAt: post.publishedAt,
        labelStatus: post.labelStatus,
        clipGroup: post.clipGroup,
        views: post.views,
        interactions: post.reactions + post.comments + post.shares + post.saves,
      }))
    : data.recentPosts;
  const topTimes = hasDetailedRows
    ? strongestTimes(filteredPosts)
    : data.topTimes;
  const topContent = hasDetailedRows
    ? strongestContent(filteredPosts)
    : data.topContent;
  const growth = data.growth.filter((item) => {
    if (filters.game) return false;
    if (filters.platform && item.platform !== filters.platform) return false;
    if (filters.dateFrom && item.capturedOn < filters.dateFrom) return false;
    if (filters.dateTo && item.capturedOn > filters.dateTo) return false;
    return true;
  });
  const hasSourceData =
    data.summary.postCount > 0 ||
    data.growth.length > 0 ||
    data.topTimes.length > 0 ||
    data.topContent.length > 0;
  const filtersActive = hasActiveReportFilters(filters);
  const hasMatches = summary.postCount > 0;
  const growthMax = Math.max(1, ...growth.map((item) => item.viewsGained));
  const metricsStale =
    data.latestMetricDate !== null &&
    isCalendarDateStale({
      value: data.latestMetricDate,
      now,
      maxAgeDays: 2,
    });
  const reportHref = (path: string) =>
    preview ? `/design-preview?view=${path.slice(1)}` : path;
  const performanceUnavailable = data.partialErrors.some(
    (error) => error.section === "Post performance",
  );
  const metricValue = (value: number) =>
    performanceUnavailable ? "—" : formatCompactNumber(value);

  return (
    <div className="space-y-7">
      <PageHeader
        aside={
          <div className="flex flex-wrap gap-2">
            <Badge tone={metricsStale ? "warning" : "neutral"}>
              {data.latestMetricDate
                ? `Metrics through ${formatShortDate(`${data.latestMetricDate}T12:00:00Z`)}`
                : "Waiting for metrics"}
            </Badge>
          </div>
        }
        description="See how your content is doing, and plan what comes next."
        eyebrow="Your content at a glance"
        title="Dashboard"
      />

      <nav aria-label="Content workflow" className="grid gap-3 sm:grid-cols-3">
        {[
          {
            href: "/label-queue",
            title: "Label your clips",
            detail: "Organize new content",
            icon: Tags,
          },
          {
            href: "/schedule-approvals",
            title: "Review proposals",
            detail: "Choose your posting times",
            icon: CalendarCheck2,
          },
          {
            href: "/upcoming-posts",
            title: "See your schedule",
            detail: "Check what's coming up",
            icon: CalendarDays,
          },
        ].map(({ href, title, detail, icon: Icon }) => (
          <Link
            key={href}
            href={reportHref(href)}
            className="group border-line bg-surface hover:border-accent/50 hover:bg-accent/5 flex min-w-0 items-center gap-3 rounded-xl border px-4 py-3.5 transition"
          >
            <Icon aria-hidden size={19} className="text-accent shrink-0" />
            <div className="min-w-0 flex-1">
              <p className="text-foreground text-sm font-medium">{title}</p>
              <p className="text-muted mt-0.5 text-xs">{detail}</p>
            </div>
            <ArrowUpRight
              aria-hidden
              size={15}
              className="text-muted group-hover:text-accent shrink-0"
            />
          </Link>
        ))}
      </nav>

      <PartialErrorState errors={data.partialErrors} />

      {metricsStale && (
        <StaleNotice title="Metrics may need an update">
          The latest metrics are from {data.latestMetricDate}. Check System
          Status if newer results are missing.
        </StaleNotice>
      )}

      {!hasSourceData ? (
        <EmptyState title="No dashboard data is available">
          Your performance will appear here after your posts publish and their
          metrics sync. You can still label clips and review your upcoming
          schedule.
        </EmptyState>
      ) : (
        <>
          {hasDetailedRows && (
            <ReportFilters
              games={options.games}
              onChange={setFilters}
              platforms={options.platforms}
              value={filters}
            />
          )}

          {filtersActive && !hasMatches ? (
            <EmptyState title="No posts match these filters">
              Clear or broaden the filters to see reporting results.
            </EmptyState>
          ) : (
            <>
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <MetricCard
                  detail="Published posts in this view"
                  icon={Film}
                  label="Published posts"
                  value={metricValue(summary.postCount)}
                />
                <MetricCard
                  detail="Across these published posts"
                  icon={Eye}
                  label="Total views"
                  value={metricValue(summary.totalViews)}
                />
                <MetricCard
                  detail="Views per published post"
                  icon={BarChart3}
                  label="Average views"
                  value={metricValue(summary.averageViews)}
                />
                <MetricCard
                  detail="Average of reported post rates"
                  icon={Gauge}
                  label="Interaction rate"
                  value={
                    performanceUnavailable
                      ? "—"
                      : formatPercentage(summary.averageInteractionRate)
                  }
                />
              </div>

              <div
                aria-label="Engagement totals"
                className="border-line flex flex-wrap items-center gap-x-8 gap-y-3 rounded-xl border px-5 py-4 text-sm"
              >
                <span className="text-muted w-full text-xs font-medium sm:w-auto">
                  Engagement
                </span>
                {[
                  {
                    label: "Reactions",
                    value: summary.totalReactions,
                    icon: Heart,
                  },
                  {
                    label: "Comments",
                    value: summary.totalComments,
                    icon: MessageCircle,
                  },
                  { label: "Shares", value: summary.totalShares, icon: Share2 },
                ].map(({ label, value, icon: Icon }) => (
                  <div key={label} className="flex items-center gap-2">
                    <Icon aria-hidden size={16} className="text-muted" />
                    <span className="text-foreground font-semibold tabular-nums">
                      {metricValue(value)}
                    </span>
                    <span className="text-muted">{label}</span>
                  </div>
                ))}
              </div>

              <div className="grid items-start gap-6 xl:grid-cols-[1.2fr_0.8fr]">
                <SectionCard
                  description="New views by platform, with the latest dates first."
                  title="Recent view growth"
                >
                  {filters.game ? (
                    <p className="text-muted text-sm leading-6">
                      Growth history is available by platform, not by game.
                      Clear the Game filter to see it.
                    </p>
                  ) : growth.length === 0 ? (
                    <p className="text-muted text-sm">
                      No growth rows match the current filters.
                    </p>
                  ) : (
                    <div className="space-y-3">
                      {growth.slice(0, 12).map((item, index) => (
                        <div
                          className="grid grid-cols-[4.8rem_1fr_auto] items-center gap-3"
                          key={`${item.platform}-${item.capturedOn}-${index}`}
                        >
                          <div>
                            <p className="text-secondary text-xs font-medium">
                              {formatShortDate(`${item.capturedOn}T12:00:00Z`)}
                            </p>
                            <p className="text-muted text-[0.65rem] tracking-wide uppercase">
                              {item.platform}
                            </p>
                          </div>
                          <div className="bg-foreground/5 h-2 overflow-hidden rounded-full">
                            <div
                              aria-label={`${formatCompactNumber(item.viewsGained)} views gained`}
                              className="from-accent/65 to-accent h-full min-w-1 rounded-full bg-gradient-to-r"
                              style={{
                                width: `${Math.max(2, (item.viewsGained / growthMax) * 100)}%`,
                              }}
                            />
                          </div>
                          <p className="text-foreground text-sm font-semibold">
                            +{formatCompactNumber(item.viewsGained)}
                          </p>
                        </div>
                      ))}
                    </div>
                  )}
                </SectionCard>

                <SectionCard
                  description={`Times with the highest average views. ${DEFAULT_DISPLAY_TIMEZONE}. Small samples are directional.`}
                  title="Strong posting windows"
                >
                  {topTimes.length === 0 ? (
                    <p className="text-muted text-sm">
                      No posting windows match the current filters.
                    </p>
                  ) : (
                    <div className="space-y-3">
                      {topTimes.slice(0, 6).map((time, index) => (
                        <div
                          className="border-line bg-foreground/[0.025] flex items-center justify-between gap-4 rounded-xl border px-4 py-3"
                          key={`${time.platform}-${time.day}-${time.hour}-${index}`}
                        >
                          <div>
                            <p className="text-foreground text-sm font-medium">
                              {time.day} · {formatHour(time.hour)}
                            </p>
                            <p className="text-muted mt-1 text-xs">
                              {time.platform} · {time.postCount}{" "}
                              {time.postCount === 1 ? "post" : "posts"}
                            </p>
                          </div>
                          <p className="text-accent text-sm font-semibold">
                            {formatCompactNumber(time.averageViews)} avg
                          </p>
                        </div>
                      ))}
                    </div>
                  )}
                </SectionCard>
              </div>

              <div className="grid items-start gap-6 xl:grid-cols-[0.8fr_1.2fr]">
                <SectionCard
                  description="See which games and clip styles get the most views."
                  title="What’s working"
                >
                  {topContent.length === 0 ? (
                    <p className="text-muted text-sm">
                      No labeled content groups match the current filters.
                    </p>
                  ) : (
                    <div className="space-y-3">
                      {topContent.slice(0, 6).map((content, index) => (
                        <div
                          className="border-line bg-foreground/[0.025] flex items-center gap-3 rounded-xl border p-3"
                          key={`${content.platform}-${content.game}-${content.contentType}-${index}`}
                        >
                          <div className="border-line bg-foreground/5 text-secondary rounded-lg border p-2">
                            <Layers3 aria-hidden size={16} />
                          </div>
                          <div className="min-w-0 flex-1">
                            <p className="text-foreground truncate text-sm font-medium">
                              {content.game ?? "Unspecified game"} ·{" "}
                              {content.contentType ?? "Unspecified type"}
                            </p>
                            <p className="text-muted mt-1 text-xs">
                              {content.platform} · {content.vibe ?? "No vibe"} ·{" "}
                              {content.postCount} posts
                            </p>
                          </div>
                          <p className="text-accent text-sm font-semibold">
                            {formatCompactNumber(content.averageViews)}
                          </p>
                        </div>
                      ))}
                    </div>
                  )}
                </SectionCard>

                <SectionCard
                  description="Your most recently published posts."
                  title="Recent performance"
                >
                  <div className="divide-line divide-y">
                    {recentPosts.map((post, index) => (
                      <article
                        className="grid gap-3 py-4 first:pt-0 last:pb-0 sm:grid-cols-[1fr_auto] sm:items-center"
                        key={`${post.platform}-${post.publishedAt}-${index}`}
                      >
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            <Badge>{post.platform}</Badge>
                            <span className="text-muted text-xs">
                              {post.publishedAt
                                ? formatDateTime(post.publishedAt)
                                : "Publication time unavailable"}
                            </span>
                          </div>
                          <p className="text-secondary mt-2 line-clamp-2 text-sm leading-6">
                            {post.caption}
                          </p>
                          <p className="text-muted mt-1 text-xs">
                            {post.clipGroup ?? "Unlabeled clip"} ·{" "}
                            {post.labelStatus}
                          </p>
                        </div>
                        <div className="flex items-center gap-4 sm:justify-end">
                          <div className="text-right">
                            <p className="text-foreground font-semibold">
                              {post.views === null
                                ? "—"
                                : formatCompactNumber(post.views)}
                            </p>
                            <p className="text-muted text-[0.68rem]">views</p>
                          </div>
                          <div className="text-right">
                            <p className="text-foreground font-semibold">
                              {formatCompactNumber(post.interactions)}
                            </p>
                            <p className="text-muted text-[0.68rem]">
                              interactions
                            </p>
                          </div>
                          {post.externalLink && (
                            <a
                              aria-label={`Open ${post.platform} post`}
                              className="border-line text-muted hover:border-accent/30 hover:text-accent rounded-lg border p-2 transition"
                              href={post.externalLink}
                              rel="noreferrer"
                              target="_blank"
                            >
                              <ArrowUpRight aria-hidden size={16} />
                            </a>
                          )}
                        </div>
                      </article>
                    ))}
                  </div>
                  <Link
                    className="border-accent/20 text-accent hover:border-accent/50 hover:bg-accent/[0.06] mt-5 inline-flex items-center gap-2 rounded-xl border px-4 py-2 text-sm font-semibold transition"
                    href={reportHref("/top-posts")}
                  >
                    View all top posts <ArrowUpRight aria-hidden size={15} />
                  </Link>
                </SectionCard>
              </div>
            </>
          )}
        </>
      )}
    </div>
  );
}
