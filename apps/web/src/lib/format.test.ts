import { describe, expect, it } from "vitest";

import {
  formatDateTime,
  isCalendarDateStale,
  localDateKey,
  sanitizeExternalUrl,
} from "@/lib/format";

describe("America/Denver display formatting", () => {
  it("uses daylight-saving offset for the historical collision instant", () => {
    const formatted = formatDateTime("2026-08-24T20:00:00.000Z");
    expect(formatted).toContain("Aug 24");
    expect(formatted).toContain("2:00 PM");
  });

  it("uses the standard-time offset in winter", () => {
    expect(formatDateTime("2026-01-12T20:00:00.000Z")).toContain("1:00 PM");
  });

  it("groups UTC instants by their Denver calendar date", () => {
    expect(localDateKey("2026-08-25T01:30:00.000Z")).toBe("2026-08-24");
  });

  it("evaluates staleness using Denver calendar days", () => {
    expect(
      isCalendarDateStale({
        value: "2026-08-26",
        now: new Date("2026-08-29T07:00:00.000Z"),
        maxAgeDays: 2,
      }),
    ).toBe(true);
  });

  it("allows only http and https external links", () => {
    expect(sanitizeExternalUrl("javascript:alert(1)")).toBeNull();
    expect(sanitizeExternalUrl("https://example.invalid/post/1")).toBe(
      "https://example.invalid/post/1",
    );
  });
});
