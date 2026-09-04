import { beforeEach, describe, expect, it, vi } from "vitest";

import { ForbiddenError } from "@/auth/errors";
import { initialScheduleDecisionActionState } from "@/scheduling/state";

const mocks = vi.hoisted(() => ({
  requireAuthorizedUser: vi.fn(),
  getServerEnvironment: vi.fn(),
  getServerScheduleDecisionClient: vi.fn(),
  revalidatePath: vi.fn(),
  begin: vi.fn(),
  unsafe: vi.fn(),
}));

vi.mock("next/cache", () => ({ revalidatePath: mocks.revalidatePath }));
vi.mock("@/auth/authorization.server", () => ({
  requireAuthorizedUser: mocks.requireAuthorizedUser,
}));
vi.mock("@/config/env-server", () => ({
  getServerEnvironment: mocks.getServerEnvironment,
}));
vi.mock("@/lib/database/server-data", () => ({
  getServerScheduleDecisionClient: mocks.getServerScheduleDecisionClient,
}));

import { saveScheduleDecision } from "@/scheduling/actions";

function decisionForm(decision: "Approved" | "Rejected" = "Approved") {
  const formData = new FormData();
  formData.set("proposal_id", "00000000-0000-4000-8000-000000000001");
  formData.set("expected_updated_at", "2026-09-04T12:00:00.000Z");
  formData.set("decision", decision);
  formData.set("confirm_decision", "on");
  return formData;
}

describe("controlled schedule decision action", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.requireAuthorizedUser.mockResolvedValue({
      id: "SANITIZED_USER",
      email: "operator@example.invalid",
    });
    mocks.getServerEnvironment.mockReturnValue({
      CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED: true,
    });
    mocks.unsafe.mockResolvedValue([
      {
        result_status: "Approved",
        result_approved_at: "2026-09-04T12:01:00.000Z",
        result_rejected_at: null,
      },
    ]);
    mocks.begin.mockImplementation(
      async (
        callback: (transaction: { unsafe: typeof mocks.unsafe }) => unknown,
      ) => callback({ unsafe: mocks.unsafe }),
    );
    mocks.getServerScheduleDecisionClient.mockReturnValue({
      begin: mocks.begin,
    });
  });

  it("authorizes and calls only the audited decision wrapper", async () => {
    await expect(
      saveScheduleDecision(
        initialScheduleDecisionActionState,
        decisionForm("Approved"),
      ),
    ).resolves.toEqual({
      status: "success",
      message:
        "Proposal approved. The existing Make workflow can now apply it after its own current-state checks.",
    });

    expect(mocks.requireAuthorizedUser).toHaveBeenCalledOnce();
    expect(mocks.unsafe).toHaveBeenCalledWith(
      expect.stringContaining("process_schedule_proposal_decision_for_web"),
      [
        "00000000-0000-4000-8000-000000000001",
        "Approved",
        "2026-09-04T12:00:00.000Z",
        "operator@example.invalid",
      ],
      { prepare: false },
    );
    expect(mocks.revalidatePath).toHaveBeenCalledWith("/schedule-approvals");
    expect(mocks.revalidatePath).toHaveBeenCalledWith("/dashboard");
    expect(mocks.revalidatePath).toHaveBeenCalledWith("/upcoming-posts");
  });

  it("records a rejection without claiming that Buffer changed", async () => {
    mocks.unsafe.mockResolvedValueOnce([
      {
        result_status: "Rejected",
        result_approved_at: null,
        result_rejected_at: "2026-09-04T12:01:00.000Z",
      },
    ]);

    await expect(
      saveScheduleDecision(
        initialScheduleDecisionActionState,
        decisionForm("Rejected"),
      ),
    ).resolves.toEqual({
      status: "success",
      message:
        "Proposal rejected. It will not be offered to the Make application workflow.",
    });
  });

  it("requires explicit confirmation before authorization or database access", async () => {
    const formData = decisionForm();
    formData.delete("confirm_decision");

    await expect(
      saveScheduleDecision(initialScheduleDecisionActionState, formData),
    ).resolves.toEqual({
      status: "error",
      message: "Review the proposal and confirm your decision before saving.",
    });
    expect(mocks.requireAuthorizedUser).not.toHaveBeenCalled();
    expect(mocks.unsafe).not.toHaveBeenCalled();
  });

  it("fails closed when schedule decisions are disabled", async () => {
    mocks.getServerEnvironment.mockReturnValue({
      CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED: false,
    });

    await expect(
      saveScheduleDecision(initialScheduleDecisionActionState, decisionForm()),
    ).resolves.toEqual({
      status: "error",
      message:
        "Controlled schedule decisions are disabled for this deployment.",
    });
    expect(mocks.getServerScheduleDecisionClient).not.toHaveBeenCalled();
  });

  it("does not open the database for a non-allowlisted session", async () => {
    mocks.requireAuthorizedUser.mockRejectedValue(new ForbiddenError());

    await expect(
      saveScheduleDecision(initialScheduleDecisionActionState, decisionForm()),
    ).resolves.toEqual({
      status: "error",
      message: "Your approved session is no longer available. Sign in again.",
    });
    expect(mocks.getServerScheduleDecisionClient).not.toHaveBeenCalled();
  });

  it.each([
    [
      "P4002",
      "This proposal has already moved to Google Sheets. Finish the decision there.",
    ],
    [
      "P4003",
      "This proposal is being exported to Google Sheets. Refresh in a moment.",
    ],
    [
      "P4005",
      "This proposal changed after the page loaded. Refresh and review it again.",
    ],
    [
      "P4006",
      "Approval was blocked by the latest scheduling safety check. Nothing was changed; refresh to review the current reason.",
    ],
  ])("maps %s without exposing database details", async (code, message) => {
    mocks.unsafe.mockRejectedValue(
      Object.assign(new Error("sensitive database detail"), { code }),
    );

    const result = await saveScheduleDecision(
      initialScheduleDecisionActionState,
      decisionForm(),
    );

    expect(result).toEqual({ status: "error", message });
    expect(result.message).not.toContain("sensitive database detail");
  });
});
