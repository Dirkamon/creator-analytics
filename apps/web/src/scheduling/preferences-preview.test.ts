import { describe, expect, it } from "vitest";
import {
  illustratePostingWeek,
  initialPostingPreference,
  validatePostingPreference,
} from "@/scheduling/preferences-preview";

const order = [1, 4, 3, 2, 5, 6, 0];

describe("local coverage-first illustration", () => {
  it("captures the user's flexible two-a-day goal", () => {
    expect(initialPostingPreference).toEqual({
      weeklyTarget: 14,
      dailyCeiling: 3,
    });
    const week = illustratePostingWeek(initialPostingPreference, 14, order);
    expect(week.counts).toEqual([1, 3, 2, 3, 3, 1, 1]);
    expect(week.planned).toBe(14);
    expect(week.uncoveredDays).toBe(0);
  });

  it("uses the available clips for coverage before assigning extras", () => {
    const week = illustratePostingWeek(initialPostingPreference, 6, order);
    expect(week.counts).toEqual([1, 1, 1, 1, 1, 1, 0]);
    expect(week.uncoveredDays).toBe(1);
    expect(week.targetShortfall).toBe(8);
    expect(week.unusedClips).toBe(0);
  });

  it("never invents inventory or forces surplus clips into the week", () => {
    expect(
      illustratePostingWeek(initialPostingPreference, 0, order).planned,
    ).toBe(0);
    expect(
      illustratePostingWeek(initialPostingPreference, 28, order).unusedClips,
    ).toBe(14);
  });

  it("rejects impossible and non-whole-number targets", () => {
    for (const draft of [
      { weeklyTarget: 6, dailyCeiling: 3 },
      { weeklyTarget: 22, dailyCeiling: 3 },
      { weeklyTarget: NaN, dailyCeiling: 3 },
      { weeklyTarget: 14.5, dailyCeiling: 3 },
      { weeklyTarget: 14, dailyCeiling: 0 },
    ]) {
      expect(validatePostingPreference(draft)).not.toBeNull();
      expect(() => illustratePostingWeek(draft, 14, order)).toThrow();
    }
  });

  it("validates stock and the example's complete day order", () => {
    for (const stock of [-1, 1.5, NaN, Infinity, 101]) {
      expect(() =>
        illustratePostingWeek(initialPostingPreference, stock, order),
      ).toThrow();
    }
    for (const invalid of [
      [1, 1, 1, 1, 1, 1, 1],
      [0, 1, 2],
      [0, 1, 2, 3, 4, 5, 7],
    ]) {
      expect(() =>
        illustratePostingWeek(initialPostingPreference, 14, invalid),
      ).toThrow();
    }
  });

  it("preserves coverage, capacity, stock, and totals across all supported goals", () => {
    for (let ceiling = 1; ceiling <= 4; ceiling += 1) {
      for (let target = 7; target <= ceiling * 7; target += 1) {
        for (let stock = 0; stock <= 30; stock += 1) {
          const week = illustratePostingWeek(
            { weeklyTarget: target, dailyCeiling: ceiling },
            stock,
            order,
          );
          expect(week.planned).toBe(Math.min(stock, target));
          expect(
            week.counts.every((count) => count >= 0 && count <= ceiling),
          ).toBe(true);
          expect(week.uncoveredDays).toBe(Math.max(7 - stock, 0));
          if (stock >= 7)
            expect(week.counts.every((count) => count >= 1)).toBe(true);
          else expect(Math.max(...week.counts)).toBeLessThanOrEqual(1);
        }
      }
    }
  });
});
