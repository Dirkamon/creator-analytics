import { describe, expect, it } from "vitest";
import {
  calendarDateLabel,
  calendarMonth,
  calendarQueryBounds,
  monthCells,
  postsByDay,
  shiftMonth,
} from "@/data/calendar";
import { calendarPreview } from "@/test/calendar-preview";

describe("calendar dates", () => {
  it("uses Denver's current month and rejects malformed or unsupported month inputs", () => {
    const now = new Date("2026-10-01T02:00:00Z");
    for (const invalid of [
      undefined,
      ["2026-09"],
      "2026-13",
      "9999-01",
      "2026-09';drop",
      "2026-9",
    ]) {
      expect(calendarMonth(invalid, now)).toBe("2026-09");
    }
    expect(calendarMonth("2024-02", now)).toBe("2024-02");
  });

  it("builds real month grids including leap days and six-week months", () => {
    const leap = monthCells("2024-02");
    expect(leap.slice(0, 4)).toEqual([null, null, null, null]);
    expect(leap.filter(Boolean)).toHaveLength(29);
    expect(monthCells("2025-02").filter(Boolean)).toHaveLength(28);
    expect(monthCells("2026-08")).toHaveLength(42);
    expect(monthCells("2026-02")).toHaveLength(28);
  });

  it("moves across years and formats dates without timezone shifts", () => {
    expect(shiftMonth("2026-12", 1)).toBe("2027-01");
    expect(shiftMonth("2026-01", -1)).toBe("2025-12");
    expect(calendarDateLabel("2026-09", true)).toBe("September 2026");
    expect(calendarDateLabel("2026-09-01")).toBe("Tuesday, September 1, 2026");
  });

  it("groups local midnight and DST instants by Denver day, preserving platform posts", () => {
    const template = calendarPreview().posts[0];
    const grouped = postsByDay([
      { ...template, key: "late", at: "2026-10-01T05:59:00Z" },
      { ...template, key: "early", at: "2026-10-01T06:01:00Z" },
      { ...template, key: "dst-first", at: "2026-11-01T07:30:00Z" },
      {
        ...template,
        key: "dst-second",
        at: "2026-11-01T08:30:00Z",
        platform: "youtube",
      },
    ]);
    expect(grouped.get("2026-09-30")?.map((post) => post.key)).toEqual([
      "late",
    ]);
    expect(grouped.get("2026-10-01")?.map((post) => post.key)).toEqual([
      "early",
    ]);
    expect(grouped.get("2026-11-01")?.map((post) => post.key)).toEqual([
      "dst-first",
      "dst-second",
    ]);
    expect(calendarQueryBounds("2026-03")).toEqual({
      from: "2026-02-28T00:00:00.000Z",
      through: "2026-04-02T00:00:00.000Z",
    });
    expect(() => calendarQueryBounds("bad")).toThrow();
  });
});
