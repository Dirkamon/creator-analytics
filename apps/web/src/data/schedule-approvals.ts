import { z } from "zod";

import type {
  PartialDataError,
  ProposalApplicationState,
  ProposalExportState,
  ScheduleApprovalsData,
} from "@/data/models";
import { sanitizeExternalUrl } from "@/lib/format";

const numericValue = z
  .union([z.number(), z.string()])
  .transform((value) => Number(value))
  .refine(Number.isFinite);

export const scheduleProposalRowSchema = z.object({
  proposal_id: z.string().uuid(),
  buffer_post_id: z.string(),
  platform: z.string(),
  content_format: z.string(),
  post_text: z.string().nullable(),
  external_link: z.string().nullable(),
  current_due_at_utc: z.string(),
  proposed_due_at_utc: z.string(),
  slot_rank: numericValue.nullable(),
  source_recommendation_rank: numericValue.nullable(),
  recommendation_score: numericValue.nullable(),
  confidence: z.string().nullable(),
  supporting_sample_size: numericValue.nullable(),
  metrics_status: z.string().nullable(),
  timezone_name: z.string(),
  approval_status: z.string(),
  approved_at: z.string().nullable(),
  applied_at: z.string().nullable(),
  generated_at: z.string(),
  updated_at: z.string(),
});

export const scheduleProposalExportRowSchema = z.object({
  proposal_id: z.string().uuid(),
});

export const applicationPreflightRowSchema = z.object({
  proposal_id: z.string().uuid(),
  post_last_synced_at: z.string().nullable(),
  blocking_reasons: z.array(z.string()).nullable(),
  is_ready: z.boolean(),
});

export const readyScheduleChangeRowSchema = z.object({
  proposal_id: z.string().uuid(),
});

export const proposalPostSyncRowSchema = z.object({
  buffer_post_id: z.string(),
  due_at: z.string().nullable(),
  last_synced_at: z.string().nullable(),
});

type ScheduleProposalRow = z.infer<typeof scheduleProposalRowSchema>;
type ScheduleProposalExportRow = z.infer<
  typeof scheduleProposalExportRowSchema
>;
type ApplicationPreflightRow = z.infer<typeof applicationPreflightRowSchema>;
type ReadyScheduleChangeRow = z.infer<typeof readyScheduleChangeRowSchema>;
type ProposalPostSyncRow = z.infer<typeof proposalPostSyncRowSchema>;

function timestampsMatch(left: string | null, right: string): boolean {
  if (!left) return false;
  const leftTime = Date.parse(left);
  const rightTime = Date.parse(right);
  return (
    Number.isFinite(leftTime) &&
    Number.isFinite(rightTime) &&
    leftTime === rightTime
  );
}

function synchronizedAfterApplication(options: {
  proposal: ScheduleProposalRow;
  post: ProposalPostSyncRow | undefined;
}): boolean {
  if (!options.proposal.applied_at || !options.post?.last_synced_at) {
    return false;
  }

  return (
    timestampsMatch(
      options.post.due_at,
      options.proposal.proposed_due_at_utc,
    ) &&
    Date.parse(options.post.last_synced_at) >=
      Date.parse(options.proposal.applied_at)
  );
}

function applicationState(options: {
  proposal: ScheduleProposalRow;
  preflight: ApplicationPreflightRow | undefined;
  readyForMake: boolean;
  readinessAvailable: boolean;
  post: ProposalPostSyncRow | undefined;
}): ProposalApplicationState {
  if (options.proposal.approval_status === "Error") {
    return "error";
  }
  if (options.proposal.approval_status === "Rejected") return "rejected";
  if (options.proposal.approval_status === "Applied") {
    return synchronizedAfterApplication({
      proposal: options.proposal,
      post: options.post,
    })
      ? "synchronized"
      : "applied_awaiting_sync";
  }
  if (options.proposal.approval_status === "Approved") {
    if (!options.readinessAvailable) return "readiness_unavailable";
    if (options.readyForMake) return "ready_for_make";
    if (options.preflight && !options.preflight.is_ready) {
      return "approved_blocked";
    }
    return "readiness_unavailable";
  }
  return "pending";
}

function exportState(options: {
  proposal: ScheduleProposalRow;
  pendingExportIds: ReadonlySet<string>;
  exportStateAvailable: boolean;
}): ProposalExportState {
  if (!options.exportStateAvailable) return "unavailable";
  if (options.proposal.approval_status !== "Pending") return "not_observable";
  return options.pendingExportIds.has(options.proposal.proposal_id)
    ? "pending_export"
    : "exported";
}

export function buildScheduleApprovalsData(options: {
  proposals: ScheduleProposalRow[];
  exports: ScheduleProposalExportRow[];
  preflightRows: ApplicationPreflightRow[];
  readyRows: ReadyScheduleChangeRow[];
  postRows: ProposalPostSyncRow[];
  exportStateAvailable: boolean;
  preflightAvailable: boolean;
  readyStateAvailable: boolean;
  partialErrors: PartialDataError[];
}): ScheduleApprovalsData {
  const pendingExportIds = new Set(
    options.exports.map((row) => row.proposal_id),
  );
  const preflightByProposal = new Map(
    options.preflightRows.map((row) => [row.proposal_id, row]),
  );
  const readyIds = new Set(options.readyRows.map((row) => row.proposal_id));
  const postById = new Map(
    options.postRows.map((row) => [row.buffer_post_id, row]),
  );

  return {
    proposals: options.proposals.map((proposal) => {
      const preflight = preflightByProposal.get(proposal.proposal_id);
      const post = postById.get(proposal.buffer_post_id);
      const isApproved = proposal.approval_status === "Approved";
      const readinessAvailable =
        !isApproved ||
        (options.preflightAvailable && options.readyStateAvailable);

      return {
        platform: proposal.platform,
        contentFormat: proposal.content_format,
        caption: proposal.post_text?.trim() || "Untitled schedule proposal",
        externalLink: sanitizeExternalUrl(proposal.external_link),
        currentDueAt: proposal.current_due_at_utc,
        proposedDueAt: proposal.proposed_due_at_utc,
        approvalStatus: proposal.approval_status,
        applicationState: applicationState({
          proposal,
          preflight,
          readyForMake: readyIds.has(proposal.proposal_id),
          readinessAvailable,
          post,
        }),
        confidence: proposal.confidence,
        metricsStatus: proposal.metrics_status,
        timezoneName: proposal.timezone_name,
        recommendationScore: proposal.recommendation_score,
        recommendationRank: proposal.source_recommendation_rank,
        slotRank: proposal.slot_rank,
        supportingSampleSize: proposal.supporting_sample_size,
        generatedAt: proposal.generated_at,
        updatedAt: proposal.updated_at,
        approvedAt: proposal.approved_at,
        appliedAt: proposal.applied_at,
        exportState: exportState({
          proposal,
          pendingExportIds,
          exportStateAvailable: options.exportStateAvailable,
        }),
        lastSyncedAt:
          post?.last_synced_at ?? preflight?.post_last_synced_at ?? null,
        blockingReasons: preflight?.blocking_reasons ?? [],
      };
    }),
    partialErrors: options.partialErrors,
  };
}
