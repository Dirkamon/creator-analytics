import type { ReactNode } from "react";

type Tone =
  | "neutral"
  | "positive"
  | "warning"
  | "danger"
  | "info"
  | "approved"
  | "ready"
  | "applied";

const toneClasses: Record<Tone, string> = {
  neutral: "border-line bg-foreground/5 text-secondary",
  positive: "border-success/20 bg-success/10 text-success",
  warning: "border-warning/20 bg-warning/10 text-warning",
  danger: "border-danger/20 bg-danger/10 text-danger",
  info: "border-accent/20 bg-accent/10 text-accent",
  approved: "border-info/20 bg-info/10 text-info",
  ready: "border-accent/30 bg-accent/10 text-accent",
  applied: "border-applied/20 bg-applied/10 text-applied",
};

export function Badge({
  children,
  tone = "neutral",
}: {
  children: ReactNode;
  tone?: Tone;
}) {
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-1 text-[0.68rem] font-semibold tracking-[0.08em] uppercase ${toneClasses[tone]}`}
    >
      {children}
    </span>
  );
}
