import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { DashboardView } from "@/components/dashboard/dashboard-view";
import { dashboardFixture } from "@/test/fixtures";

describe("DashboardView", () => {
  it("renders sanitized metrics, labels, and external post links", () => {
    render(
      <DashboardView
        data={dashboardFixture}
        now={new Date("2026-08-29T18:00:00.000Z")}
      />,
    );

    expect(
      screen.getByRole("heading", { name: "Dashboard" }),
    ).toBeInTheDocument();
    expect(screen.getByText("15.4K")).toBeInTheDocument();
    expect(screen.getByText("Sample Clip Alpha · labeled")).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: "Open tiktok post" }),
    ).toHaveAttribute("href", "https://example.invalid/posts/sample-one");
  });

  it("renders the explicit empty state", () => {
    render(
      <DashboardView
        data={{
          ...dashboardFixture,
          summary: {
            postCount: 0,
            totalViews: 0,
            averageViews: 0,
            averageInteractionRate: null,
          },
          recentPosts: [],
          growth: [],
          topTimes: [],
          topContent: [],
          latestMetricDate: null,
        }}
      />,
    );

    expect(
      screen.getByText("No dashboard data is available"),
    ).toBeInTheDocument();
  });
});
