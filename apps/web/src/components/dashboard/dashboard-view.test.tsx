import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it } from "vitest";

import { DashboardView } from "@/components/dashboard/dashboard-view";
import { dashboardFixture } from "@/test/fixtures";

afterEach(cleanup);

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
    expect(screen.getByText("1,000")).toBeInTheDocument();
    expect(screen.getByText("Sample Clip Alpha · labeled")).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: "Open tiktok post" }),
    ).toHaveAttribute("href", "https://example.invalid/posts/sample-one");
  });

  it("filters every post-backed dashboard metric without changing source data", async () => {
    const user = userEvent.setup();
    render(
      <DashboardView
        data={dashboardFixture}
        now={new Date("2026-08-29T18:00:00.000Z")}
      />,
    );

    await user.selectOptions(screen.getByLabelText("Platform"), "youtube");

    expect(screen.getAllByText("6,200").length).toBeGreaterThan(0);
    expect(screen.getByText("300")).toBeInTheDocument();
    expect(
      screen.queryByText("Sample Clip Alpha · labeled"),
    ).not.toBeInTheDocument();
  });

  it("renders the explicit empty state", () => {
    render(
      <DashboardView
        data={{
          ...dashboardFixture,
          summary: {
            postCount: 0,
            totalViews: 0,
            totalReactions: 0,
            totalComments: 0,
            totalShares: 0,
            averageViews: 0,
            averageInteractionRate: null,
          },
          filterablePosts: [],
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
