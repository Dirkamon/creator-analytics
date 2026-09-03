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
      className="rounded-2xl border border-white/10 bg-slate-950/55 p-4"
    >
      <div className="flex flex-col gap-4 xl:flex-row xl:items-end">
        <div className="flex items-center gap-2 pb-1 text-sm font-semibold text-white xl:mr-2">
          <Filter aria-hidden className="text-cyan-300" size={17} />
          Filters
        </div>
        <label className="grid min-w-44 flex-1 gap-1.5 text-xs font-medium text-slate-400">
          Platform
          <select
            className="rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white transition outline-none focus:border-cyan-300/60"
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
        <label className="grid min-w-44 flex-1 gap-1.5 text-xs font-medium text-slate-400">
          Game
          <select
            className="rounded-xl border border-white/10 bg-slate-950 px-3 py-2.5 text-sm text-white transition outline-none focus:border-cyan-300/60"
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
        <label className="grid min-w-40 flex-1 gap-1.5 text-xs font-medium text-slate-400">
          From date
          <input
            className="rounded-xl border border-white/10 bg-slate-950 px-3 py-2 text-sm text-white transition outline-none focus:border-cyan-300/60"
            max={value.dateTo || undefined}
            onChange={(event) => update("dateFrom", event.target.value)}
            type="date"
            value={value.dateFrom}
          />
        </label>
        <label className="grid min-w-40 flex-1 gap-1.5 text-xs font-medium text-slate-400">
          Through date
          <input
            className="rounded-xl border border-white/10 bg-slate-950 px-3 py-2 text-sm text-white transition outline-none focus:border-cyan-300/60"
            min={value.dateFrom || undefined}
            onChange={(event) => update("dateTo", event.target.value)}
            type="date"
            value={value.dateTo}
          />
        </label>
        <button
          className="inline-flex items-center justify-center gap-2 rounded-xl border border-white/10 px-4 py-2.5 text-sm font-medium text-slate-300 transition hover:border-cyan-300/30 hover:text-white disabled:cursor-not-allowed disabled:opacity-40"
          disabled={!active}
          onClick={() => onChange(EMPTY_REPORT_FILTERS)}
          type="button"
        >
          <RotateCcw aria-hidden size={15} />
          Clear
        </button>
      </div>
      <p className="mt-3 text-xs text-slate-600">
        Date boundaries use {DEFAULT_DISPLAY_TIMEZONE}.
      </p>
    </section>
  );
}
