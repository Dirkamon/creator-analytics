import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import { AnalyticsView } from "@/components/analytics/analytics-view";
import { analyticsFixture } from "@/test/fixtures";

afterEach(cleanup);

describe("AnalyticsView", () => {
  it("separates platform evidence and exposes sample sizes and fallback state", () => {
    render(<AnalyticsView data={analyticsFixture} />);

    expect(screen.getByRole("heading", { name: "Analytics" })).toBeVisible();
    expect(screen.getAllByText("TikTok").length).toBeGreaterThan(0);
    expect(screen.getAllByText("YouTube").length).toBeGreaterThan(0);
    expect(screen.getAllByText(/8 posts/).length).toBeGreaterThan(0);
    expect(screen.getByText("Game + Content Type")).toBeVisible();
    expect(
      screen.getByText(/Small samples are directional, not conclusive/),
    ).toBeVisible();
    expect(screen.getByText(/reports delayed or stale metrics/)).toBeVisible();
  });

  it("has no scheduling or mutation controls", () => {
    render(<AnalyticsView data={analyticsFixture} />);

    expect(screen.queryByRole("button")).not.toBeInTheDocument();
    expect(screen.queryByText(/^Refresh$/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/^Apply$/i)).not.toBeInTheDocument();
  });

  it("renders empty and partial-error states", () => {
    render(
      <AnalyticsView
        data={{
          contentPerformance: [],
          postingWindows: [],
          recommendations: [],
          fallbackSelections: [],
          cadenceSettings: [],
          weeklySlots: [],
          partialErrors: [
            {
              section: "Posting windows",
              message: "Posting windows are temporarily unavailable.",
            },
          ],
        }}
      />,
    );

    expect(screen.getByText("Some sections could not be loaded")).toBeVisible();
    expect(screen.getByText("No analytics rows were returned")).toBeVisible();
  });
});
