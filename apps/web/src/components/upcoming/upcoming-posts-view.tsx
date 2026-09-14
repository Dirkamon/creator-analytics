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
    <article className="border-line bg-surface rounded-2xl border p-5 shadow-xl shadow-black/10 sm:p-6">
      <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <Badge>{post.platform}</Badge>
            <span className="text-muted text-xs">{post.channelName}</span>
            <Badge
              tone={post.labelStatus === "labeled" ? "positive" : "warning"}
            >
              {post.labelStatus}
            </Badge>
          </div>
          <p className="text-foreground mt-3 max-w-3xl text-sm leading-6 sm:text-base">
            {post.caption}
          </p>
          <div className="text-muted mt-3 flex flex-wrap gap-x-4 gap-y-2 text-xs">
            <span>{post.clipGroup ?? "No Clip Group"}</span>
            <span>{post.game ?? "Game not labeled"}</span>
            <span>{post.contentType ?? "Content type not labeled"}</span>
          </div>
        </div>

        {post.externalLink && (
          <a
            className="border-line text-secondary hover:border-accent/30 hover:text-accent inline-flex shrink-0 items-center gap-2 rounded-xl border px-3 py-2 text-sm transition"
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

      <div className="border-line mt-5 grid gap-3 border-t pt-5 md:grid-cols-2">
        <div className="bg-foreground/[0.025] rounded-xl p-4">
          <div className="text-muted flex items-center gap-2 text-xs font-semibold tracking-[0.1em] uppercase">
            <CalendarClock aria-hidden size={15} />
            Buffer-synchronized schedule
          </div>
          <p className="text-foreground mt-2 font-medium">
            {formatDateTime(post.dueAt)}
          </p>
          <p className="text-muted mt-1 text-xs">
            Last synced{" "}
            {post.lastSyncedAt
              ? formatDateTime(post.lastSyncedAt)
              : "not recorded"}
          </p>
        </div>

        <div className="bg-foreground/[0.025] rounded-xl p-4">
          <div className="flex items-center justify-between gap-3">
            <div className="text-muted flex items-center gap-2 text-xs font-semibold tracking-[0.1em] uppercase">
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
              <p className="text-foreground mt-2 font-medium">
                {formatDateTime(post.proposal.proposedDueAt)}
              </p>
              <p className="text-muted mt-1 text-xs">
                {post.proposal.confidence ?? "Confidence unavailable"} ·{" "}
                {post.proposal.metricsStatus ?? "Metrics status unavailable"}
              </p>
            </>
          ) : (
            <p className="text-muted mt-2 text-sm">
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
              <div className="border-line mb-3 flex items-baseline justify-between gap-4 border-b pb-3">
                <h2 className="text-foreground font-semibold">
                  {formatDate(posts[0].dueAt)}
                </h2>
                <p className="text-muted text-xs">
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
