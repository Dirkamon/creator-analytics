"use client";

import { useActionState, useState } from "react";
import { Layers3, Save, Sheet, Tags } from "lucide-react";

import { saveContentLabel } from "@/labeling/actions";
import {
  labelContentTypes,
  labelEditingIntensities,
  labelGames,
  labelHookTypes,
  labelVibes,
} from "@/labeling/options";
import { initialLabelingActionState } from "@/labeling/state";

type ExistingClipGroup = {
  name: string;
  game: string | null;
  contentType: string | null;
  vibe: string | null;
  platforms: string[];
  postCount: number;
};

const fieldClassName =
  "mt-1.5 w-full rounded-xl border border-white/10 bg-slate-950/80 px-3 py-2.5 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-cyan-300/40 focus:ring-2 focus:ring-cyan-300/10";

function SelectField({
  label,
  name,
  options,
  required = false,
}: {
  label: string;
  name: string;
  options: readonly string[];
  required?: boolean;
}) {
  return (
    <label className="text-xs font-medium text-slate-300">
      {label}
      {required ? " *" : ""}
      <select className={fieldClassName} name={name} required={required}>
        <option value="">{required ? "Choose one" : "Not specified"}</option>
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
    </label>
  );
}

export function LabelEditor({
  bufferPostId,
  clipGroups,
}: {
  bufferPostId: string;
  clipGroups: ExistingClipGroup[];
}) {
  const [mode, setMode] = useState<"create" | "link_existing">("create");
  const [selectedGroupName, setSelectedGroupName] = useState("");
  const [state, formAction, pending] = useActionState(
    saveContentLabel,
    initialLabelingActionState,
  );
  const selectedGroup = clipGroups.find(
    (group) => group.name === selectedGroupName,
  );

  return (
    <details className="mt-4 rounded-xl border border-cyan-300/15 bg-cyan-300/[0.035] p-3 open:bg-slate-950/60">
      <summary className="cursor-pointer list-none text-sm font-medium text-cyan-100 marker:hidden">
        <span className="inline-flex items-center gap-2">
          <Tags aria-hidden size={15} />
          Label in app
        </span>
      </summary>

      <form action={formAction} className="mt-4 space-y-4">
        <input name="post_id" type="hidden" value={bufferPostId} />
        <input name="mode" type="hidden" value={mode} />

        <fieldset>
          <legend className="text-xs font-medium text-slate-300">
            Clip Group choice
          </legend>
          <div className="mt-2 grid gap-2 sm:grid-cols-2">
            <label className="flex cursor-pointer gap-3 rounded-xl border border-white/10 bg-white/[0.025] p-3 text-sm text-slate-300">
              <input
                checked={mode === "create"}
                className="mt-0.5 accent-cyan-300"
                name={`mode-choice-${bufferPostId}`}
                onChange={() => {
                  setMode("create");
                  setSelectedGroupName("");
                }}
                type="radio"
              />
              <span>
                <strong className="block text-white">New Clip Group</strong>
                Create labels for a new clip.
              </span>
            </label>
            <label className="flex cursor-pointer gap-3 rounded-xl border border-white/10 bg-white/[0.025] p-3 text-sm text-slate-300">
              <input
                checked={mode === "link_existing"}
                className="mt-0.5 accent-cyan-300"
                disabled={clipGroups.length === 0}
                name={`mode-choice-${bufferPostId}`}
                onChange={() => setMode("link_existing")}
                type="radio"
              />
              <span>
                <strong className="block text-white">
                  Existing Clip Group
                </strong>
                Link another platform version.
              </span>
            </label>
          </div>
        </fieldset>

        {mode === "create" ? (
          <>
            <label className="block text-xs font-medium text-slate-300">
              Clip Group *
              <input
                className={fieldClassName}
                maxLength={160}
                name="clip_group"
                placeholder="Example: Castle Circuit tutorial 03"
                required
              />
            </label>

            <div className="grid gap-3 sm:grid-cols-3">
              <SelectField
                label="Game"
                name="game"
                options={labelGames}
                required
              />
              <SelectField
                label="Content Type"
                name="content_type"
                options={labelContentTypes}
                required
              />
              <SelectField
                label="Vibe"
                name="vibe"
                options={labelVibes}
                required
              />
              <SelectField
                label="Hook Type"
                name="hook_type"
                options={labelHookTypes}
              />
              <SelectField
                label="Editing Intensity"
                name="editing_intensity"
                options={labelEditingIntensities}
              />
              <label className="text-xs font-medium text-slate-300">
                Duration (seconds)
                <input
                  className={fieldClassName}
                  max={86_400}
                  min={0}
                  name="duration_seconds"
                  placeholder="45"
                  step={1}
                  type="number"
                />
              </label>
            </div>

            <div className="grid gap-3 sm:grid-cols-2">
              <label className="text-xs font-medium text-slate-300">
                Source Recording
                <input
                  className={fieldClassName}
                  maxLength={255}
                  name="source_recording"
                  placeholder="Optional filename or project"
                />
              </label>
              <label className="text-xs font-medium text-slate-300">
                Notes
                <textarea
                  className={`${fieldClassName} min-h-20 resize-y`}
                  maxLength={2_000}
                  name="notes"
                  placeholder="Optional context"
                />
              </label>
            </div>
          </>
        ) : (
          <>
            <label className="block text-xs font-medium text-slate-300">
              Existing Clip Group *
              <select
                className={fieldClassName}
                name="clip_group"
                onChange={(event) => setSelectedGroupName(event.target.value)}
                required
                value={selectedGroupName}
              >
                <option value="">Choose an existing group</option>
                {clipGroups.map((group) => (
                  <option key={group.name} value={group.name}>
                    {group.name}
                  </option>
                ))}
              </select>
            </label>

            {selectedGroup && (
              <div className="rounded-xl border border-amber-300/20 bg-amber-300/[0.06] p-4 text-sm leading-6 text-slate-300">
                <p className="flex items-center gap-2 font-medium text-amber-100">
                  <Layers3 aria-hidden size={16} />
                  Shared Clip Group confirmation
                </p>
                <p className="mt-2">
                  This adds the selected post to{" "}
                  <strong>{selectedGroup.name}</strong>. Its existing labels
                  stay unchanged: {selectedGroup.game ?? "unknown game"}
                  {" · "}
                  {selectedGroup.contentType ?? "unknown type"}
                  {" · "}
                  {selectedGroup.vibe ?? "unknown vibe"}.
                </p>
                <p className="mt-1 text-xs text-slate-400">
                  Visible reporting sample: {selectedGroup.postCount} linked{" "}
                  {selectedGroup.postCount === 1 ? "row" : "rows"}
                  {selectedGroup.platforms.length > 0
                    ? ` across ${selectedGroup.platforms.join(", ")}`
                    : ""}
                  . After saving, at least {selectedGroup.postCount + 1} posts
                  will share this group. The save response reports the full
                  database total.
                </p>
                <label className="mt-3 flex cursor-pointer items-start gap-2 text-xs text-amber-100">
                  <input
                    className="mt-0.5 accent-amber-300"
                    name="confirm_shared_effect"
                    required
                    type="checkbox"
                  />
                  I reviewed the shared effect and want to link this post.
                </label>
              </div>
            )}
          </>
        )}

        <div className="flex flex-col gap-3 border-t border-white/5 pt-4 sm:flex-row sm:items-center sm:justify-between">
          <p className="flex items-center gap-2 text-xs text-slate-500">
            <Sheet aria-hidden size={14} />
            Only not-yet-exported rows can be saved here. Exported rows stay in
            Google Sheets.
          </p>
          <button
            className="inline-flex shrink-0 items-center justify-center gap-2 rounded-xl bg-cyan-300 px-4 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-cyan-200 disabled:cursor-not-allowed disabled:opacity-50"
            disabled={pending || (mode === "link_existing" && !selectedGroup)}
            type="submit"
          >
            <Save aria-hidden size={15} />
            {pending ? "Saving…" : "Save label"}
          </button>
        </div>

        {state.status !== "idle" && (
          <p
            aria-live="polite"
            className={`rounded-xl border px-3 py-2.5 text-sm ${
              state.status === "success"
                ? "border-emerald-300/20 bg-emerald-300/[0.07] text-emerald-100"
                : "border-rose-300/20 bg-rose-300/[0.07] text-rose-100"
            }`}
            role={state.status === "error" ? "alert" : "status"}
          >
            {state.message}
          </p>
        )}
      </form>
    </details>
  );
}
