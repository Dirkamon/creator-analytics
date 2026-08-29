import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import {
  EmptyState,
  LoadingState,
  PartialErrorState,
  PermissionErrorState,
  StaleNotice,
  UnexpectedErrorState,
} from "@/components/states/feedback-states";

describe("reusable feedback states", () => {
  it("renders an accessible loading state", () => {
    render(<LoadingState label="Loading upcoming posts" />);
    expect(screen.getByLabelText("Loading upcoming posts")).toBeInTheDocument();
  });

  it("renders empty, stale, partial, and permission messages", () => {
    render(
      <>
        <EmptyState title="Nothing scheduled">No rows.</EmptyState>
        <StaleNotice>Last sync is old.</StaleNotice>
        <PartialErrorState
          errors={[{ section: "Growth", message: "Unavailable." }]}
        />
        <PermissionErrorState>Allowlist required.</PermissionErrorState>
      </>,
    );

    expect(screen.getByText("Nothing scheduled")).toBeInTheDocument();
    expect(screen.getByText("This data may be stale")).toBeInTheDocument();
    expect(
      screen.getByText("Some sections could not be loaded"),
    ).toBeInTheDocument();
    expect(screen.getByText("Private access required")).toBeInTheDocument();
  });

  it("offers a retry without exposing an error object", () => {
    const retry = vi.fn();
    render(<UnexpectedErrorState retry={retry} />);
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(retry).toHaveBeenCalledOnce();
  });
});
