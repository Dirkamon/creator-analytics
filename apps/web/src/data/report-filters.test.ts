import { describe, expect, it } from "vitest";

import {
  EMPTY_REPORT_FILTERS,
  filterReportingPosts,
  reportFilterOptions,
} from "@/data/report-filters";
import { dashboardFixture } from "@/test/fixtures";

describe("report filters", () => {
  it("builds stable platform and game options", () => {
    expect(reportFilterOptions(dashboardFixture.filterablePosts)).toEqual({
      platforms: ["tiktok", "youtube"],
      games: ["Sample Game"],
    });
  });

  it("uses America/Denver calendar dates for inclusive boundaries", () => {
    const result = filterReportingPosts(dashboardFixture.filterablePosts, {
      ...EMPTY_REPORT_FILTERS,
      dateFrom: "2026-08-27",
      dateTo: "2026-08-27",
    });

    expect(result.map((post) => post.key)).toEqual(["SANITIZED_POST_ONE"]);
  });
});
