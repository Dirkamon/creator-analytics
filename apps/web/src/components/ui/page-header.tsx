import type { ReactNode } from "react";

export function PageHeader({
  eyebrow,
  title,
  description,
  aside,
}: {
  eyebrow: string;
  title: string;
  description: string;
  aside?: ReactNode;
}) {
  return (
    <header className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
      <div className="max-w-3xl">
        <p className="text-accent text-xs font-semibold tracking-[0.2em] uppercase">
          {eyebrow}
        </p>
        <h1 className="text-foreground mt-3 text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">
          {title}
        </h1>
        <p className="text-muted mt-3 max-w-2xl text-sm leading-6 sm:text-base">
          {description}
        </p>
      </div>
      {aside && <div className="shrink-0">{aside}</div>}
    </header>
  );
}
