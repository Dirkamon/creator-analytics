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
  neutral: "border-white/10 bg-white/5 text-slate-300",
  positive: "border-emerald-400/20 bg-emerald-400/10 text-emerald-200",
  warning: "border-amber-400/20 bg-amber-400/10 text-amber-200",
  danger: "border-rose-400/20 bg-rose-400/10 text-rose-200",
  info: "border-cyan-400/20 bg-cyan-400/10 text-cyan-200",
  approved: "border-blue-400/20 bg-blue-400/10 text-blue-200",
  ready: "border-cyan-300/30 bg-cyan-300/10 text-cyan-100",
  applied: "border-violet-400/20 bg-violet-400/10 text-violet-200",
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
