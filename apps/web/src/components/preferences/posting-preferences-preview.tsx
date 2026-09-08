"use client";

import { CalendarCheck2, RotateCcw, ShieldCheck } from "lucide-react";
import { useState } from "react";

import { PageHeader } from "@/components/ui/page-header";
import {
  illustratePostingWeek,
  initialPostingPreference,
  previewDays,
  validatePostingPreference,
  type PostingPreferenceDraft,
} from "@/scheduling/preferences-preview";

const platforms = [
  { id: "tiktok", name: "TikTok", order: [1, 4, 3, 2, 5, 6, 0] },
  { id: "youtube", name: "YouTube Shorts", order: [5, 3, 0, 4, 1, 2, 6] },
] as const;

const control =
  "border-line bg-canvas text-foreground mt-2 w-full rounded-xl border px-3 py-3 text-base";

export function PostingPreferencesPreview() {
  const [drafts, setDrafts] = useState<Record<string, PostingPreferenceDraft>>({
    tiktok: { ...initialPostingPreference },
    youtube: { ...initialPostingPreference },
  });
  const [availableClips, setAvailableClips] = useState(14);
  const [resetNotice, setResetNotice] = useState("");
  const results = platforms.map((platform) => {
    const draft = drafts[platform.id];
    const error = validatePostingPreference(draft);
    return {
      ...platform,
      draft,
      error,
      week: error
        ? null
        : illustratePostingWeek(draft, availableClips, platform.order),
    };
  });

  function update(
    platform: string,
    field: keyof PostingPreferenceDraft,
    value: number,
  ) {
    setDrafts((current) => ({
      ...current,
      [platform]: { ...current[platform], [field]: value },
    }));
    setResetNotice("");
  }

  return (
    <div className="space-y-7">
      <PageHeader
        eyebrow="Your posting rhythm"
        title="Scheduling Preferences"
        description="Keep every day covered. Give the extra posts to stronger days."
        aside={
          <span className="border-warning/30 bg-warning/10 text-warning rounded-full border px-3 py-2 text-sm font-medium">
            Local draft · Not active
          </span>
        }
      />

      <div className="border-accent/25 bg-accent/5 flex gap-3 rounded-2xl border p-5">
        <CalendarCheck2
          aria-hidden
          className="text-accent mt-0.5 shrink-0"
          size={22}
        />
        <div>
          <h2 className="text-foreground text-base font-semibold">
            Daily coverage comes first
          </h2>
          <p className="text-secondary mt-1 text-base leading-7">
            Reserve at least one post every day on each platform, then use
            analytics to place the remaining posts within your daily ceiling.
          </p>
          <p className="text-muted mt-2 text-sm leading-6">
            This needs enough labeled clips and safe, eligible posting slots. If
            either runs short, flag the gap instead of crowding another day or
            bypassing safeguards.
          </p>
        </div>
      </div>

      <div className="grid gap-5 lg:grid-cols-2">
        {results.map(({ id, name, draft, error }) => (
          <section
            key={id}
            aria-labelledby={`${id}-title`}
            className="section-card"
          >
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h2 id={`${id}-title`} className="text-xl font-semibold">
                {name}
              </h2>
              <span className="text-muted text-sm">
                One platform post per clip
              </span>
            </div>
            <div className="mt-6 grid gap-5 sm:grid-cols-2">
              <label className="text-secondary text-sm font-medium">
                Weekly target
                <input
                  aria-label={`${name} weekly target`}
                  aria-describedby={`${id}-help ${id}-error`}
                  aria-invalid={Boolean(error)}
                  className={control}
                  type="number"
                  min={7}
                  max={28}
                  step={1}
                  value={
                    Number.isNaN(draft.weeklyTarget) ? "" : draft.weeklyTarget
                  }
                  onChange={(event) =>
                    update(
                      id,
                      "weeklyTarget",
                      event.target.value === ""
                        ? NaN
                        : Number(event.target.value),
                    )
                  }
                />
              </label>
              <label className="text-secondary text-sm font-medium">
                Daily ceiling
                <select
                  aria-label={`${name} daily ceiling`}
                  aria-describedby={`${id}-help ${id}-error`}
                  className={control}
                  value={draft.dailyCeiling}
                  onChange={(event) =>
                    update(id, "dailyCeiling", Number(event.target.value))
                  }
                >
                  {[1, 2, 3, 4].map((count) => (
                    <option key={count} value={count}>
                      {count} {count === 1 ? "post" : "posts"}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            <p id={`${id}-help`} className="text-muted mt-4 text-sm leading-6">
              {error
                ? "Adjust the values to preview this platform."
                : `${draft.weeklyTarget} per week averages ${(draft.weeklyTarget / 7).toLocaleString("en-US", { maximumFractionDigits: 1 })} per day. Daily floor: 1. The ceiling is a limit, not a daily target.`}
            </p>
            <p
              id={`${id}-error`}
              role={error ? "alert" : undefined}
              className="text-danger mt-2 text-sm"
            >
              {error}
            </p>
          </section>
        ))}
      </div>

      <section className="section-card" aria-labelledby="posting-times-title">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 id="posting-times-title" className="text-xl font-semibold">
            Posting times
          </h2>
          <span className="text-secondary text-sm">
            Any hour · America/Denver
          </span>
        </div>
        <p className="text-secondary mt-3 text-base leading-7">
          All 24 hours are allowed, including overnight. Let analytics rank the
          suggested posting times for each platform, with no preferred time
          window.
        </p>
        <p className="text-muted mt-2 text-sm leading-6">
          Daily coverage and spacing still come first. Recommendations need
          supporting data; no time guarantees better performance. This is your
          draft preference, not a change to live posting rules.
        </p>
      </section>

      <section
        className="section-card"
        aria-labelledby="rescheduling-limit-title"
      >
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 id="rescheduling-limit-title" className="text-xl font-semibold">
            Rescheduling limit
          </h2>
          <span className="text-secondary text-sm">
            Up to 12 hours earlier or later
          </span>
        </div>
        <p className="text-secondary mt-3 text-base leading-7">
          Measure each proposal from the time you set in Buffer. A post
          scheduled for Wednesday at 6 PM could be proposed between Wednesday at
          6 AM and Thursday at 6 AM. Repeated proposals must not keep extending
          that window.
        </p>
        <p className="text-muted mt-2 text-sm leading-6">
          If daily coverage cannot be met within this limit and the other safety
          rules, flag the gap instead of moving a post farther. Nothing moves
          without your approval.
        </p>
      </section>

      <section className="section-card" aria-labelledby="example-title">
        <div className="flex flex-col gap-5 md:flex-row md:items-start md:justify-between">
          <div>
            <h2 id="example-title" className="text-xl font-semibold">
              Try an example week
            </h2>
            <p className="text-muted mt-2 max-w-2xl text-sm leading-6">
              Illustration only—not your current queue or an analytics forecast.
              The example assumes eligible slots are available within each
              post’s 12-hour movement limit; it does not check actual Buffer
              times. Each example clip is posted once to both platforms.
            </p>
          </div>
          <label className="text-secondary shrink-0 text-sm font-medium">
            Example clips available
            <select
              aria-label="Example clips available"
              className={control}
              value={availableClips}
              onChange={(event) =>
                setAvailableClips(Number(event.target.value))
              }
            >
              {[0, 4, 6, 7, 10, 14, 21, 28].map((count) => (
                <option key={count} value={count}>
                  {count} clips · {count * 2} platform posts
                </option>
              ))}
            </select>
          </label>
        </div>

        <div className="border-line mt-6 overflow-x-auto rounded-xl border">
          <table
            className="w-full min-w-[42rem] text-left text-sm"
            aria-label="Illustrative weekly post counts"
          >
            <thead className="bg-surface-raised text-muted">
              <tr>
                <th scope="col" className="px-4 py-4 font-medium">
                  Platform
                </th>
                {previewDays.map((day) => (
                  <th
                    key={day}
                    scope="col"
                    className="px-3 py-4 text-center font-medium"
                  >
                    {day}
                  </th>
                ))}
                <th scope="col" className="px-4 py-4 text-right font-medium">
                  Total
                </th>
              </tr>
            </thead>
            <tbody>
              {results.map(({ id, name, week }) => (
                <tr key={id} className="border-line border-t">
                  <th scope="row" className="px-4 py-5 font-medium">
                    {name}
                  </th>
                  {previewDays.map((day, index) => (
                    <td key={day} className="px-3 py-5 text-center">
                      <span
                        className={`inline-flex size-9 items-center justify-center rounded-lg text-base font-semibold ${!week ? "text-muted" : week.counts[index] === 0 ? "bg-warning/10 text-warning" : week.counts[index] === 1 ? "bg-surface-raised text-secondary" : "bg-accent/15 text-accent"}`}
                      >
                        {week ? week.counts[index] : "—"}
                      </span>
                    </td>
                  ))}
                  <td className="px-4 py-5 text-right text-base font-semibold">
                    {week ? week.planned : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div aria-live="polite" className="mt-5 grid gap-3 md:grid-cols-2">
          {results.map(({ id, name, week }) => (
            <div
              key={id}
              className="bg-canvas rounded-xl px-4 py-3 text-sm leading-6"
            >
              <p className="font-medium">{name}</p>
              {!week ? (
                <p className="text-danger">
                  Correct the settings above to see an example.
                </p>
              ) : (
                <>
                  <p
                    className={
                      week.uncoveredDays ? "text-warning" : "text-success"
                    }
                  >
                    {week.uncoveredDays
                      ? `${week.uncoveredDays} uncovered days: more clips are needed before adding extra daily posts.`
                      : "All 7 days covered in this example."}
                  </p>
                  {week.targetShortfall > 0 && (
                    <p className="text-muted">
                      {week.targetShortfall} more clips needed to reach the
                      weekly target.
                    </p>
                  )}
                  {week.unusedClips > 0 && (
                    <p className="text-muted">
                      {week.unusedClips} clips left outside this example week.
                      They are not forced into extra slots.
                    </p>
                  )}
                </>
              )}
            </div>
          ))}
        </div>
      </section>

      <div className="flex flex-col gap-5 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex max-w-3xl gap-3">
          <ShieldCheck
            aria-hidden
            className="text-success mt-1 shrink-0"
            size={20}
          />
          <div className="text-muted text-sm leading-6">
            <p className="text-secondary font-medium">
              Your approval step stays in place.
            </p>
            <p>
              No settings are saved to the scheduler here. Changes last only
              while this preview is open. Existing posts, spacing rules,
              protected posting times, and Buffer schedules are untouched.
            </p>
            <p className="mt-2">
              These draft preferences still need to be connected to the
              scheduler and tested in staging before rollout.
            </p>
          </div>
        </div>
        <button
          type="button"
          className="border-line text-secondary hover:bg-surface-raised flex shrink-0 items-center justify-center gap-2 rounded-xl border px-4 py-3 text-sm font-medium"
          onClick={() => {
            setDrafts({
              tiktok: { ...initialPostingPreference },
              youtube: { ...initialPostingPreference },
            });
            setAvailableClips(14);
            setResetNotice(
              "Draft reset to 14 per week, at least 1 per day, and a daily ceiling of 3 on each platform.",
            );
          }}
        >
          <RotateCcw aria-hidden size={16} /> Reset example
        </button>
      </div>
      <p role="status" className="text-muted text-sm">
        {resetNotice}
      </p>
    </div>
  );
}
