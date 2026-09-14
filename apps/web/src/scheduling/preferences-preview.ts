/** Local design-preview model only. Never used to generate real proposals. */
export type PostingPreferenceDraft = {
  weeklyTarget: number;
  dailyCeiling: number;
};

export const initialPostingPreference: PostingPreferenceDraft = {
  weeklyTarget: 14,
  dailyCeiling: 3,
};

export const previewDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

export function validatePostingPreference(draft: PostingPreferenceDraft) {
  if (
    !Number.isInteger(draft.dailyCeiling) ||
    draft.dailyCeiling < 1 ||
    draft.dailyCeiling > 4
  ) {
    return "Choose a daily ceiling between 1 and 4 posts.";
  }
  if (!Number.isInteger(draft.weeklyTarget) || draft.weeklyTarget < 7) {
    return "Choose at least 7 posts per week to cover every day.";
  }
  if (draft.weeklyTarget > draft.dailyCeiling * 7) {
    return "The weekly target is higher than your daily ceiling allows.";
  }
  return null;
}

/** Illustrates counts, not dates, safe slots, analytics, or Buffer changes. */
export function illustratePostingWeek(
  draft: PostingPreferenceDraft,
  availableClips: number,
  exampleDayOrder: readonly number[],
) {
  const error = validatePostingPreference(draft);
  if (error) throw new Error(error);
  if (
    !Number.isInteger(availableClips) ||
    availableClips < 0 ||
    availableClips > 100
  ) {
    throw new Error(
      "Example clip stock must be a whole number between 0 and 100.",
    );
  }
  if (
    exampleDayOrder.length !== 7 ||
    new Set(exampleDayOrder).size !== 7 ||
    exampleDayOrder.some((day) => !Number.isInteger(day) || day < 0 || day > 6)
  ) {
    throw new Error(
      "An example week must include all seven days exactly once.",
    );
  }

  const counts = Array<number>(7).fill(0);
  let remaining = Math.min(availableClips, draft.weeklyTarget);
  // Reserve one per day before placing any extras. A short-stock illustration
  // covers the earliest days; production will also need eligibility checks.
  for (let day = 0; day < 7 && remaining > 0; day += 1) {
    counts[day] = 1;
    remaining -= 1;
  }
  for (const day of exampleDayOrder) {
    const extra = Math.min(remaining, draft.dailyCeiling - counts[day]);
    counts[day] += extra;
    remaining -= extra;
  }
  const planned = counts.reduce((sum, count) => sum + count, 0);
  return {
    counts,
    planned,
    uncoveredDays: counts.filter((count) => count === 0).length,
    targetShortfall: draft.weeklyTarget - planned,
    unusedClips: availableClips - planned,
  };
}
