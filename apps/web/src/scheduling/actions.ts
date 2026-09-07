"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { requireAuthorizedUser } from "@/auth/authorization.server";
import { isAuthorizationError } from "@/auth/errors";
import { getServerEnvironment } from "@/config/env-server";
import { ConfigurationError } from "@/config/errors";
import { getServerScheduleDecisionClient } from "@/lib/database/server-data";
import type { ScheduleDecisionActionState } from "@/scheduling/state";

const scheduleDecisionSchema = z.object({
  proposal_id: z.string().uuid(),
  expected_updated_at: z.iso.datetime({ offset: true }),
  decision: z.enum(["Approved", "Rejected"]),
  confirm_decision: z.literal("on"),
});

type ScheduleDecisionDatabaseResult = {
  result_status: "Approved" | "Rejected";
  result_approved_at: string | null;
  result_rejected_at: string | null;
};

function databaseErrorCode(error: unknown): string | null {
  if (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    typeof error.code === "string"
  ) {
    return error.code;
  }
  return null;
}

function databaseFailureMessage(error: unknown): string {
  switch (databaseErrorCode(error)) {
    case "P4001":
      return "This proposal already has a decision. Refresh to see its current state.";
    case "P4002":
      return "This proposal has already moved to Google Sheets. Finish the decision there.";
    case "P4003":
      return "This proposal is being exported to Google Sheets. Refresh in a moment.";
    case "P4004":
      return "This proposal is no longer available. Refresh the page.";
    case "P4005":
      return "This proposal changed after the page loaded. Refresh and review it again.";
    case "P4006":
      return "Approval was blocked by the latest scheduling safety check. Nothing was changed; refresh to review the current reason.";
    case "22023":
      return "The submitted decision is no longer valid. Refresh and try again.";
    default:
      return "The decision could not be saved. Nothing was partially applied; refresh and try again.";
  }
}

export async function saveScheduleDecision(
  proposalId: string,
  expectedUpdatedAt: string,
  _previousState: ScheduleDecisionActionState,
  formData: FormData,
): Promise<ScheduleDecisionActionState> {
  const parsed = scheduleDecisionSchema.safeParse({
    proposal_id: proposalId,
    expected_updated_at: expectedUpdatedAt,
    decision: formData.get("decision"),
    confirm_decision: formData.get("confirm_decision"),
  });

  if (!parsed.success) {
    return {
      status: "error",
      message: "Review the proposal and confirm your decision before saving.",
    };
  }

  try {
    const authorizedUser = await requireAuthorizedUser();
    const environment = getServerEnvironment();

    if (!environment.CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED) {
      return {
        status: "error",
        message:
          "Controlled schedule decisions are disabled for this deployment.",
      };
    }

    const database = getServerScheduleDecisionClient();
    const result = await database.begin(async (transaction) => {
      const rows = await transaction.unsafe(
        [
          "select result_status, result_approved_at, result_rejected_at",
          "from public.process_schedule_proposal_decision_for_web(",
          "$1::uuid, $2::text, $3::timestamptz, $4::text",
          ")",
        ].join(" "),
        [
          parsed.data.proposal_id,
          parsed.data.decision,
          parsed.data.expected_updated_at,
          authorizedUser.email,
        ],
        { prepare: false },
      );

      return rows[0] as unknown as ScheduleDecisionDatabaseResult | undefined;
    });

    if (!result || result.result_status !== parsed.data.decision) {
      throw new Error("The schedule decision function returned no result.");
    }

    revalidatePath("/schedule-approvals");
    revalidatePath("/dashboard");
    revalidatePath("/upcoming-posts");

    return {
      status: "success",
      message:
        result.result_status === "Approved"
          ? "Proposal approved. The existing Make workflow can now apply it after its own current-state checks."
          : "Proposal rejected. It will not be offered to the Make application workflow.",
    };
  } catch (error) {
    if (isAuthorizationError(error)) {
      return {
        status: "error",
        message: "Your approved session is no longer available. Sign in again.",
      };
    }

    if (error instanceof ConfigurationError) {
      return {
        status: "error",
        message:
          "Controlled schedule decisions are not configured for this deployment.",
      };
    }

    return { status: "error", message: databaseFailureMessage(error) };
  }
}
