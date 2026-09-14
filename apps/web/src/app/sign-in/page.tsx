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
            <div className="bg-accent-solid text-on-accent grid size-11 place-items-center rounded-xl font-black">
              CA
            </div>
            <div>
              <p className="text-foreground font-semibold">Creator Analytics</p>
              <p className="text-muted text-xs">Your creator workspace</p>
            </div>
          </div>
          <Badge tone="info">Private</Badge>
        </div>

        <section className="border-line bg-canvas/75 rounded-3xl border p-7 shadow-2xl shadow-black/30 backdrop-blur sm:p-9">
          <div className="border-success/20 bg-success/10 text-success flex size-11 items-center justify-center rounded-xl border">
            <ShieldCheck aria-hidden size={21} />
          </div>
          <h1 className="text-foreground mt-5 text-3xl font-semibold tracking-tight">
            Sign in securely
          </h1>
          <p className="text-muted mt-3 text-sm leading-6">
            Enter your approved email to receive a sign-in link. Public
            registration is disabled.
          </p>
          <SignInForm />
        </section>

        <div className="text-muted mt-5 flex items-center justify-center gap-2 text-xs">
          <Activity aria-hidden size={14} />
          Access is by invitation
        </div>
      </div>
    </main>
  );
}
