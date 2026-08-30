import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import { SystemStatusView } from "@/components/system-status/system-status-view";
import { systemStatusFixture } from "@/test/fixtures";

afterEach(cleanup);

describe("SystemStatusView", () => {
  it("shows database-observed freshness, blocks, and the exact label backlog", () => {
    render(<SystemStatusView data={systemStatusFixture} />);

    expect(
      screen.getByRole("heading", { name: "System Status" }),
    ).toBeVisible();
    expect(screen.getByText("Database-observed")).toBeVisible();
    expect(screen.getAllByText("3").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Fresh").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Stale").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Missing").length).toBeGreaterThan(0);
    expect(
      screen.getAllByText(
        /row counts do not represent current pipeline failures/,
      ).length,
    ).toBeGreaterThan(0);
    expect(
      screen.getByText(/exported-but-unlinked total is database state/),
    ).toBeVisible();
    expect(
      screen.getByText(/Same-channel minimum-gap conflict/i),
    ).toBeVisible();
    expect(screen.getByText(/External health is unavailable/)).toBeVisible();
  });

  it("does not claim external health or expose operational controls", () => {
    render(<SystemStatusView data={systemStatusFixture} />);

    expect(
      screen.getByText(/does not verify live Buffer queues/),
    ).toBeVisible();
    expect(screen.queryByRole("button")).not.toBeInTheDocument();
    expect(screen.queryByText(/^Retry Make$/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/^Refresh$/i)).not.toBeInTheDocument();
  });

  it("renders unavailable counts and a partial-error state", () => {
    render(
      <SystemStatusView
        data={{
          ...systemStatusFixture,
          summary: {
            observedPosts: null,
            postSyncPlatformsNeedingAttention: null,
            observedSentMetrics: null,
            metricsPlatformsNeedingAttention: null,
            proposalErrors: null,
            blockedApprovedProposals: null,
            unlinkedPosts: null,
            pendingLabelExports: null,
            exportedStillUnlinked: null,
          },
          partialErrors: [
            {
              section: "Post and metrics freshness",
              message: "Post and metrics freshness is temporarily unavailable.",
            },
          ],
        }}
      />,
    );

    expect(screen.getByText("Some sections could not be loaded")).toBeVisible();
    expect(screen.getAllByText("Unavailable").length).toBeGreaterThan(0);
  });
});
