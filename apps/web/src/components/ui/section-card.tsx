import type { ReactNode } from "react";

export function SectionCard({
  title,
  description,
  children,
  className = "",
}: {
  title: string;
  description?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section
      className={`rounded-2xl border border-white/10 bg-slate-950/55 p-5 shadow-xl shadow-black/10 sm:p-6 ${className}`}
    >
      <div>
        <h2 className="font-semibold tracking-tight text-white">{title}</h2>
        {description && (
          <p className="mt-1 text-xs leading-5 text-slate-500">{description}</p>
        )}
      </div>
      <div className="mt-5">{children}</div>
    </section>
  );
}
