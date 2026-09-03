import { ArrowUpRight, CalendarClock, Link2, RefreshCw } from "lucide-react";

import {
  EmptyState,
  PartialErrorState,
  StaleNotice,
} from "@/components/states/feedback-states";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/page-header";
import type { UpcomingPost, UpcomingPostsData } from "@/data/models";
import {
  DEFAULT_DISPLAY_TIMEZONE,
  formatDate,
  formatDateTime,
  localDateKey,
} from "@/lib/format";

function proposalTone(status: string) {
  if (status === "Applied") return "positive" as const;
  if (status === "Approved") return "info" as const;
  if (status === "Error" || status === "Rejected") return "danger" as const;
  if (status === "Pending") return "warning" as const;
  return "neutral" as const;
}

function PostCard({ post }: { post: UpcomingPost }) {
  return (
    <article className="rounded-2xl border border-white/10 bg-slate-950/55 p-5 shadow-xl shadow-black/10 sm:p-6">
      <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <Badge>{post.platform}</Badge>
            <span className="text-xs text-slate-500">{post.channelName}</span>
            <Badge
              tone={post.labelStatus === "labeled" ? "positive" : "warning"}
            >
              {post.labelStatus}
            </Badge>
          </div>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-100 sm:text-base">
            {post.caption}
          </p>
          <div className="mt-3 flex flex-wrap gap-x-4 gap-y-2 text-xs text-slate-500">
            <span>{post.clipGroup ?? "No Clip Group"}</span>
            <span>{post.game ?? "Game not labeled"}</span>
            <span>{post.contentType ?? "Content type not labeled"}</span>
          </div>
        </div>

        {post.externalLink && (
          <a
            className="inline-flex shrink-0 items-center gap-2 rounded-xl border border-white/10 px-3 py-2 text-sm text-slate-300 transition hover:border-cyan-300/30 hover:text-cyan-200"
            href={post.externalLink}
            rel="noreferrer"
            target="_blank"
          >
            <Link2 aria-hidden size={15} />
            Open post
            <ArrowUpRight aria-hidden size={14} />
          </a>
        )}
      </div>

      <div className="mt-5 grid gap-3 border-t border-white/5 pt-5 md:grid-cols-2">
        <div className="rounded-xl bg-white/[0.025] p-4">
          <div className="flex items-center gap-2 text-xs font-semibold tracking-[0.1em] text-slate-500 uppercase">
            <CalendarClock aria-hidden size={15} />
            Buffer-synchronized schedule
          </div>
          <p className="mt-2 font-medium text-white">
            {formatDateTime(post.dueAt)}
          </p>
          <p className="mt-1 text-xs text-slate-600">
            Last synced{" "}
            {post.lastSyncedAt
              ? formatDateTime(post.lastSyncedAt)
              : "not recorded"}
          </p>
        </div>

        <div className="rounded-xl bg-white/[0.025] p-4">
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-2 text-xs font-semibold tracking-[0.1em] text-slate-500 uppercase">
              <RefreshCw aria-hidden size={15} />
              Latest proposal record
            </div>
            {post.proposal && (
              <Badge tone={proposalTone(post.proposal.status)}>
                {post.proposal.status}
              </Badge>
            )}
          </div>
          {post.proposal ? (
            <>
              <p className="mt-2 font-medium text-white">
                {formatDateTime(post.proposal.proposedDueAt)}
              </p>
              <p className="mt-1 text-xs text-slate-600">
                {post.proposal.confidence ?? "Confidence unavailable"} ·{" "}
                {post.proposal.metricsStatus ?? "Metrics status unavailable"}
              </p>
            </>
          ) : (
            <p className="mt-2 text-sm text-slate-500">
              No proposal history was returned for this post.
            </p>
          )}
        </div>
      </div>
    </article>
  );
}

export function UpcomingPostsView({ data }: { data: UpcomingPostsData }) {
  const groups = new Map<string, UpcomingPost[]>();
  for (const post of data.posts) {
    const key = localDateKey(post.dueAt);
    groups.set(key, [...(groups.get(key) ?? []), post]);
  }

  return (
    <div className="space-y-7">
      <PageHeader
        aside={<Badge tone="info">{DEFAULT_DISPLAY_TIMEZONE}</Badge>}
        description="The current schedule synchronized from Buffer, shown separately from proposal history. This page cannot approve, refresh, or apply schedule changes."
        eyebrow="Publishing calendar"
        title="Upcoming Posts"
      />

      <PartialErrorState errors={data.partialErrors} />

      <StaleNotice title="Synchronized is not the same as live-verified">
        Times below come from the most recent Supabase post sync. A proposal
        marked Applied is audit history; it does not independently prove
        Buffer&apos;s current queue state.
      </StaleNotice>

      {data.posts.length === 0 ? (
        <EmptyState title="No upcoming posts were returned">
          There may be no scheduled work, or the existing synchronization may
          need operator review. This page will not trigger a refresh.
        </EmptyState>
      ) : (
        <div className="space-y-8">
          {Array.from(groups.entries()).map(([dateKey, posts]) => (
            <section key={dateKey}>
              <div className="mb-3 flex items-baseline justify-between gap-4 border-b border-white/10 pb-3">
                <h2 className="font-semibold text-white">
                  {formatDate(posts[0].dueAt)}
                </h2>
                <p className="text-xs text-slate-500">
                  {posts.length} {posts.length === 1 ? "post" : "posts"}
                </p>
              </div>
              <div className="space-y-4">
                {posts.map((post) => (
                  <PostCard key={post.key} post={post} />
                ))}
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
