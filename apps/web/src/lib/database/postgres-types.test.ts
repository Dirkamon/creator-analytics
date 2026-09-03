import { describe, expect, it } from "vitest";

import { postgresDateText } from "@/lib/database/postgres-types";

describe("PostgreSQL date text mapping", () => {
  it("preserves database date and timestamp text for application schemas", () => {
    expect(postgresDateText.from).toEqual([1082, 1114, 1184]);
    expect(postgresDateText.parse("2026-09-02")).toBe("2026-09-02");
    expect(postgresDateText.parse("2026-09-02 14:30:00+00")).toBe(
      "2026-09-02 14:30:00+00",
    );
  });

  it("serializes Date parameters as ISO timestamps", () => {
    expect(
      postgresDateText.serialize(new Date("2026-09-02T14:30:00.000Z")),
    ).toBe("2026-09-02T14:30:00.000Z");
  });
});
