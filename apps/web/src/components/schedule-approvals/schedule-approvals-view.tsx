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
import { ScheduleDecisionEditor } from "@/components/schedule-approvals/schedule-decision-editor";
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
    <div className="border-line bg-foreground/[0.025] rounded-xl border p-3">
      <p className="text-muted text-[0.65rem] font-semibold tracking-[0.1em] uppercase">
        {label}
      </p>
      <p className="text-secondary mt-1 text-sm">{value}</p>
    </div>
  );
}

function exportStateLabel(
  state: ScheduleApprovalsData["proposals"][number]["exportState"],
): string {
  if (state === "pending_export") return "Pending export";
  if (state === "export_in_progress") return "Export in progress";
  if (state === "exported") return "Marked exported";
  if (state === "not_observable") {
    return "Not exposed for this proposal status";
  }
  return "Unavailable";
}

function ProposalCard({
  proposal,
  index,
  decisionsEnabled,
}: {
  proposal: ScheduleApprovalsData["proposals"][number];
  index: number;
  decisionsEnabled: boolean;
}) {
  const application = applicationPresentation(proposal.applicationState);

  return (
    <article
      className="border-line bg-surface rounded-2xl border p-5 shadow-xl shadow-black/10 sm:p-6"
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
          <p className="text-foreground mt-3 max-w-4xl text-sm leading-6 sm:text-base">
            {proposal.caption}
          </p>
          <p className="text-muted mt-2 text-xs">
            Generated{" "}
            {formatDateTime(proposal.generatedAt, proposal.timezoneName)} ·
            Updated {formatDateTime(proposal.updatedAt, proposal.timezoneName)}
          </p>
        </div>
        {proposal.externalLink && (
          <a
            className="border-line text-secondary hover:border-accent/30 hover:text-accent inline-flex shrink-0 items-center gap-2 rounded-xl border px-3 py-2 text-sm transition"
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
        <div className="border-line bg-foreground/[0.025] rounded-xl border p-4">
          <p className="text-muted flex items-center gap-2 text-xs font-semibold tracking-[0.1em] uppercase">
            <CalendarClock aria-hidden size={15} />
            Captured current time
          </p>
          <p className="text-foreground mt-2 font-medium">
            {formatDateTime(proposal.currentDueAt, proposal.timezoneName)}
          </p>
        </div>
        <div className="text-accent hidden items-center lg:flex">
          <ArrowRight aria-hidden size={20} />
        </div>
        <div className="border-accent/10 bg-accent/[0.04] rounded-xl border p-4">
          <p className="text-accent/70 flex items-center gap-2 text-xs font-semibold tracking-[0.1em] uppercase">
            <Sparkles aria-hidden size={15} />
            Proposed time
          </p>
          <p className="text-foreground mt-2 font-medium">
            {formatDateTime(proposal.proposedDueAt, proposal.timezoneName)}
          </p>
          <p className="text-muted mt-1 text-xs">{proposal.timezoneName}</p>
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
        <div className="border-line bg-foreground/[0.025] rounded-xl border p-4">
          <p className="text-muted flex items-center gap-2 text-xs font-semibold tracking-[0.1em] uppercase">
            <ShieldCheck aria-hidden size={15} />
            Application / synchronization
          </p>
          <p className="text-foreground mt-2 text-sm font-medium">
            {application.label}
          </p>
          <p className="text-muted mt-1 text-xs leading-5">
            {proposal.appliedAt
              ? `Applied ${formatDateTime(proposal.appliedAt, proposal.timezoneName)}`
              : proposal.approvedAt
                ? `Approved ${formatDateTime(proposal.approvedAt, proposal.timezoneName)}`
                : "No approval or application timestamp recorded"}
          </p>
          <p className="text-muted mt-1 text-xs">
            Last synchronized{" "}
            {proposal.lastSyncedAt
              ? formatDateTime(proposal.lastSyncedAt, proposal.timezoneName)
              : "not recorded"}
          </p>
        </div>

        <div className="border-line bg-foreground/[0.025] rounded-xl border p-4">
          <p className="text-muted flex items-center gap-2 text-xs font-semibold tracking-[0.1em] uppercase">
            <CircleAlert aria-hidden size={15} />
            Preflight state
          </p>
          {proposal.blockingReasons.length > 0 ? (
            <ul className="text-danger mt-2 space-y-1 text-sm leading-5">
              {proposal.blockingReasons.map((reason) => (
                <li key={reason}>{reason}</li>
              ))}
            </ul>
          ) : (
            <p className="text-muted mt-2 text-sm">
              {proposal.applicationState === "ready_for_make"
                ? "The current database preflight passed and the proposal is present in the Make-facing ready view."
                : "No preflight block reason is recorded for this proposal state."}
            </p>
          )}
        </div>
      </div>

      {decisionsEnabled && proposal.approvalStatus === "Pending" && (
        <>
          {proposal.exportState === "pending_export" ? (
            <ScheduleDecisionEditor
              expectedUpdatedAt={proposal.updatedAt}
              proposalId={proposal.proposalId}
            />
          ) : (
            <div className="border-warning/15 bg-warning/[0.045] text-warning mt-4 rounded-xl border p-4 text-sm">
              {proposal.exportState === "export_in_progress"
                ? `Google Sheets export is in progress${
                    proposal.exportClaimedAt
                      ? ` since ${formatDateTime(proposal.exportClaimedAt, proposal.timezoneName)}`
                      : ""
                  }. Refresh after it finishes, then record the decision in Google Sheets.`
                : proposal.exportState === "exported"
                  ? "This proposal belongs to the existing Google Sheets workflow. Record its decision in the Schedule Approvals sheet."
                  : "Decision controls are unavailable because the proposal ownership state could not be verified. Refresh before taking action."}
            </div>
          )}
        </>
      )}
    </article>
  );
}

export function ScheduleApprovalsView({
  data,
  decisionsEnabled = false,
}: {
  data: ScheduleApprovalsData;
  decisionsEnabled?: boolean;
}) {
  return (
    <div className="space-y-7">
      <PageHeader
        aside={
          <Badge tone={decisionsEnabled ? "ready" : "warning"}>
            {decisionsEnabled ? "Controlled decisions" : "Observation only"}
          </Badge>
        }
        description={
          decisionsEnabled
            ? "Up to 200 recent proposal records with controlled Pending decisions, current database preflight, and synchronization evidence. Buffer application remains in the existing Make workflow."
            : "Up to 200 recent proposal records with page-local application preflight and synchronization evidence. Decisions and Buffer application remain outside this interface."
        }
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
              decisionsEnabled={decisionsEnabled}
              index={index}
              key={proposal.proposalId}
              proposal={proposal}
            />
          ))}
        </div>
      )}
    </div>
  );
}
