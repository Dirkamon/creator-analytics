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
    <div className="border-line bg-surface rounded-2xl border p-5 shadow-xl shadow-black/10">
      <p className="text-muted text-xs font-semibold tracking-[0.12em] uppercase">
        {label}
      </p>
      <p className="text-foreground mt-3 text-3xl font-semibold tracking-tight">
        {value === null ? "—" : formatCompactNumber(value)}
      </p>
      <p className="text-muted mt-1 text-xs leading-5">{detail}</p>
    </div>
  );
}

function queueStatePresentation(state: LabelQueueState) {
  if (state === "pending_export") {
    return { label: "Pending export", tone: "warning" as const };
  }
  if (state === "export_in_progress") {
    return { label: "Export in progress", tone: "warning" as const };
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
        “Pending export” is available to either the app or Make. “Export in
        progress” is atomically owned by Make and cannot be labeled here.
        “Exported · still unlinked” belongs to the existing Google Sheets
        workflow. The app never marks rows exported.
      </StaleNotice>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
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
          detail="Claimed by Make and unavailable to the app"
          label="Export in progress"
          value={data.summary.exportInProgress}
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
            <div className="divide-line divide-y">
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
                          <span className="text-muted text-xs">
                            {item.channelName}
                          </span>
                        </div>
                        <p className="text-secondary mt-3 text-sm leading-6">
                          {item.caption}
                        </p>
                        <div className="text-muted mt-3 flex flex-wrap gap-x-4 gap-y-2 text-xs">
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
                          item.queueState === "export_in_progress" && (
                            <p className="border-warning/15 bg-warning/[0.04] text-warning/80 mt-4 rounded-xl border px-3 py-2 text-xs leading-5">
                              Make has claimed this row for Google Sheets
                              {item.claimedAt
                                ? ` since ${formatDateTime(item.claimedAt)}`
                                : ""}
                              . If it remains here, review the Make run before
                              retrying so a Sheet row is not duplicated.
                            </p>
                          )}
                        {labelingEnabled &&
                          item.queueState === "exported_unlinked" && (
                            <p className="border-warning/15 bg-warning/[0.04] text-warning/80 mt-4 rounded-xl border px-3 py-2 text-xs leading-5">
                              This row is already in Google Sheets. Complete or
                              retry it there so the two workflows do not race.
                            </p>
                          )}
                      </div>
                      {item.externalLink && (
                        <a
                          className="border-line text-secondary hover:border-accent/30 hover:text-accent inline-flex shrink-0 items-center gap-2 rounded-xl border px-3 py-2 text-sm transition"
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
          <div className="border-accent/10 bg-accent/[0.05] text-muted mb-5 flex items-start gap-3 rounded-xl border p-3 text-xs leading-5">
            <Layers3
              aria-hidden
              className="text-accent mt-0.5 shrink-0"
              size={16}
            />
            Clip Group labels are shared. Linking a post to an existing group
            requires an explicit confirmation and preserves that group’s current
            labels.
          </div>

          {data.clipGroups.length === 0 ? (
            <p className="text-muted text-sm">
              No linked Clip Group relationships were returned.
            </p>
          ) : (
            <div className="space-y-3">
              {data.clipGroups.slice(0, 12).map((group) => (
                <article
                  className="border-line bg-foreground/[0.025] rounded-xl border p-4"
                  key={group.name}
                >
                  <div className="flex items-start gap-3">
                    <div className="border-line bg-foreground/5 text-accent rounded-lg border p-2">
                      <Tags aria-hidden size={16} />
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="text-foreground font-medium">
                        {group.name}
                      </p>
                      <p className="text-muted mt-1 text-xs">
                        {group.game ?? "Game unavailable"} ·{" "}
                        {group.contentType ?? "Type unavailable"}
                      </p>
                      <div className="mt-3 flex flex-wrap gap-2">
                        {group.platforms.map((platform) => (
                          <Badge key={platform}>{platform}</Badge>
                        ))}
                      </div>
                      <p className="text-muted mt-3 flex items-center gap-2 text-xs">
                        <Film aria-hidden size={14} />
                        {group.postCount} linked reporting{" "}
                        {group.postCount === 1 ? "row" : "rows"}
                      </p>
                      {group.recentPosts[0]?.publishedAt && (
                        <p className="text-muted mt-2 text-[0.7rem]">
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
