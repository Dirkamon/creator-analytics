import {
  ArrowUpRight,
  BarChart3,
  Eye,
  Film,
  Gauge,
  Layers3,
} from "lucide-react";

import {
  EmptyState,
  PartialErrorState,
  StaleNotice,
} from "@/components/states/feedback-states";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/page-header";
import { SectionCard } from "@/components/ui/section-card";
import type { DashboardData } from "@/data/models";
import {
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

export function DashboardView({
  data,
  now = new Date(),
}: {
  data: DashboardData;
  now?: Date;
}) {
  const hasData =
    data.summary.postCount > 0 ||
    data.growth.length > 0 ||
    data.topTimes.length > 0 ||
    data.topContent.length > 0;
  const growthMax = Math.max(1, ...data.growth.map((item) => item.viewsGained));
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
        aside={<Badge tone="positive">Synchronized reporting</Badge>}
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

      {!hasData ? (
        <EmptyState title="No dashboard data is available">
          The reporting views returned no rows. This interface will not start an
          ingestion or refresh workflow.
        </EmptyState>
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 2xl:grid-cols-4">
            <MetricCard
              detail="Sent posts returned by the reporting view"
              icon={Film}
              label="Tracked posts"
              value={formatCompactNumber(data.summary.postCount)}
            />
            <MetricCard
              detail="Cumulative views across returned sent posts"
              icon={Eye}
              label="Tracked views"
              value={formatCompactNumber(data.summary.totalViews)}
            />
            <MetricCard
              detail="Average across returned sent posts"
              icon={BarChart3}
              label="Average views"
              value={formatCompactNumber(data.summary.averageViews)}
            />
            <MetricCard
              detail="Repository-defined calculated interaction rate"
              icon={Gauge}
              label="Interaction rate"
              value={formatPercentage(data.summary.averageInteractionRate)}
            />
          </div>

          <div className="grid gap-6 2xl:grid-cols-[1.35fr_0.65fr]">
            <SectionCard
              description="Daily gains from the existing Looker reporting view; newest dates first."
              title="Recent view growth"
            >
              {data.growth.length === 0 ? (
                <p className="text-sm text-slate-500">
                  No growth rows are available.
                </p>
              ) : (
                <div className="space-y-3">
                  {data.growth.slice(0, 12).map((item, index) => (
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
              description="Highest average-view day and hour combinations."
              title="Strong posting windows"
            >
              <div className="space-y-3">
                {data.topTimes.slice(0, 6).map((time, index) => (
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
            </SectionCard>
          </div>

          <div className="grid gap-6 2xl:grid-cols-[0.8fr_1.2fr]">
            <SectionCard
              description="Existing content labels grouped by the reporting view."
              title="Content signals"
            >
              <div className="space-y-3">
                {data.topContent.slice(0, 6).map((content, index) => (
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
            </SectionCard>

            <SectionCard
              description="Latest sent posts with safe display fields only."
              title="Recent performance"
            >
              <div className="divide-y divide-white/5">
                {data.recentPosts.map((post, index) => (
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
                        <p className="text-[0.68rem] text-slate-600">views</p>
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
            </SectionCard>
          </div>
        </>
      )}
    </div>
  );
}
