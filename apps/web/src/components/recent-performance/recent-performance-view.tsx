"use client";

import {
  ArrowUpRight,
  Bookmark,
  ChevronLeft,
  ChevronRight,
  Eye,
  Gauge,
  Heart,
  MessageCircle,
  Share2,
} from "lucide-react";
import { useMemo, useState } from "react";

import { ReportFilters } from "@/components/reporting/report-filters";
import {
  EmptyState,
  PartialErrorState,
} from "@/components/states/feedback-states";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/page-header";
import { PlatformBadge } from "@/components/ui/platform-badge";
import type {
  RecentPerformanceData,
  RecentPerformancePost,
} from "@/data/models";
import {
  EMPTY_REPORT_FILTERS,
  filterReportingPosts,
  reportFilterOptions,
} from "@/data/report-filters";
import {
  DEFAULT_DISPLAY_TIMEZONE,
  formatDateTime,
  formatPercentage,
  isCalendarDateStale,
} from "@/lib/format";

const PAGE_SIZE = 10;
const countFormat = new Intl.NumberFormat("en-US", {
  maximumFractionDigits: 0,
});
const formatCount = (value: number | null) =>
  value === null ? "—" : countFormat.format(value);

function publishedTime(post: RecentPerformancePost) {
  const time = post.publishedAt ? Date.parse(post.publishedAt) : NaN;
  return Number.isFinite(time) ? time : -Infinity;
}

function PostDetails({
  post,
  now,
}: {
  post: RecentPerformancePost;
  now: Date;
}) {
  const hasMetricDate = Boolean(post.latestMetricDate);
  const stale =
    post.latestMetricDate !== null &&
    isCalendarDateStale({ value: post.latestMetricDate, now, maxAgeDays: 2 });
  const metrics = [
    { label: "Views", value: formatCount(post.views), icon: Eye },
    {
      label: "Likes / reactions",
      value: formatCount(post.reactions),
      icon: Heart,
    },
    {
      label: "Comments",
      value: formatCount(post.comments),
      icon: MessageCircle,
    },
    { label: "Shares", value: formatCount(post.shares), icon: Share2 },
    { label: "Saves", value: formatCount(post.saves), icon: Bookmark },
    {
      label: "Interaction rate",
      value: formatPercentage(post.interactionRate),
      icon: Gauge,
    },
  ];

  return (
    <article
      className="section-card"
      aria-label={`${post.platform}: ${post.clipGroup ?? post.caption}`}
    >
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0 flex-1 basis-64">
          <div className="flex flex-wrap items-center gap-2">
            <PlatformBadge platform={post.platform} />
            {post.channelName && (
              <span className="text-muted text-xs">{post.channelName}</span>
            )}
            <Badge tone={!hasMetricDate || stale ? "warning" : "neutral"}>
              {!hasMetricDate
                ? "Metrics date unavailable"
                : stale
                  ? "Metrics may be out of date"
                  : "Latest synced metrics"}
            </Badge>
          </div>
          <h2 className="text-foreground mt-3 text-base font-semibold break-words">
            {post.clipGroup ?? "Unlabeled clip"}
          </h2>
          <p className="text-muted mt-1 text-xs">
            {post.publishedAt && Number.isFinite(publishedTime(post))
              ? `Published ${formatDateTime(post.publishedAt)}`
              : "Publication time unavailable"}
          </p>
        </div>
        {post.externalLink && (
          <a
            className="border-line text-secondary hover:border-accent/50 hover:text-accent inline-flex shrink-0 items-center gap-2 rounded-xl border px-3 py-2 text-sm font-medium transition"
            href={post.externalLink}
            target="_blank"
            rel="noreferrer"
            aria-label={`Open ${post.platform} post: ${post.clipGroup ?? post.caption}`}
          >
            Open post <ArrowUpRight aria-hidden size={15} />
          </a>
        )}
      </div>
      <p className="text-secondary mt-4 text-sm leading-6 break-words whitespace-pre-wrap">
        {post.caption}
      </p>
      <div className="text-muted mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs">
        <span>{post.game ?? "Game not labeled"}</span>
        <span>{post.contentType ?? "Type not labeled"}</span>
      </div>
      <dl className="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-3 2xl:grid-cols-6">
        {metrics.map(({ label, value, icon: Icon }) => (
          <div
            key={label}
            className="border-line bg-canvas/60 min-w-0 rounded-xl border p-3 sm:p-4"
          >
            <dt className="text-muted flex items-center gap-2 text-xs">
              <Icon aria-hidden size={14} className="shrink-0" />
              {label}
            </dt>
            <dd className="text-foreground mt-2 text-xl font-semibold break-words tabular-nums">
              {value}
            </dd>
          </div>
        ))}
      </dl>
      <p className="text-muted mt-4 text-xs">
        {post.latestMetricDate ? (
          <>
            Metrics through{" "}
            <time dateTime={post.latestMetricDate}>
              {post.latestMetricDate}
            </time>
          </>
        ) : (
          "No metrics date was reported for this post."
        )}
      </p>
    </article>
  );
}

