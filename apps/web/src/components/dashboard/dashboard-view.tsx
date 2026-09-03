"use client";

import {
  ArrowUpRight,
  BarChart3,
  Eye,
  Film,
  Gauge,
  Heart,
  Layers3,
  MessageCircle,
  Share2,
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
    <div className="rounded-2xl border border-white/10 bg-slate-950/55 p-5 shadow-xl shadow-black/10">
      <div className="flex items-start justify-between gap-4">
        <p className="text-xs font-semibold tracking-[0.12em] text-slate-500 uppercase">
          {label}
        </p>
        <div className="rounded-lg border border-cyan-300/15 bg-cyan-300/[0.08] p-2 text-cyan-200">
          <Icon aria-hidden size={16} />
        </div>
      </div>
      <p className="mt-4 text-3xl font-semibold tracking-tight text-white">
        {value}
      </p>
      <p className="mt-1 text-xs text-slate-500">{detail}</p>
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
}: {
  data: DashboardData;
  now?: Date;
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

  return (
    <div className="space-y-7">
      <PageHeader
        aside={
          <div className="flex flex-wrap gap-2">
            <Badge tone="positive">Synchronized reporting</Badge>
            <Badge tone="info">{DEFAULT_DISPLAY_TIMEZONE}</Badge>
          </div>
        }
        description="A private read-only view of performance already modeled in Supabase. No scheduling, labeling, or ingestion actions are available here."
        eyebrow="Performance overview"
        title="Dashboard"
      />

      <PartialErrorState errors={data.partialErrors} />

      {metricsStale && (
        <StaleNotice title="Metrics are outside the expected freshness window">
          The latest metric date is {data.latestMetricDate}. This page does not
          trigger ingestion; verify the existing metrics workflow before drawing
          conclusions from the totals.
        </StaleNotice>
      )}

      {!hasSourceData ? (
        <EmptyState title="No dashboard data is available">
          The reporting views returned no rows. This interface will not start an
          ingestion or refresh workflow.
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
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 2xl:grid-cols-7">
                <MetricCard
                  detail="Sent posts in the current view"
                  icon={Film}
                  label="Tracked posts"
                  value={formatCompactNumber(summary.postCount)}
                />
                <MetricCard
                  detail="Cumulative views in the current view"
                  icon={Eye}
                  label="Tracked views"
                  value={formatCompactNumber(summary.totalViews)}
                />
                <MetricCard
                  detail="Average across the current view"
                  icon={BarChart3}
                  label="Average views"
                  value={formatCompactNumber(summary.averageViews)}
                />
                <MetricCard
                  detail="Repository-defined average"
                  icon={Gauge}
                  label="Interaction rate"
                  value={formatPercentage(summary.averageInteractionRate)}
                />
                <MetricCard
                  detail="Total reactions in the current view"
                  icon={Heart}
                  label="Reactions"
                  value={formatCompactNumber(summary.totalReactions)}
                />
                <MetricCard
                  detail="Total comments in the current view"
                  icon={MessageCircle}
                  label="Comments"
                  value={formatCompactNumber(summary.totalComments)}
                />
                <MetricCard
                  detail="Total shares in the current view"
                  icon={Share2}
                  label="Shares"
                  value={formatCompactNumber(summary.totalShares)}
                />
              </div>

              <div className="grid gap-6 2xl:grid-cols-[1.35fr_0.65fr]">
                <SectionCard
                  description="Daily gains from the existing Looker reporting view; newest dates first."
                  title="Recent view growth"
                >
                  {filters.game ? (
                    <p className="text-sm leading-6 text-slate-500">
                      Growth history is platform-level and cannot be safely
                      segmented by game. Clear the Game filter to display it.
                    </p>
                  ) : growth.length === 0 ? (
                    <p className="text-sm text-slate-500">
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
                            <p className="text-xs font-medium text-slate-300">
                              {formatShortDate(`${item.capturedOn}T12:00:00Z`)}
                            </p>
                            <p className="text-[0.65rem] tracking-wide text-slate-600 uppercase">
                              {item.platform}
                            </p>
                          </div>
                          <div className="h-2 overflow-hidden rounded-full bg-white/5">
                            <div
                              aria-label={`${formatCompactNumber(item.viewsGained)} views gained`}
                              className="h-full min-w-1 rounded-full bg-gradient-to-r from-teal-400 to-cyan-300"
                              style={{
                                width: `${Math.max(2, (item.viewsGained / growthMax) * 100)}%`,
                              }}
                            />
                          </div>
                          <p className="text-sm font-semibold text-white">
                            +{formatCompactNumber(item.viewsGained)}
                          </p>
                        </div>
                      ))}
                    </div>
                  )}
                </SectionCard>

                <SectionCard
                  description="Highest average-view day and hour combinations in the current view."
                  title="Strong posting windows"
                >
                  {topTimes.length === 0 ? (
                    <p className="text-sm text-slate-500">
                      No posting windows match the current filters.
                    </p>
                  ) : (
                    <div className="space-y-3">
                      {topTimes.slice(0, 6).map((time, index) => (
                        <div
                          className="flex items-center justify-between gap-4 rounded-xl border border-white/5 bg-white/[0.025] px-4 py-3"
                          key={`${time.platform}-${time.day}-${time.hour}-${index}`}
                        >
                          <div>
                            <p className="text-sm font-medium text-white">
                              {time.day} · {formatHour(time.hour)}
                            </p>
                            <p className="mt-1 text-xs text-slate-500">
                              {time.platform} · {time.postCount} posts
                            </p>
                          </div>
                          <p className="text-sm font-semibold text-cyan-200">
                            {formatCompactNumber(time.averageViews)} avg
                          </p>
                        </div>
                      ))}
                    </div>
                  )}
                </SectionCard>
              </div>

              <div className="grid gap-6 2xl:grid-cols-[0.8fr_1.2fr]">
                <SectionCard
                  description="Existing content labels grouped within the current view."
                  title="Content signals"
                >
                  {topContent.length === 0 ? (
                    <p className="text-sm text-slate-500">
                      No labeled content groups match the current filters.
                    </p>
                  ) : (
                    <div className="space-y-3">
                      {topContent.slice(0, 6).map((content, index) => (
                        <div
                          className="flex items-center gap-3 rounded-xl border border-white/5 bg-white/[0.025] p-3"
                          key={`${content.platform}-${content.game}-${content.contentType}-${index}`}
                        >
                          <div className="rounded-lg border border-white/10 bg-white/5 p-2 text-slate-300">
                            <Layers3 aria-hidden size={16} />
                          </div>
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-sm font-medium text-white">
                              {content.game ?? "Unspecified game"} ·{" "}
                              {content.contentType ?? "Unspecified type"}
                            </p>
                            <p className="mt-1 text-xs text-slate-500">
                              {content.platform} · {content.vibe ?? "No vibe"} ·{" "}
                              {content.postCount} posts
                            </p>
                          </div>
                          <p className="text-sm font-semibold text-cyan-200">
                            {formatCompactNumber(content.averageViews)}
                          </p>
                        </div>
                      ))}
                    </div>
                  )}
                </SectionCard>

                <SectionCard
                  description="Latest sent posts in the current view, with safe display fields only."
                  title="Recent performance"
                >
                  <div className="divide-y divide-white/5">
                    {recentPosts.map((post, index) => (
                      <article
                        className="grid gap-3 py-4 first:pt-0 last:pb-0 sm:grid-cols-[1fr_auto] sm:items-center"
                        key={`${post.platform}-${post.publishedAt}-${index}`}
                      >
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            <Badge>{post.platform}</Badge>
                            <span className="text-xs text-slate-600">
                              {post.publishedAt
                                ? formatDateTime(post.publishedAt)
                                : "Publication time unavailable"}
                            </span>
                          </div>
                          <p className="mt-2 line-clamp-2 text-sm leading-6 text-slate-200">
                            {post.caption}
                          </p>
                          <p className="mt-1 text-xs text-slate-500">
                            {post.clipGroup ?? "Unlabeled clip"} ·{" "}
                            {post.labelStatus}
                          </p>
                        </div>
                        <div className="flex items-center gap-4 sm:justify-end">
                          <div className="text-right">
                            <p className="font-semibold text-white">
                              {post.views === null
                                ? "—"
                                : formatCompactNumber(post.views)}
                            </p>
                            <p className="text-[0.68rem] text-slate-600">
                              views
                            </p>
                          </div>
                          <div className="text-right">
                            <p className="font-semibold text-white">
                              {formatCompactNumber(post.interactions)}
                            </p>
                            <p className="text-[0.68rem] text-slate-600">
                              interactions
                            </p>
                          </div>
                          {post.externalLink && (
                            <a
                              aria-label={`Open ${post.platform} post`}
                              className="rounded-lg border border-white/10 p-2 text-slate-400 transition hover:border-cyan-300/30 hover:text-cyan-200"
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
                    className="mt-5 inline-flex items-center gap-2 rounded-xl border border-cyan-300/20 px-4 py-2 text-sm font-semibold text-cyan-200 transition hover:border-cyan-300/50 hover:bg-cyan-300/[0.06]"
                    href="/top-posts"
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
