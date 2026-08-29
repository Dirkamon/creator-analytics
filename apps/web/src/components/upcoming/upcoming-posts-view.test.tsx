import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { UpcomingPostsView } from "@/components/upcoming/upcoming-posts-view";
import { upcomingPostsFixture } from "@/test/fixtures";

describe("UpcomingPostsView", () => {
  it("separates synchronized schedules from proposal history", () => {
    render(<UpcomingPostsView data={upcomingPostsFixture} />);

    expect(
      screen.getByRole("heading", { name: "Upcoming Posts" }),
    ).toBeInTheDocument();
    expect(screen.getAllByText("Buffer-synchronized schedule")).toHaveLength(2);
    expect(screen.getAllByText("Latest proposal record")).toHaveLength(2);
    expect(screen.getByText("Pending")).toBeInTheDocument();
    expect(screen.getByText(/Mon, Aug 31, 2:00 PM/)).toBeInTheDocument();
  });

  it("renders a read-only empty state", () => {
    render(<UpcomingPostsView data={{ posts: [], partialErrors: [] }} />);
    expect(
      screen.getByText("No upcoming posts were returned"),
    ).toBeInTheDocument();
    expect(screen.getByText(/will not trigger a refresh/i)).toBeInTheDocument();
  });
});
