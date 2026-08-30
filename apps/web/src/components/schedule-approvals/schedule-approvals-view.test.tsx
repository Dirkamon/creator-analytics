import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import { ScheduleApprovalsView } from "@/components/schedule-approvals/schedule-approvals-view";
import { scheduleApprovalsFixture } from "@/test/fixtures";

afterEach(cleanup);

describe("ScheduleApprovalsView", () => {
  it("keeps each repository-backed application stage visually distinct", () => {
    render(<ScheduleApprovalsView data={scheduleApprovalsFixture} />);

    expect(
      screen.getByRole("heading", { name: "Schedule Approvals" }),
    ).toBeInTheDocument();
    expect(screen.getAllByText("Pending").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Ready for Make").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Approved · blocked").length).toBeGreaterThan(0);
    expect(
      screen.getAllByText("Applied · awaiting sync").length,
    ).toBeGreaterThan(0);
    expect(screen.getAllByText("Synchronized").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Error").length).toBeGreaterThan(0);
    expect(
      screen.getByText(
        "Blocked: current schedule changed after proposal generation",
      ),
    ).toBeInTheDocument();
  });

  it("shows stored recommendation evidence without decision controls", () => {
    render(<ScheduleApprovalsView data={scheduleApprovalsFixture} />);

    expect(screen.getAllByText("Recommendation rationale")).toHaveLength(6);
    expect(
      screen.getAllByText(/Stored evidence: score 0.82 · source rank 1/),
    ).toHaveLength(6);
    expect(screen.queryByRole("button")).not.toBeInTheDocument();
    expect(screen.queryByText(/^Approve$/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/^Apply$/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/^Refresh$/i)).not.toBeInTheDocument();
  });

  it("renders a read-only empty state", () => {
    render(
      <ScheduleApprovalsView data={{ proposals: [], partialErrors: [] }} />,
    );

    expect(
      screen.getByText("No proposal history was returned"),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/cannot create or refresh proposals/i),
    ).toBeInTheDocument();
  });
});
