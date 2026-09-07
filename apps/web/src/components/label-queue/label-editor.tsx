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
  "mt-1.5 w-full rounded-xl border border-line bg-canvas/80 px-3 py-2.5 text-sm text-foreground outline-none transition placeholder:text-muted focus:border-accent/40 focus:ring-2 focus:ring-accent/10";

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
    <label className="text-secondary text-xs font-medium">
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
    <details className="border-accent/15 bg-accent/[0.035] open:bg-canvas/60 mt-4 rounded-xl border p-3">
      <summary className="text-accent cursor-pointer list-none text-sm font-medium marker:hidden">
        <span className="inline-flex items-center gap-2">
          <Tags aria-hidden size={15} />
          Label in app
        </span>
      </summary>

      <form action={formAction} className="mt-4 space-y-4">
        <input name="post_id" type="hidden" value={bufferPostId} />
        <input name="mode" type="hidden" value={mode} />

        <fieldset>
          <legend className="text-secondary text-xs font-medium">
            Clip Group choice
          </legend>
          <div className="mt-2 grid gap-2 sm:grid-cols-2">
            <label className="border-line bg-foreground/[0.025] text-secondary flex cursor-pointer gap-3 rounded-xl border p-3 text-sm">
              <input
                checked={mode === "create"}
                className="accent-accent mt-0.5"
                name={`mode-choice-${bufferPostId}`}
                onChange={() => {
                  setMode("create");
                  setSelectedGroupName("");
                }}
                type="radio"
              />
              <span>
                <strong className="text-foreground block">
                  New Clip Group
                </strong>
                Create labels for a new clip.
              </span>
            </label>
            <label className="border-line bg-foreground/[0.025] text-secondary flex cursor-pointer gap-3 rounded-xl border p-3 text-sm">
              <input
                checked={mode === "link_existing"}
                className="accent-accent mt-0.5"
                disabled={clipGroups.length === 0}
                name={`mode-choice-${bufferPostId}`}
                onChange={() => setMode("link_existing")}
                type="radio"
              />
              <span>
                <strong className="text-foreground block">
                  Existing Clip Group
                </strong>
                Link another platform version.
              </span>
            </label>
          </div>
        </fieldset>

        {mode === "create" ? (
          <>
            <label className="text-secondary block text-xs font-medium">
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
              <label className="text-secondary text-xs font-medium">
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
              <label className="text-secondary text-xs font-medium">
                Source Recording
                <input
                  className={fieldClassName}
                  maxLength={255}
                  name="source_recording"
                  placeholder="Optional filename or project"
                />
              </label>
              <label className="text-secondary text-xs font-medium">
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
            <label className="text-secondary block text-xs font-medium">
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
              <div className="border-warning/20 bg-warning/[0.06] text-secondary rounded-xl border p-4 text-sm leading-6">
                <p className="text-warning flex items-center gap-2 font-medium">
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
                <p className="text-muted mt-1 text-xs">
                  Visible reporting sample: {selectedGroup.postCount} linked{" "}
                  {selectedGroup.postCount === 1 ? "row" : "rows"}
                  {selectedGroup.platforms.length > 0
                    ? ` across ${selectedGroup.platforms.join(", ")}`
                    : ""}
                  . After saving, at least {selectedGroup.postCount + 1} posts
                  will share this group. The save response reports the full
                  database total.
                </p>
                <label className="text-warning mt-3 flex cursor-pointer items-start gap-2 text-xs">
                  <input
                    className="accent-warning mt-0.5"
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

        <div className="border-line flex flex-col gap-3 border-t pt-4 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-muted flex items-center gap-2 text-xs">
            <Sheet aria-hidden size={14} />
            Only not-yet-exported rows can be saved here. Exported rows stay in
            Google Sheets.
          </p>
          <button
            className="bg-accent-solid text-on-accent hover:bg-accent-hover inline-flex shrink-0 items-center justify-center gap-2 rounded-xl px-4 py-2.5 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-50"
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
                ? "border-success/20 bg-success/[0.07] text-success"
                : "border-danger/20 bg-danger/[0.07] text-danger"
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
