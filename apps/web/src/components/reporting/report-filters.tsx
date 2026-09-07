"use client";

import { Filter, RotateCcw } from "lucide-react";

import type { ReportFilterValue } from "@/data/report-filters";
import { EMPTY_REPORT_FILTERS } from "@/data/report-filters";
import { DEFAULT_DISPLAY_TIMEZONE } from "@/lib/format";

export function ReportFilters({
  value,
  platforms,
  games,
  onChange,
}: {
  value: ReportFilterValue;
  platforms: readonly string[];
  games: readonly string[];
  onChange: (value: ReportFilterValue) => void;
}) {
  const update = (key: keyof ReportFilterValue, nextValue: string) =>
    onChange({ ...value, [key]: nextValue });
  const active = Object.values(value).some(Boolean);

  return (
    <section
      aria-label="Report filters"
      className="border-line bg-surface rounded-2xl border p-4"
    >
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div className="text-foreground flex items-center gap-2 text-sm font-semibold sm:col-span-2 lg:col-span-4">
          <Filter aria-hidden className="text-accent" size={17} />
          Filters
          <button
            className="text-muted hover:text-accent ml-auto inline-flex items-center gap-2 rounded-lg px-2 py-1 text-xs font-medium transition disabled:cursor-not-allowed disabled:opacity-40"
            disabled={!active}
            onClick={() => onChange(EMPTY_REPORT_FILTERS)}
            type="button"
          >
            <RotateCcw aria-hidden size={13} />
            Clear
          </button>
        </div>
        <label className="text-muted grid min-w-0 gap-1.5 text-xs font-medium">
          Platform
          <select
            className="border-line bg-canvas text-foreground focus:border-accent/60 rounded-xl border px-3 py-2.5 text-sm transition outline-none"
            onChange={(event) => update("platform", event.target.value)}
            value={value.platform}
          >
            <option value="">All platforms</option>
            {platforms.map((platform) => (
              <option key={platform} value={platform}>
                {platform}
              </option>
            ))}
          </select>
        </label>
        <label className="text-muted grid min-w-0 gap-1.5 text-xs font-medium">
          Game
          <select
            className="border-line bg-canvas text-foreground focus:border-accent/60 rounded-xl border px-3 py-2.5 text-sm transition outline-none"
            onChange={(event) => update("game", event.target.value)}
            value={value.game}
          >
            <option value="">All games</option>
            {games.map((game) => (
              <option key={game} value={game}>
                {game}
              </option>
            ))}
          </select>
        </label>
        <label className="text-muted grid min-w-0 gap-1.5 text-xs font-medium">
          From date
          <input
            className="border-line bg-canvas text-foreground focus:border-accent/60 rounded-xl border px-3 py-2 text-sm transition outline-none"
            max={value.dateTo || undefined}
            onChange={(event) => update("dateFrom", event.target.value)}
            type="date"
            value={value.dateFrom}
          />
        </label>
        <label className="text-muted grid min-w-0 gap-1.5 text-xs font-medium">
          Through date
          <input
            className="border-line bg-canvas text-foreground focus:border-accent/60 rounded-xl border px-3 py-2 text-sm transition outline-none"
            min={value.dateFrom || undefined}
            onChange={(event) => update("dateTo", event.target.value)}
            type="date"
            value={value.dateTo}
          />
        </label>
      </div>
      <p className="text-muted mt-3 text-xs">
        Dates use {DEFAULT_DISPLAY_TIMEZONE}. Leave dates blank to see all
        available posts.
      </p>
    </section>
  );
}