export function RecentPerformanceView({
  data,
  now = new Date(),
}: {
  data: RecentPerformanceData;
  now?: Date;
}) {
  const [filters, setFilters] = useState(EMPTY_REPORT_FILTERS);
  const [page, setPage] = useState(1);
  const options = useMemo(() => reportFilterOptions(data.posts), [data.posts]);
  const posts = useMemo(
    () =>
      filterReportingPosts(data.posts, filters).sort((a, b) => {
        const left = publishedTime(a);
        const right = publishedTime(b);
        return left === right
          ? a.key.localeCompare(b.key)
          : left > right
            ? -1
            : 1;
      }),
    [data.posts, filters],
  );
  const pageCount = Math.max(1, Math.ceil(posts.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const visible = posts.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const readFailed = data.partialErrors.length > 0 && data.posts.length === 0;

  return (
    <div className="space-y-7">
      <PageHeader
        title="Recent Performance"
        eyebrow="Your latest posts, in detail"
        description="See how each recent post is doing, with your newest published posts first."
        aside={<Badge tone="info">{DEFAULT_DISPLAY_TIMEZONE}</Badge>}
      />
      <PartialErrorState errors={data.partialErrors} />
      {readFailed ? (
        <p className="text-muted text-sm">
          We couldn’t load your recent posts. Refresh to try again; no post or
          metric has been changed.
        </p>
      ) : data.posts.length === 0 ? (
        <EmptyState title="No published posts yet">
          Your posts will appear here after they publish and sync. Scheduled
          posts are shown in Upcoming Posts.
        </EmptyState>
      ) : (
        <>
          <ReportFilters
            games={options.games}
            platforms={options.platforms}
            value={filters}
            onChange={(next) => {
              setFilters(next);
              setPage(1);
            }}
          />
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 className="text-foreground font-semibold">Newest first</h2>
              <p className="text-muted mt-1 text-sm" aria-live="polite">
                {countFormat.format(posts.length)} matching{" "}
                {posts.length === 1 ? "post" : "posts"} · {PAGE_SIZE} per page
              </p>
            </div>
            <p className="text-muted text-xs">
              Page {safePage} of {pageCount}
            </p>
          </div>
          <p className="text-muted max-w-4xl text-xs leading-5">
            Counts are the latest synchronized totals, not live updates or daily
            gains. Likes use the platform’s reactions field. — means a value
            wasn’t reported; 0 is a reported zero. Interaction rate uses the
            existing reporting calculation.
          </p>
          {data.posts.length >= 10000 && (
            <p className="text-warning text-sm">
              This view is limited to the 10,000 most recent published posts.
            </p>
          )}
          {visible.length === 0 ? (
            <EmptyState title="No posts match these filters">
              Clear or broaden the filters to see recent performance.
            </EmptyState>
          ) : (
            <div className="space-y-5">
              {visible.map((post) => (
                <PostDetails key={post.key} post={post} now={now} />
              ))}
            </div>
          )}
          <nav
            aria-label="Recent performance pages"
            className="border-line flex flex-wrap items-center justify-between gap-4 border-t pt-5"
          >
            <button
              type="button"
              className="border-line text-secondary hover:border-accent/50 inline-flex items-center gap-2 rounded-xl border px-3 py-2 text-sm disabled:cursor-not-allowed disabled:opacity-40"
              disabled={safePage <= 1}
              onClick={() => setPage(safePage - 1)}
            >
              <ChevronLeft aria-hidden size={16} />
              Previous
            </button>
            <span className="text-muted text-xs">
              Showing{" "}
              {visible.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1}–
              {Math.min(safePage * PAGE_SIZE, posts.length)} of{" "}
              {countFormat.format(posts.length)}
            </span>
            <button
              type="button"
              className="border-line text-secondary hover:border-accent/50 inline-flex items-center gap-2 rounded-xl border px-3 py-2 text-sm disabled:cursor-not-allowed disabled:opacity-40"
              disabled={safePage >= pageCount}
              onClick={() => setPage(safePage + 1)}
            >
              Next
              <ChevronRight aria-hidden size={16} />
            </button>
          </nav>
        </>
      )}
    </div>
  );
}
