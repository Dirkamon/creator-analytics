import { cleanup, fireEvent, render, screen } from "@testing-library/react";
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

  it("shows controls only for an app-owned Pending proposal", () => {
    const pending = scheduleApprovalsFixture.proposals[0];
    render(
      <ScheduleApprovalsView
        data={{
          proposals: [
            pending,
            {
              ...pending,
              proposalId: "00000000-0000-4000-8000-000000000010",
              exportState: "export_in_progress",
              exportClaimedAt: "2026-08-29T09:12:00.000Z",
            },
            {
              ...pending,
              proposalId: "00000000-0000-4000-8000-000000000011",
              exportState: "exported",
            },
            {
              ...pending,
              proposalId: "00000000-0000-4000-8000-000000000012",
              exportState: "unavailable",
            },
          ],
          partialErrors: [],
        }}
        decisionsEnabled
      />,
    );

    expect(screen.getByText("Controlled decisions")).toBeInTheDocument();
    expect(
      screen.getByRole("radio", { name: "Approve proposal" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("radio", { name: "Reject proposal" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Save decision" }),
    ).toBeInTheDocument();
    expect(screen.getAllByText("Decide in app")).toHaveLength(1);
    expect(screen.getByText(/export is in progress/i)).toBeInTheDocument();
    expect(
      screen.getByText(/belongs to the existing Google Sheets workflow/i),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/ownership state could not be verified/i),
    ).toBeInTheDocument();
  });

  it("serializes the selected decision and explicit confirmation", () => {
    render(
      <ScheduleApprovalsView
        data={{
          proposals: [scheduleApprovalsFixture.proposals[0]],
          partialErrors: [],
        }}
        decisionsEnabled
      />,
    );

    fireEvent.click(screen.getByRole("radio", { name: "Approve proposal" }));
    fireEvent.click(
      screen.getByRole("checkbox", {
        name: /I reviewed the current and proposed times/i,
      }),
    );

    const form = screen
      .getByRole("button", { name: "Save decision" })
      .closest("form");
    expect(form).not.toBeNull();

    const submission = new FormData(form!);
    expect(submission.get("decision")).toBe("Approved");
    expect(submission.get("confirm_decision")).toBe("on");
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
