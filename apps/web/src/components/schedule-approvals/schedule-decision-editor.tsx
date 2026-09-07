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
  const [state, formAction, pending] = useActionState(
    saveScheduleDecision,
    initialScheduleDecisionActionState,
  );

  return (
    <form
      action={formAction}
      className="mt-4 rounded-xl border border-cyan-300/15 bg-cyan-300/[0.035] p-4"
    >
      <input name="proposal_id" type="hidden" value={proposalId} />
      <input
        name="expected_updated_at"
        type="hidden"
        value={expectedUpdatedAt}
      />

      <p className="flex items-center gap-2 text-sm font-medium text-cyan-100">
        <ShieldCheck aria-hidden size={16} />
        Decide in app
      </p>
      <p className="mt-2 text-xs leading-5 text-slate-400">
        Approval records your decision in Supabase. It does not change Buffer
        directly; the existing Make workflow must still apply the schedule.
      </p>

      <label className="mt-3 flex cursor-pointer items-start gap-2 text-xs text-slate-300">
        <input
          className="mt-0.5 accent-cyan-300"
          name="confirm_decision"
          required
          type="checkbox"
        />
        I reviewed the current and proposed times and want to record the
        decision selected below.
      </label>

      <fieldset className="mt-4">
        <legend className="text-xs font-medium text-slate-300">
          Decision
        </legend>
        <div className="mt-2 grid gap-2 sm:grid-cols-2">
          <label className="flex cursor-pointer items-center gap-2 rounded-xl border border-cyan-300/20 bg-cyan-300/[0.05] px-4 py-2.5 text-sm font-semibold text-cyan-100 transition hover:bg-cyan-300/[0.1]">
            <input
              className="accent-cyan-300"
              name="decision"
              required
              type="radio"
              value="Approved"
            />
            <Check aria-hidden size={15} />
            Approve proposal
          </label>
          <label className="flex cursor-pointer items-center gap-2 rounded-xl border border-rose-300/20 bg-rose-300/[0.05] px-4 py-2.5 text-sm font-semibold text-rose-100 transition hover:bg-rose-300/[0.1]">
            <input
              className="accent-rose-300"
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
        className="mt-4 inline-flex items-center justify-center gap-2 rounded-xl bg-cyan-300 px-4 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-cyan-200 disabled:cursor-not-allowed disabled:opacity-50"
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
              ? "border-emerald-300/20 bg-emerald-300/[0.07] text-emerald-100"
              : "border-rose-300/20 bg-rose-300/[0.07] text-rose-100"
          }`}
          role={state.status === "error" ? "alert" : "status"}
        >
          {state.message}
        </p>
      )}
    </form>
  );
}
