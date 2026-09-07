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
    <section className={`section-card ${className}`}>
      <div>
        <h2 className="text-foreground font-semibold tracking-tight">
          {title}
        </h2>
        {description && (
          <p className="text-muted mt-1 text-xs leading-5">{description}</p>
        )}
      </div>
      <div className="mt-5">{children}</div>
    </section>
  );
}
