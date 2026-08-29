import { LogOut, ShieldCheck } from "lucide-react";
import type { ReactNode } from "react";

import { signOut } from "@/auth/actions";
import { Navigation } from "@/components/shell/navigation";
import { Badge } from "@/components/ui/badge";

function Brand() {
  return (
    <div className="flex items-center gap-3">
      <div className="grid size-10 place-items-center rounded-xl bg-cyan-300 font-black text-slate-950 shadow-[0_10px_32px_rgba(103,232,249,0.2)]">
        CA
      </div>
      <div>
        <p className="font-semibold tracking-tight text-white">
          Creator Analytics
        </p>
        <p className="text-xs text-slate-500">Operations console</p>
      </div>
    </div>
  );
}

export function AppShell({
  children,
  userEmail,
}: {
  children: ReactNode;
  userEmail: string;
}) {
  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      <aside className="fixed inset-y-0 left-0 hidden w-64 border-r border-white/10 bg-slate-950/95 px-5 py-6 backdrop-blur xl:flex xl:flex-col">
        <Brand />
        <div className="mt-9">
          <Badge tone="info">Phase 1 · read only</Badge>
        </div>
        <div className="mt-7">
          <Navigation />
        </div>
        <div className="mt-auto border-t border-white/10 pt-5">
          <div className="flex items-center gap-2 text-xs text-slate-500">
            <ShieldCheck aria-hidden className="text-emerald-300" size={15} />
            Allowlisted session
          </div>
          <p className="mt-2 truncate text-sm text-slate-300" title={userEmail}>
            {userEmail}
          </p>
          <form action={signOut} className="mt-3">
            <button
              className="flex w-full items-center gap-2 rounded-xl border border-white/10 px-3 py-2 text-sm text-slate-300 transition hover:border-white/20 hover:bg-white/5 hover:text-white"
              type="submit"
            >
              <LogOut aria-hidden size={15} />
              Sign out
            </button>
          </form>
        </div>
      </aside>

      <div className="xl:pl-64">
        <header className="sticky top-0 z-20 border-b border-white/10 bg-slate-950/90 px-4 py-3 backdrop-blur xl:hidden">
          <div className="mx-auto flex max-w-7xl items-center justify-between gap-4">
            <Brand />
            <Badge tone="info">Read only</Badge>
          </div>
          <div className="mx-auto mt-3 max-w-7xl">
            <Navigation compact />
          </div>
        </header>
        <main className="mx-auto max-w-[96rem] px-4 py-7 sm:px-6 lg:px-10 lg:py-10">
          {children}
        </main>
      </div>
    </div>
  );
}
