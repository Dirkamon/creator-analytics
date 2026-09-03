import { ArrowUpRight, Film, Layers3, Link2, Tags } from "lucide-react";

import { LabelEditor } from "@/components/label-queue/label-editor";
import {
  EmptyState,
  PartialErrorState,
  StaleNotice,
} from "@/components/states/feedback-states";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/page-header";
import { SectionCard } from "@/components/ui/section-card";
import type { LabelQueueData, LabelQueueState } from "@/data/models";
import {
  formatCompactNumber,
  formatDateTime,
  formatLocalWallTime,
} from "@/lib/format";

function QueueMetric({
  label,
  value,
  detail,
}: {
  label: string;
  value: number | null;
  detail: string;
}) {
  return (
    <div className="rounded-2xl border border-white/10 bg-slate-950/55 p-5 shadow-xl shadow-black/10">
      <p className="text-xs font-semibold tracking-[0.12em] text-slate-500 uppercase">
        {label}
      </p>
      <p className="mt-3 text-3xl font-semibold tracking-tight text-white">
        {value === null ? "—" : formatCompactNumber(value)}
      </p>
      <p className="mt-1 text-xs leading-5 text-slate-500">{detail}</p>
    </div>
  );
}

function queueStatePresentation(state: LabelQueueState) {
  if (state === "pending_export") {
    return { label: "Pending export", tone: "warning" as const };
  }
  if (state === "exported_unlinked") {
    return { label: "Exported · still unlinked", tone: "info" as const };
  }
  return { label: "Export state unavailable", tone: "neutral" as const };
}

