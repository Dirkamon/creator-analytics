import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import { LabelQueueView } from "@/components/label-queue/label-queue-view";
import { labelQueueFixture } from "@/test/fixtures";

afterEach(cleanup);

describe("LabelQueueView", () => {
  it("shows observed export states and shared Clip Group relationships", () => {
    render(<LabelQueueView data={labelQueueFixture} />);

    expect(
      screen.getByRole("heading", { name: "Label Queue" }),
    ).toBeInTheDocument();
    expect(screen.getAllByText("Pending export").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Export in progress").length).toBeGreaterThan(0);
    expect(
      screen.getAllByText("Exported · still unlinked").length,
    ).toBeGreaterThan(0);
    expect(screen.getByText("Sample Shared Clip")).toBeInTheDocument();
    expect(
      screen.getByText(/Linking a post to an existing group/),
    ).toBeInTheDocument();
  });

  it("keeps labeling controls hidden when the deployment is observation-only", () => {
    render(<LabelQueueView data={labelQueueFixture} />);

    expect(screen.queryByRole("button")).not.toBeInTheDocument();
    expect(screen.queryByText(/^Process$/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/^Label$/i)).not.toBeInTheDocument();
  });

  it("exposes a controlled editor only for rows not yet exported to Sheets", () => {
    render(<LabelQueueView data={labelQueueFixture} labelingEnabled />);

    expect(
      screen.getByText("Controlled labeling", { exact: true }),
    ).toBeInTheDocument();
    expect(screen.getAllByText("Label in app", { exact: true })).toHaveLength(
      1,
    );
    expect(screen.getByText(/Make has claimed this row/i)).toBeInTheDocument();
    expect(screen.getByText(/already in Google Sheets/i)).toBeInTheDocument();
  });

  it("renders a read-only empty state", () => {
    render(
      <LabelQueueView
        data={{
          summary: {
            unlinked: 0,
            pendingExport: 0,
            exportInProgress: 0,
            exportedStillUnlinked: 0,
          },
          items: [],
          clipGroups: [],
          partialErrors: [],
        }}
      />,
    );

    expect(
      screen.getByText("No unlinked posts were returned"),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/will not start a Sheet export/i),
    ).toBeInTheDocument();
  });
});
