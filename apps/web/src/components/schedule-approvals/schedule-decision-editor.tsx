"use client";

import { useActionState } from "react";
import { Check, ShieldCheck, X } from "lucide-react";

import { saveScheduleDecision } from "@/scheduling/actions";
import { initialScheduleDecisionActionState } from "@/scheduling/state";

export function ScheduleDecisionEditor({
  proposalId,
  expectedUpdatedAt,
}: {
  proposalId: string;
  expectedUpdatedAt: string;
}) {
  const saveDecision = saveScheduleDecision.bind(
    null,
    proposalId,
    expectedUpdatedAt,
  );
  const [state, formAction, pending] = useActionState(
    saveDecision,
    initialScheduleDecisionActionState,
  );

  return (
    <form
      action={formAction}
      className="border-accent/15 bg-accent/[0.035] mt-4 rounded-xl border p-4"
    >
      <p className="text-accent flex items-center gap-2 text-sm font-medium">
        <ShieldCheck aria-hidden size={16} />
        Decide in app
      </p>
      <p className="text-muted mt-2 text-xs leading-5">
        Approval records your decision in Supabase. It does not change Buffer
        directly; the existing Make workflow must still apply the schedule.
      </p>

      <label className="text-secondary mt-3 flex cursor-pointer items-start gap-2 text-xs">
        <input
          className="accent-accent mt-0.5"
          name="confirm_decision"
          required
          type="checkbox"
        />
        I reviewed the current and proposed times and want to record the
        decision selected below.
      </label>

      <fieldset className="mt-4">
        <legend className="text-secondary text-xs font-medium">Decision</legend>
        <div className="mt-2 grid gap-2 sm:grid-cols-2">
          <label className="border-accent/20 bg-accent/[0.05] text-accent hover:bg-accent/[0.1] flex cursor-pointer items-center gap-2 rounded-xl border px-4 py-2.5 text-sm font-semibold transition">
            <input
              className="accent-accent"
              name="decision"
              required
              type="radio"
              value="Approved"
            />
            <Check aria-hidden size={15} />
            Approve proposal
          </label>
          <label className="border-danger/20 bg-danger/[0.05] text-danger hover:bg-danger/[0.1] flex cursor-pointer items-center gap-2 rounded-xl border px-4 py-2.5 text-sm font-semibold transition">
            <input
              className="accent-danger"
              name="decision"
              required
              type="radio"
              value="Rejected"
            />
            <X aria-hidden size={15} />
            Reject proposal
          </label>
        </div>
      </fieldset>

      <button
        className="bg-accent-solid text-on-accent hover:bg-accent-hover mt-4 inline-flex items-center justify-center gap-2 rounded-xl px-4 py-2.5 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-50"
        disabled={pending}
        type="submit"
      >
        <Check aria-hidden size={15} />
        {pending ? "Saving…" : "Save decision"}
      </button>

      {state.status !== "idle" && (
        <p
          aria-live="polite"
          className={`mt-3 rounded-xl border px-3 py-2.5 text-sm ${
            state.status === "success"
              ? "border-success/20 bg-success/[0.07] text-success"
              : "border-danger/20 bg-danger/[0.07] text-danger"
          }`}
          role={state.status === "error" ? "alert" : "status"}
        >
          {state.message}
        </p>
      )}
    </form>
  );
}
