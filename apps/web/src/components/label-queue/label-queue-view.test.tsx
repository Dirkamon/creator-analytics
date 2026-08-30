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
    expect(
      screen.getAllByText("Exported · still unlinked").length,
    ).toBeGreaterThan(0);
    expect(screen.getByText("Sample Shared Clip")).toBeInTheDocument();
    expect(
      screen.getByText(/A change to one content item affects/),
    ).toBeInTheDocument();
  });

  it("does not expose labeling or processing controls", () => {
    render(<LabelQueueView data={labelQueueFixture} />);

    expect(screen.queryByRole("button")).not.toBeInTheDocument();
    expect(screen.queryByText(/^Process$/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/^Label$/i)).not.toBeInTheDocument();
  });

  it("renders a read-only empty state", () => {
    render(
      <LabelQueueView
        data={{
          summary: {
            unlinked: 0,
            pendingExport: 0,
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
    expect(screen.getByText(/will not start an export/i)).toBeInTheDocument();
  });
});