export function LabelQueueView({
  data,
  labelingEnabled = false,
}: {
  data: LabelQueueData;
  labelingEnabled?: boolean;
}) {
  return (
    <div className="space-y-7">
      <PageHeader
        aside={
          <Badge tone={labelingEnabled ? "positive" : "warning"}>
            {labelingEnabled ? "Controlled labeling" : "Observation only"}
          </Badge>
        }
        description={
          labelingEnabled
            ? "Label posts before they are exported to Google Sheets. Exported rows remain owned by the existing Make and Sheets fallback."
            : "Database-observed unlabeled work and recent shared Clip Group relationships. Labeling remains disabled in this deployment."
        }
        eyebrow="Content organization"
        title="Label Queue"
      />

      <PartialErrorState errors={data.partialErrors} />

      <StaleNotice title="Queue state is database-observed, not a Sheet workflow state">
        “Pending export” means the export timestamp is still empty and, when
        controlled labeling is enabled, the app may own that row. “Exported ·
        still unlinked” means Google Sheets already owns the row; finish it in
        the existing Sheet workflow. The app never marks rows exported.
      </StaleNotice>

      <div className="grid gap-4 sm:grid-cols-3">
        <QueueMetric
          detail="Posts with no linked content item"
          label="Unlinked"
          value={data.summary.unlinked}
        />
        <QueueMetric
          detail="Unlinked posts not yet marked exported"
          label="Pending export"
          value={data.summary.pendingExport}
        />
        <QueueMetric
          detail="Marked exported but still without content linkage"
          label="Exported · unlinked"
          value={data.summary.exportedStillUnlinked}
        />
      </div>

      <div className="grid gap-6 2xl:grid-cols-[1.35fr_0.65fr]">
        <SectionCard
          description="Every row remains unlinked in Supabase. Export state is derived without changing the queue."
          title="Observed queue"
        >
          {data.items.length === 0 ? (
            <EmptyState title="No unlinked posts were returned">
              The database currently exposes no Label Queue rows, or the queue
              read failed as described above. This page will not start a Sheet
              export.
            </EmptyState>
          ) : (
            <div className="divide-y divide-white/5">
              {data.items.map((item) => {
                const state = queueStatePresentation(item.queueState);
                return (
                  <article
                    className="py-5 first:pt-0 last:pb-0"
                    key={item.bufferPostId}
                  >
                    <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <Badge>{item.platform}</Badge>
                          <Badge tone={state.tone}>{state.label}</Badge>
                          <span className="text-xs text-slate-500">
                            {item.channelName}
                          </span>
                        </div>
                        <p className="mt-3 text-sm leading-6 text-slate-200">
                          {item.caption}
                        </p>
                        <div className="mt-3 flex flex-wrap gap-x-4 gap-y-2 text-xs text-slate-500">
                          <span>
                            {item.publishedAtLocal
                              ? formatLocalWallTime(item.publishedAtLocal)
                              : "Publication time unavailable"}
                          </span>
                          <span>Source status: {item.sourceStatus}</span>
                          <span>
                            {item.views === null
                              ? "Views unavailable"
                              : `${formatCompactNumber(item.views)} views`}
                          </span>
                          <span>
                            Metrics through {item.latestMetricDate ?? "unknown"}
                          </span>
                        </div>
                        {labelingEnabled &&
                          item.queueState === "pending_export" && (
                            <LabelEditor
                              bufferPostId={item.bufferPostId}
                              clipGroups={data.clipGroups}
                            />
                          )}
                        {labelingEnabled &&
                          item.queueState === "exported_unlinked" && (
                            <p className="mt-4 rounded-xl border border-amber-300/15 bg-amber-300/[0.04] px-3 py-2 text-xs leading-5 text-amber-100/80">
                              This row is already in Google Sheets. Complete or
                              retry it there so the two workflows do not race.
                            </p>
                          )}
                      </div>
                      {item.externalLink && (
                        <a
                          className="inline-flex shrink-0 items-center gap-2 rounded-xl border border-white/10 px-3 py-2 text-sm text-slate-300 transition hover:border-cyan-300/30 hover:text-cyan-200"
                          href={item.externalLink}
                          rel="noreferrer"
                          target="_blank"
                        >
                          <Link2 aria-hidden size={15} />
                          Open post
                          <ArrowUpRight aria-hidden size={14} />
                        </a>
                      )}
                    </div>
                  </article>
                );
              })}
            </div>
          )}
        </SectionCard>

        <SectionCard
          description="Shared labels from up to 300 recent linked reporting rows. Counts describe that bounded result, not every historical post."
          title="Shared Clip Groups"
        >
          <div className="mb-5 flex items-start gap-3 rounded-xl border border-cyan-300/10 bg-cyan-300/[0.05] p-3 text-xs leading-5 text-slate-400">
            <Layers3
              aria-hidden
              className="mt-0.5 shrink-0 text-cyan-200"
              size={16}
            />
            Clip Group labels are shared. Linking a post to an existing group
            requires an explicit confirmation and preserves that group’s current
            labels.
          </div>

          {data.clipGroups.length === 0 ? (
            <p className="text-sm text-slate-500">
              No linked Clip Group relationships were returned.
            </p>
          ) : (
            <div className="space-y-3">
              {data.clipGroups.slice(0, 12).map((group) => (
                <article
                  className="rounded-xl border border-white/5 bg-white/[0.025] p-4"
                  key={group.name}
                >
                  <div className="flex items-start gap-3">
                    <div className="rounded-lg border border-white/10 bg-white/5 p-2 text-cyan-200">
                      <Tags aria-hidden size={16} />
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="font-medium text-white">{group.name}</p>
                      <p className="mt-1 text-xs text-slate-500">
                        {group.game ?? "Game unavailable"} ·{" "}
                        {group.contentType ?? "Type unavailable"}
                      </p>
                      <div className="mt-3 flex flex-wrap gap-2">
                        {group.platforms.map((platform) => (
                          <Badge key={platform}>{platform}</Badge>
                        ))}
                      </div>
                      <p className="mt-3 flex items-center gap-2 text-xs text-slate-500">
                        <Film aria-hidden size={14} />
                        {group.postCount} linked reporting{" "}
                        {group.postCount === 1 ? "row" : "rows"}
                      </p>
                      {group.recentPosts[0]?.publishedAt && (
                        <p className="mt-2 text-[0.7rem] text-slate-600">
                          Latest shown{" "}
                          {formatDateTime(group.recentPosts[0].publishedAt)}
                        </p>
                      )}
                    </div>
                  </div>
                </article>
              ))}
            </div>
          )}
        </SectionCard>
      </div>
    </div>
  );
}
