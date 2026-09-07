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
      className="bg-accent-solid text-on-accent hover:bg-accent-hover flex w-full items-center justify-center gap-2 rounded-xl px-4 py-3 font-semibold transition disabled:cursor-wait disabled:opacity-70"
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
        <label className="text-secondary text-sm font-medium" htmlFor="email">
          Approved email address
        </label>
        <div className="relative mt-2">
          <Mail
            aria-hidden
            className="text-muted pointer-events-none absolute top-3.5 left-3.5"
            size={17}
          />
          <input
            autoComplete="email"
            className="border-line bg-surface-raised text-foreground placeholder:text-muted focus:border-accent/60 focus:ring-accent/10 w-full rounded-xl border py-3 pr-4 pl-11 transition outline-none focus:ring-4"
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
              ? "border-success/20 bg-success/10 text-success"
              : "border-danger/20 bg-danger/10 text-danger"
          }`}
          role={state.status === "error" ? "alert" : "status"}
        >
          {state.message}
        </p>
      )}
    </form>
  );
}
