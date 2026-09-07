import { LogOut, ShieldCheck } from "lucide-react";
import type { ReactNode } from "react";

import { signOut } from "@/auth/actions";
import { Navigation } from "@/components/shell/navigation";
import { ThemeSelector } from "@/components/shell/theme-selector";

function Brand() {
  return (
    <div className="flex min-w-0 items-center gap-3">
      <div className="bg-accent-solid text-on-accent grid size-10 shrink-0 place-items-center rounded-xl font-black">
        CA
      </div>
      <div>
        <p className="text-foreground text-sm font-semibold tracking-tight">
          Creator Analytics
        </p>
        <p className="text-muted mt-0.5 text-xs">Your creator workspace</p>
      </div>
    </div>
  );
}

export function AppShell({
  children,
  userEmail,
  previewPath,
}: {
  children: ReactNode;
  userEmail: string;
  previewPath?: string;
}) {
  const preview = previewPath !== undefined;
  const account = (
    <>
      <div className="text-muted flex items-center gap-2 text-xs">
        <ShieldCheck aria-hidden className="text-success" size={15} />
        {preview ? "Sample account" : "Private workspace"}
      </div>
      <p className="text-secondary mt-2 truncate text-xs" title={userEmail}>
        {userEmail}
      </p>
      {!preview && (
        <form action={signOut} className="mt-3">
          <button
            className="text-muted hover:bg-surface-raised hover:text-foreground flex w-full items-center gap-2 rounded-lg px-2 py-2 text-sm transition"
            type="submit"
          >
            <LogOut aria-hidden size={15} /> Sign out
          </button>
        </form>
      )}
    </>
  );
  return (
    <div className="bg-canvas text-foreground min-h-screen">
      <a
        href="#main-content"
        className="bg-accent-solid text-on-accent sr-only z-50 rounded-lg p-3 focus:not-sr-only focus:fixed focus:top-3 focus:left-3"
      >
        Skip to content
      </a>
      <aside className="border-line bg-surface fixed inset-y-0 left-0 hidden w-60 flex-col overflow-y-auto border-r px-4 py-7 xl:flex">
        <Brand />
        <div className="mt-10">
          <Navigation previewPath={previewPath} />
        </div>
        <div className="mt-auto pt-10">
          <ThemeSelector />
          <div className="border-line mt-6 border-t pt-5">{account}</div>
        </div>
      </aside>
      <div className="xl:pl-60">
        <header className="border-line bg-surface/95 sticky top-0 z-20 border-b px-4 py-3 backdrop-blur xl:hidden">
          <div className="flex items-center justify-between gap-3">
            <Brand />
            <ThemeSelector compact />
          </div>
          <div className="mt-3">
            <Navigation compact previewPath={previewPath} />
          </div>
          <details className="text-muted mt-2 text-xs">
            <summary className="py-1">Account</summary>
            <div className="pt-3 pb-2">{account}</div>
          </details>
        </header>
        <main
          id="main-content"
          tabIndex={-1}
          className="mx-auto max-w-[100rem] px-4 py-6 outline-none sm:px-7 lg:px-9 lg:py-9"
        >
          {preview && (
            <div className="border-accent/25 bg-accent/5 text-accent mb-6 rounded-xl border px-4 py-3 text-sm">
              Design preview · Sample data. Try the themes and filters.
            </div>
          )}
          {children}
        </main>
      </div>
    </div>
  );
}
