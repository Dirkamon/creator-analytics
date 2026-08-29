import {
  AlertTriangle,
  Clock3,
  Inbox,
  LockKeyhole,
  RotateCw,
} from "lucide-react";
import type { ReactNode } from "react";

function StatePanel({
  icon,
  title,
  children,
  className = "",
}: {
  icon: ReactNode;
  title: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section
      className={`rounded-2xl border border-white/10 bg-slate-950/55 p-5 ${className}`}
    >
      <div className="flex items-start gap-3">
        <div className="mt-0.5 rounded-xl border border-white/10 bg-white/5 p-2 text-cyan-200">
          {icon}
        </div>
        <div>
          <h2 className="font-semibold text-white">{title}</h2>
          <div className="mt-1 text-sm leading-6 text-slate-400">
            {children}
          </div>
        </div>
      </div>
    </section>
  );
}

export function LoadingState({
  label = "Loading analytics",
}: {
  label?: string;
}) {
  return (
    <div aria-label={label} aria-live="polite" className="space-y-4">
      <div className="h-7 w-48 animate-pulse rounded-lg bg-white/10" />
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {[0, 1, 2, 3].map((item) => (
          <div
            className="h-28 animate-pulse rounded-2xl border border-white/5 bg-white/5"
            key={item}
          />
        ))}
      </div>
      <div className="h-72 animate-pulse rounded-2xl border border-white/5 bg-white/5" />
    </div>
  );
}

export function EmptyState({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <StatePanel icon={<Inbox aria-hidden size={18} />} title={title}>
      {children}
    </StatePanel>
  );
}

export function StaleNotice({
  title = "This data may be stale",
  children,
}: {
  title?: string;
  children: ReactNode;
}) {
  return (
    <StatePanel
      className="border-amber-400/20 bg-amber-400/[0.06]"
      icon={<Clock3 aria-hidden size={18} />}
      title={title}
    >
      {children}
    </StatePanel>
  );
}

export function PartialErrorState({
  errors,
}: {
  errors: readonly { section: string; message: string }[];
}) {
  if (errors.length === 0) return null;

  return (
    <StatePanel
      className="border-amber-400/20 bg-amber-400/[0.06]"
      icon={<AlertTriangle aria-hidden size={18} />}
      title="Some sections could not be loaded"
    >
      <ul className="space-y-1">
        {errors.map((error) => (
          <li key={error.section}>
            <span className="font-medium text-slate-200">{error.section}:</span>{" "}
            {error.message}
          </li>
        ))}
      </ul>
    </StatePanel>
  );
}

export function PermissionErrorState({
  title = "Private access required",
  children,
}: {
  title?: string;
  children: ReactNode;
}) {
  return (
    <StatePanel icon={<LockKeyhole aria-hidden size={18} />} title={title}>
      {children}
    </StatePanel>
  );
}

export function UnexpectedErrorState({ retry }: { retry: () => void }) {
  return (
    <StatePanel
      icon={<AlertTriangle aria-hidden size={18} />}
      title="This page could not be loaded"
    >
      <p>
        No changes were made. Retry the read-only request when you are ready.
      </p>
      <button
        className="mt-4 inline-flex items-center gap-2 rounded-xl bg-cyan-300 px-4 py-2 font-semibold text-slate-950 transition hover:bg-cyan-200"
        onClick={retry}
        type="button"
      >
        <RotateCw aria-hidden size={16} />
        Try again
      </button>
    </StatePanel>
  );
}
