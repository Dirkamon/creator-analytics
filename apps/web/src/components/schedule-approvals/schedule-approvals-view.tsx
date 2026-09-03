import {
  ArrowRight,
  ArrowUpRight,
  CalendarClock,
  CircleAlert,
  Link2,
  ShieldCheck,
  Sparkles,
} from "lucide-react";

import {
  EmptyState,
  PartialErrorState,
  StaleNotice,
} from "@/components/states/feedback-states";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/page-header";
import type {
  ProposalApplicationState,
  ScheduleApprovalsData,
} from "@/data/models";
import { formatDateTime } from "@/lib/format";

function approvalTone(status: string) {
  if (status === "Pending") return "warning" as const;
  if (status === "Approved") return "approved" as const;
  if (status === "Applied") return "applied" as const;
  if (status === "Error") return "danger" as const;
  return "neutral" as const;
}

function applicationPresentation(state: ProposalApplicationState) {
  const presentations = {
    pending: { label: "Pending", tone: "warning" as const },
    approved_blocked: {
      label: "Approved · blocked",
      tone: "danger" as const,
    },
    ready_for_make: { label: "Ready for Make", tone: "ready" as const },
    applied_awaiting_sync: {
      label: "Applied · awaiting sync",
      tone: "applied" as const,
    },
    synchronized: { label: "Synchronized", tone: "positive" as const },
    error: { label: "Error", tone: "danger" as const },
    rejected: { label: "Rejected", tone: "neutral" as const },
    readiness_unavailable: {
      label: "Readiness unavailable",
      tone: "neutral" as const,
    },
  };
  return presentations[state];
}

function EvidenceItem({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-white/5 bg-white/[0.025] p-3">
      <p className="text-[0.65rem] font-semibold tracking-[0.1em] text-slate-600 uppercase">
        {label}
      </p>
      <p className="mt-1 text-sm text-slate-200">{value}</p>
    </div>
  );
}

function exportStateLabel(
  state: ScheduleApprovalsData["proposals"][number]["exportState"],
): string {
  if (state === "pending_export") return "Pending export";
  if (state === "exported") return "Marked exported";
  if (state === "not_observable") {
    return "Not exposed for this proposal status";
  }
  return "Unavailable";
}

