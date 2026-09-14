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
      className={`border-line bg-surface rounded-2xl border p-5 ${className}`}
    >
      <div className="flex items-start gap-3">
        <div className="border-line bg-foreground/5 text-accent mt-0.5 rounded-xl border p-2">
          {icon}
        </div>
        <div>
          <h2 className="text-foreground font-semibold">{title}</h2>
          <div className="text-muted mt-1 text-sm leading-6">{children}</div>
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
      <div className="bg-foreground/10 h-7 w-48 animate-pulse rounded-lg" />
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {[0, 1, 2, 3].map((item) => (
          <div
            className="border-line bg-foreground/5 h-28 animate-pulse rounded-2xl border"
            key={item}
          />
        ))}
      </div>
      <div className="border-line bg-foreground/5 h-72 animate-pulse rounded-2xl border" />
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
      className="border-warning/20 bg-warning/[0.06]"
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
      className="border-warning/20 bg-warning/[0.06]"
      icon={<AlertTriangle aria-hidden size={18} />}
      title="Some sections could not be loaded"
    >
      <ul className="space-y-1">
        {errors.map((error) => (
          <li key={error.section}>
            <span className="text-secondary font-medium">{error.section}:</span>{" "}
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
        className="bg-accent-solid text-on-accent hover:bg-accent-hover mt-4 inline-flex items-center gap-2 rounded-xl px-4 py-2 font-semibold transition"
        onClick={retry}
        type="button"
      >
        <RotateCw aria-hidden size={16} />
        Try again
      </button>
    </StatePanel>
  );
}
