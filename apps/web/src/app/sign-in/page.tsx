import { Activity, ShieldCheck } from "lucide-react";
import type { Metadata } from "next";

import { SignInForm } from "@/components/auth/sign-in-form";
import { Badge } from "@/components/ui/badge";

export const metadata: Metadata = {
  title: "Sign in",
};

export default function SignInPage() {
  return (
    <main className="grid min-h-screen place-items-center px-4 py-12">
      <div className="w-full max-w-md">
        <div className="mb-7 flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="grid size-11 place-items-center rounded-xl bg-cyan-300 font-black text-slate-950">
              CA
            </div>
            <div>
              <p className="font-semibold text-white">Creator Analytics</p>
              <p className="text-xs text-slate-500">
                Private operations console
              </p>
            </div>
          </div>
          <Badge tone="info">Read only</Badge>
        </div>

        <section className="rounded-3xl border border-white/10 bg-slate-950/75 p-7 shadow-2xl shadow-black/30 backdrop-blur sm:p-9">
          <div className="flex size-11 items-center justify-center rounded-xl border border-emerald-300/20 bg-emerald-300/10 text-emerald-200">
            <ShieldCheck aria-hidden size={21} />
          </div>
          <h1 className="mt-5 text-3xl font-semibold tracking-tight text-white">
            Sign in securely
          </h1>
          <p className="mt-3 text-sm leading-6 text-slate-400">
            Use an approved email address. Public registration is disabled, and
            access is checked again before every server-side analytics query.
          </p>
          <SignInForm />
        </section>

        <div className="mt-5 flex items-center justify-center gap-2 text-xs text-slate-600">
          <Activity aria-hidden size={14} />
          Existing Supabase Auth users only
        </div>
      </div>
    </main>
  );
}