function ProposalCard({
  proposal,
  index,
}: {
  proposal: ScheduleApprovalsData["proposals"][number];
  index: number;
}) {
  const application = applicationPresentation(proposal.applicationState);

  return (
    <article
      className="rounded-2xl border border-white/10 bg-slate-950/55 p-5 shadow-xl shadow-black/10 sm:p-6"
      data-proposal-index={index}
    >
      <div className="flex flex-col gap-5 xl:flex-row xl:items-start xl:justify-between">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <Badge>{proposal.platform}</Badge>
            <Badge>{proposal.contentFormat}</Badge>
            <Badge tone={approvalTone(proposal.approvalStatus)}>
              {proposal.approvalStatus}
            </Badge>
            <Badge tone={application.tone}>{application.label}</Badge>
          </div>
          <p className="mt-3 max-w-4xl text-sm leading-6 text-slate-100 sm:text-base">
            {proposal.caption}
          </p>
          <p className="mt-2 text-xs text-slate-500">
            Generated{" "}
            {formatDateTime(proposal.generatedAt, proposal.timezoneName)} ·
            Updated {formatDateTime(proposal.updatedAt, proposal.timezoneName)}
          </p>
        </div>
        {proposal.externalLink && (
          <a
            className="inline-flex shrink-0 items-center gap-2 rounded-xl border border-white/10 px-3 py-2 text-sm text-slate-300 transition hover:border-cyan-300/30 hover:text-cyan-200"
            href={proposal.externalLink}
            rel="noreferrer"
            target="_blank"
          >
            <Link2 aria-hidden size={15} />
            Open post
            <ArrowUpRight aria-hidden size={14} />
          </a>
        )}
      </div>

      <div className="mt-5 grid gap-3 lg:grid-cols-[1fr_auto_1fr] lg:items-stretch">
        <div className="rounded-xl border border-white/5 bg-white/[0.025] p-4">
          <p className="flex items-center gap-2 text-xs font-semibold tracking-[0.1em] text-slate-500 uppercase">
            <CalendarClock aria-hidden size={15} />
            Captured current time
          </p>
          <p className="mt-2 font-medium text-white">
            {formatDateTime(proposal.currentDueAt, proposal.timezoneName)}
          </p>
        </div>
        <div className="hidden items-center text-cyan-300 lg:flex">
          <ArrowRight aria-hidden size={20} />
        </div>
        <div className="rounded-xl border border-cyan-300/10 bg-cyan-300/[0.04] p-4">
          <p className="flex items-center gap-2 text-xs font-semibold tracking-[0.1em] text-cyan-200/70 uppercase">
            <Sparkles aria-hidden size={15} />
            Proposed time
          </p>
          <p className="mt-2 font-medium text-white">
            {formatDateTime(proposal.proposedDueAt, proposal.timezoneName)}
          </p>
          <p className="mt-1 text-xs text-slate-600">{proposal.timezoneName}</p>
        </div>
      </div>

      <div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <EvidenceItem
          label="Confidence / freshness"
          value={`${proposal.confidence ?? "Unavailable"} · ${proposal.metricsStatus ?? "Metrics unknown"}`}
        />
        <EvidenceItem
          label="Recommendation rationale"
          value={`Stored evidence: score ${proposal.recommendationScore ?? "—"} · source rank ${proposal.recommendationRank ?? "—"}`}
        />
        <EvidenceItem
          label="Slot / sample"
          value={`Slot ${proposal.slotRank ?? "—"} · ${proposal.supportingSampleSize ?? "—"} samples`}
        />
        <EvidenceItem
          label="Export state"
          value={exportStateLabel(proposal.exportState)}
        />
      </div>

      <div className="mt-4 grid gap-3 lg:grid-cols-2">
        <div className="rounded-xl border border-white/5 bg-white/[0.025] p-4">
          <p className="flex items-center gap-2 text-xs font-semibold tracking-[0.1em] text-slate-500 uppercase">
            <ShieldCheck aria-hidden size={15} />
            Application / synchronization
          </p>
          <p className="mt-2 text-sm font-medium text-white">
            {application.label}
          </p>
          <p className="mt-1 text-xs leading-5 text-slate-500">
            {proposal.appliedAt
              ? `Applied ${formatDateTime(proposal.appliedAt, proposal.timezoneName)}`
              : proposal.approvedAt
                ? `Approved ${formatDateTime(proposal.approvedAt, proposal.timezoneName)}`
                : "No approval or application timestamp recorded"}
          </p>
          <p className="mt-1 text-xs text-slate-600">
            Last synchronized{" "}
            {proposal.lastSyncedAt
              ? formatDateTime(proposal.lastSyncedAt, proposal.timezoneName)
              : "not recorded"}
          </p>
        </div>

        <div className="rounded-xl border border-white/5 bg-white/[0.025] p-4">
          <p className="flex items-center gap-2 text-xs font-semibold tracking-[0.1em] text-slate-500 uppercase">
            <CircleAlert aria-hidden size={15} />
            Preflight state
          </p>
          {proposal.blockingReasons.length > 0 ? (
            <ul className="mt-2 space-y-1 text-sm leading-5 text-rose-200">
              {proposal.blockingReasons.map((reason) => (
                <li key={reason}>{reason}</li>
              ))}
            </ul>
          ) : (
            <p className="mt-2 text-sm text-slate-400">
              {proposal.applicationState === "ready_for_make"
                ? "The current database preflight passed and the proposal is present in the Make-facing ready view."
                : "No preflight block reason is recorded for this proposal state."}
            </p>
          )}
        </div>
      </div>
    </article>
  );
}

export function ScheduleApprovalsView({
  data,
}: {
  data: ScheduleApprovalsData;
}) {
  return (
    <div className="space-y-7">
      <PageHeader
        aside={<Badge tone="warning">Observation only</Badge>}
        description="Up to 200 recent proposal records with page-local application preflight and synchronization evidence. Decisions and Buffer application remain outside this interface."
        eyebrow="Scheduling workflow"
        title="Schedule Approvals"
      />

      <PartialErrorState errors={data.partialErrors} />

      <StaleNotice title="Applied does not automatically mean synchronized">
        “Ready for Make” is present only when the Approved proposal passes the
        current database preflight and appears in the existing 19-column
        Make-facing view. “Synchronized” additionally requires a later post sync
        whose due time matches the applied target. This page does not verify
        Buffer live or trigger a refresh.
      </StaleNotice>

      {data.proposals.length === 0 ? (
        <EmptyState title="No proposal history was returned">
          There may be no schedule proposals, or proposal history may be
          temporarily unavailable as described above. This page cannot create or
          refresh proposals.
        </EmptyState>
      ) : (
        <div className="space-y-4">
          {data.proposals.map((proposal, index) => (
            <ProposalCard
              index={index}
              key={`${proposal.generatedAt}-${proposal.platform}-${index}`}
              proposal={proposal}
            />
          ))}
        </div>
      )}
    </div>
  );
}
