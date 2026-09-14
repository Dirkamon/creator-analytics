import { describe, expect, it } from "vitest";

import {
  applicationPreflightRowSchema,
  buildScheduleApprovalsData,
  proposalPostSyncRowSchema,
  readyScheduleChangeRowSchema,
  scheduleProposalExportRowSchema,
  scheduleProposalRowSchema,
} from "@/data/schedule-approvals";

const proposalId = "00000000-0000-4000-8000-000000000001";

function proposal(status: string) {
  return scheduleProposalRowSchema.parse({
    proposal_id: proposalId,
    buffer_post_id: "SANITIZED_POST",
    platform: "tiktok",
    content_format: "short_form",
    post_text: "Sanitized proposal",
    external_link: "https://example.invalid/proposal",
    current_due_at_utc: "2026-08-31T01:30:00Z",
    proposed_due_at_utc: "2026-08-31T20:00:00Z",
    slot_rank: 1,
    source_recommendation_rank: 2,
    recommendation_score: "0.75",
    confidence: "Moderate",
    supporting_sample_size: 12,
    metrics_status: "Fresh",
    timezone_name: "America/Denver",
    approval_status: status,
    approved_at: status === "Approved" ? "2026-08-29T10:00:00Z" : null,
    applied_at: status === "Applied" ? "2026-08-29T10:00:00Z" : null,
    generated_at: "2026-08-29T09:00:00Z",
    updated_at: "2026-08-29T10:00:00Z",
  });
}

describe("Schedule Approvals data mapping", () => {
  it("derives only repository-observable Pending export states", () => {
    const baseOptions = {
      proposals: [proposal("Pending")],
      preflightRows: [],
      readyRows: [],
      postRows: [],
      exportStateAvailable: true,
      preflightAvailable: true,
      readyStateAvailable: true,
      partialErrors: [],
    };

    const pending = buildScheduleApprovalsData({
      ...baseOptions,
      exports: [
        scheduleProposalExportRowSchema.parse({
          proposal_id: proposalId,
          queue_state: "pending_export",
          claimed_at: null,
        }),
      ],
    });
    const exported = buildScheduleApprovalsData({
      ...baseOptions,
      exports: [
        scheduleProposalExportRowSchema.parse({
          proposal_id: proposalId,
          queue_state: "exported",
          claimed_at: null,
        }),
      ],
    });
    const claimed = buildScheduleApprovalsData({
      ...baseOptions,
      exports: [
        scheduleProposalExportRowSchema.parse({
          proposal_id: proposalId,
          queue_state: "export_in_progress",
          claimed_at: "2026-08-29T10:01:00Z",
        }),
      ],
    });

    expect(pending.proposals[0].exportState).toBe("pending_export");
    expect(exported.proposals[0].exportState).toBe("exported");
    expect(claimed.proposals[0]).toMatchObject({
      exportState: "export_in_progress",
      exportClaimedAt: "2026-08-29T10:01:00Z",
      proposalId,
    });
  });

  it("uses the ready view and preflight to distinguish Approved states", () => {
    const ready = buildScheduleApprovalsData({
      proposals: [proposal("Approved")],
      exports: [
        scheduleProposalExportRowSchema.parse({
          proposal_id: proposalId,
          queue_state: "exported",
          claimed_at: null,
        }),
      ],
      preflightRows: [
        applicationPreflightRowSchema.parse({
          proposal_id: proposalId,
          post_last_synced_at: "2026-08-29T09:30:00Z",
          blocking_reasons: [],
          is_ready: true,
        }),
      ],
      readyRows: [
        readyScheduleChangeRowSchema.parse({ proposal_id: proposalId }),
      ],
      postRows: [],
      exportStateAvailable: true,
      preflightAvailable: true,
      readyStateAvailable: true,
      partialErrors: [],
    });

    expect(ready.proposals[0]).toMatchObject({
      applicationState: "ready_for_make",
      exportState: "not_observable",
      recommendationScore: 0.75,
    });

    const blocked = buildScheduleApprovalsData({
      proposals: [proposal("Approved")],
      exports: [],
      preflightRows: [
        applicationPreflightRowSchema.parse({
          proposal_id: proposalId,
          post_last_synced_at: "2026-08-29T09:30:00Z",
          blocking_reasons: ["Blocked: current schedule changed"],
          is_ready: false,
        }),
      ],
      readyRows: [],
      postRows: [],
      exportStateAvailable: true,
      preflightAvailable: true,
      readyStateAvailable: true,
      partialErrors: [],
    });

    expect(blocked.proposals[0]).toMatchObject({
      applicationState: "approved_blocked",
      blockingReasons: ["Blocked: current schedule changed"],
    });
  });

  it("requires a later matching post sync before showing synchronized", () => {
    const applied = proposal("Applied");
    const result = buildScheduleApprovalsData({
      proposals: [applied],
      exports: [],
      preflightRows: [],
      readyRows: [],
      postRows: [
        proposalPostSyncRowSchema.parse({
          buffer_post_id: "SANITIZED_POST",
          due_at: "2026-08-31T20:00:00+00:00",
          last_synced_at: "2026-08-29T10:30:00Z",
        }),
      ],
      exportStateAvailable: true,
      preflightAvailable: true,
      readyStateAvailable: true,
      partialErrors: [],
    });

    expect(result.proposals[0].applicationState).toBe("synchronized");
  });
});
