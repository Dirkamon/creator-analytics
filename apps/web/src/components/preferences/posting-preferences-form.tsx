"use client";

import { startTransition, useActionState, useState } from "react";
import { PageHeader } from "@/components/ui/page-header";
import { savePostingPreferences } from "@/scheduling/preferences-actions";
import type {
  SavedPreference,
  CoverageDay,
  PreferencesActionState,
} from "@/scheduling/preferences";

const initialState: PreferencesActionState = { status: "idle", message: "" };
const names = { tiktok: "TikTok", youtube: "YouTube Shorts" };
const control =
  "border-line bg-canvas text-foreground mt-2 w-full rounded-xl border px-3 py-3 text-base";

export function PostingPreferencesForm({
  settings,
  coverage,
}: {
  settings: SavedPreference[];
  coverage: CoverageDay[];
}) {
  // Keep the draft tied to the revision the user actually reviewed. A server
  // revalidation must not silently let an older draft overwrite newer settings.
  const [revision] = useState(settings[0].revision);
  const [confirmed, setConfirmed] = useState(false);
  const [values, setValues] = useState<Record<string, string>>(() => ({
    enabled: String(settings[0].enabled),
    ...Object.fromEntries(
      settings.flatMap((setting) => [
        [`${setting.platform}_weekly`, String(setting.posts_per_week)],
        [`${setting.platform}_ceiling`, String(setting.max_posts_per_day)],
      ]),
    ),
  }));
  const [state, action, pending] = useActionState(
    savePostingPreferences.bind(null, revision),
    initialState,
  );
  const saved = state.status === "success" ? state.saved : undefined;
  function updateValue(name: string, value: string) {
    setValues((previous) => ({ ...previous, [name]: value }));
  }
  return (
    <div className="space-y-7">
      <PageHeader
        eyebrow="Your posting rhythm"
        title="Scheduling Preferences"
        description="Keep days covered, then let performance guide the extra posts."
        aside={
          <span className="border-warning/30 bg-warning/10 text-warning rounded-full border px-3 py-2 text-sm">
            Staging only ·{" "}
            {(saved?.enabled ?? settings[0].enabled) ? "Rules on" : "Rules off"}
          </span>
        }
      />
      <form
        method="post"
        onSubmit={(event) => {
          event.preventDefault();
          if (pending || state.status === "success") return;
          // Dispatch explicitly to avoid the form action's native reset, which
          // can reset even controlled selects after a save or returned error.
          const formData = new FormData(event.currentTarget);
          setConfirmed(false);
          startTransition(() => action(formData));
        }}
        className="space-y-6"
      >
        <fieldset
          disabled={pending || state.status === "success"}
          className="space-y-6 disabled:opacity-70"
        >
          <legend className="sr-only">Posting preferences</legend>
          <div className="grid gap-5 lg:grid-cols-2">
            {settings.map((setting) => (
              <section
                key={setting.platform}
                className="section-card"
                aria-labelledby={`${setting.platform}-settings-title`}
              >
                <h2
                  id={`${setting.platform}-settings-title`}
                  className="text-xl font-semibold"
                >
                  {names[setting.platform]}
                </h2>
                <div className="mt-5 grid gap-5 sm:grid-cols-2">
                  <label className="text-secondary text-sm font-medium">
                    Weekly target
                    <input
                      aria-label={`${names[setting.platform]} weekly target`}
                      name={`${setting.platform}_weekly`}
                      type="number"
                      min={7}
                      max={28}
                      step={1}
                      required
                      value={
                        saved
                          ? String(saved[`${setting.platform}_weekly`])
                          : values[`${setting.platform}_weekly`]
                      }
                      onChange={(event) =>
                        updateValue(
                          `${setting.platform}_weekly`,
                          event.currentTarget.value,
                        )
                      }
                      className={control}
                    />
                  </label>
                  <label className="text-secondary text-sm font-medium">
                    Maximum per day
                    <input
                      aria-label={`${names[setting.platform]} daily ceiling`}
                      name={`${setting.platform}_ceiling`}
                      type="number"
                      min={1}
                      max={4}
                      step={1}
                      required
                      value={
                        saved
                          ? String(saved[`${setting.platform}_ceiling`])
                          : values[`${setting.platform}_ceiling`]
                      }
                      onChange={(event) =>
                        updateValue(
                          `${setting.platform}_ceiling`,
                          event.currentTarget.value,
                        )
                      }
                      className={control}
                    />
                  </label>
                </div>
                <p className="text-muted mt-4 text-sm leading-6">
                  Aim for at least one every day. Existing spacing stays at{" "}
                  {setting.min_gap_hours} hours, with no last-minute moves
                  inside {setting.protected_hours} hours. Times use{" "}
                  {setting.timezone_name}.
                </p>
              </section>
            ))}
          </div>
          <section
            className="section-card space-y-3"
            aria-labelledby="scheduling-safety-title"
          >
            <h2 id="scheduling-safety-title" className="text-lg font-semibold">
              Your scheduling safeguards
            </h2>
            <p className="text-secondary leading-7">
              Any publishing hour is allowed, including overnight. Every
              proposed move must stay within 12 elapsed hours before or after
              the original manual Buffer time. Repeated runs cannot extend that
              limit.
            </p>
            <p className="text-muted text-sm leading-6">
              Coverage depends on labeled clips, fresh analytics, available
              slots and existing reservations. Planning keeps the current
              two-day runway. A shortage will stay visible; no clip is invented
              and no post moves without approval.
            </p>
            <label className="text-secondary block text-sm font-medium">
              Use the new rules in staging
              <select
                name="enabled"
                value={saved ? String(saved.enabled) : values.enabled}
                onChange={(event) =>
                  updateValue("enabled", event.currentTarget.value)
                }
                className={control}
              >
                <option value="false">Off — keep the existing scheduler</option>
                <option value="true">On — use for new staging proposals</option>
              </select>
            </label>
            <p className="text-muted text-sm">
              Saving changes stored targets but does not refresh proposals or
              contact Buffer. Pending and approved proposals must be resolved
              before settings can change.
            </p>
          </section>
          <label className="text-secondary flex items-start gap-3 text-sm leading-6">
            <input
              type="checkbox"
              name="confirm"
              checked={confirmed}
              onChange={(event) => setConfirmed(event.currentTarget.checked)}
              required
              className="accent-accent mt-1 size-4"
            />
            I reviewed these staging settings. I understand that each schedule
            change still needs approval.
          </label>
          <button
            type="submit"
            className="bg-accent-solid text-on-accent rounded-xl px-5 py-3 font-semibold"
          >
            {pending ? "Saving…" : "Save staging preferences"}
          </button>
        </fieldset>
        {state.message && (
          <p
            role={state.status === "error" ? "alert" : "status"}
            className="text-secondary border-line rounded-xl border p-4"
          >
            {state.message}
            {state.status === "success" && (
              <>
                {" "}
                <a
                  href="/scheduling-preferences"
                  className="text-accent underline"
                >
                  Reload saved settings
                </a>
              </>
            )}
          </p>
        )}
      </form>
      <section className="section-card" aria-labelledby="coverage-title">
        <h2 id="coverage-title" className="text-xl font-semibold">
          Day-by-day coverage
        </h2>
        <p className="text-muted mt-2 text-sm leading-6">
          Synchronized counts are the last database observation, not a live
          Buffer check. Planned counts include pending or approved moves and
          applied moves awaiting sync. They are not guaranteed. This table does
          not preview unsaved edits.
        </p>
        <div className="mt-5 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-muted">
              <tr>
                {[
                  "Date",
                  "Platform / channel",
                  "Synchronized",
                  "Planned",
                  "Coverage",
                ].map((heading) => (
                  <th
                    className="border-line border-b px-3 py-3 font-medium"
                    key={heading}
                  >
                    {heading}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {coverage.map((day) => (
                <tr key={`${day.buffer_channel_id}-${day.local_date}`}>
                  <td className="border-line border-b px-3 py-3 whitespace-nowrap">
                    {day.local_date}
                    <span className="text-muted block text-xs">
                      {day.timezone_name}
                    </span>
                  </td>
                  <td className="border-line border-b px-3 py-3">
                    {names[day.platform]}
                    <span className="text-muted block max-w-48 truncate text-xs">
                      {day.buffer_channel_id}
                    </span>
                  </td>
                  <td className="border-line border-b px-3 py-3">
                    {day.scheduled_count}
                  </td>
                  <td className="border-line border-b px-3 py-3">
                    {day.planned_count}
                  </td>
                  <td className="border-line border-b px-3 py-3">
                    <span
                      className={
                        day.planned_count ? "text-success" : "text-warning"
                      }
                    >
                      {day.planned_count
                        ? "At least one planned"
                        : "Gap to fill"}
                    </span>
                    {day.coverage_note && (
                      <p className="text-muted mt-1 max-w-lg text-xs leading-5">
                        {day.coverage_note}
                      </p>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
