"use client";

import { ArrowRight, Mail } from "lucide-react";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";

import { requestMagicLink } from "@/auth/actions";
import { initialMagicLinkState } from "@/auth/magic-link-state";

function SubmitButton() {
  const { pending } = useFormStatus();

  return (
    <button
      className="flex w-full items-center justify-center gap-2 rounded-xl bg-cyan-300 px-4 py-3 font-semibold text-slate-950 transition hover:bg-cyan-200 disabled:cursor-wait disabled:opacity-70"
      disabled={pending}
      type="submit"
    >
      {pending ? "Sending secure link…" : "Send magic link"}
      {!pending && <ArrowRight aria-hidden size={17} />}
    </button>
  );
}

export function SignInForm() {
  const [state, action] = useActionState(
    requestMagicLink,
    initialMagicLinkState,
  );

  return (
    <form action={action} className="mt-8 space-y-5">
      <div>
        <label className="text-sm font-medium text-slate-200" htmlFor="email">
          Approved email address
        </label>
        <div className="relative mt-2">
          <Mail
            aria-hidden
            className="pointer-events-none absolute top-3.5 left-3.5 text-slate-500"
            size={17}
          />
          <input
            autoComplete="email"
            className="w-full rounded-xl border border-white/10 bg-slate-900/70 py-3 pr-4 pl-11 text-white transition outline-none placeholder:text-slate-600 focus:border-cyan-300/60 focus:ring-4 focus:ring-cyan-300/10"
            id="email"
            name="email"
            placeholder="Approved account email"
            required
            type="email"
          />
        </div>
      </div>
      <SubmitButton />
      {state.message && (
        <p
          aria-live="polite"
          className={`rounded-xl border px-4 py-3 text-sm leading-6 ${
            state.status === "success"
              ? "border-emerald-400/20 bg-emerald-400/10 text-emerald-100"
              : "border-rose-400/20 bg-rose-400/10 text-rose-100"
          }`}
          role={state.status === "error" ? "alert" : "status"}
        >
          {state.message}
        </p>
      )}
    </form>
  );
}
