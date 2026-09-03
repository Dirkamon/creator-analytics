import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it } from "vitest";

import { TopPostsView } from "@/components/top-posts/top-posts-view";
import { dashboardFixture } from "@/test/fixtures";

afterEach(cleanup);

describe("TopPostsView", () => {
  const data = {
    posts: dashboardFixture.filterablePosts,
    partialErrors: [],
  };

  it("renders the Looker-parity columns and ranks posts by views", () => {
    render(<TopPostsView data={data} />);

    expect(screen.getByRole("heading", { name: "Top Posts" })).toBeVisible();
    expect(screen.getByRole("button", { name: "Sort by Views" })).toBeVisible();
    expect(
      screen.getByRole("button", { name: "Sort by Reactions" }),
    ).toBeVisible();
    expect(
      screen.getByRole("button", { name: "Sort by Interaction rate" }),
    ).toBeVisible();
    expect(screen.getByText("9,200")).toBeVisible();
  });

  it("filters by platform and keeps the controls read-only", async () => {
    const user = userEvent.setup();
    render(<TopPostsView data={data} />);

    await user.selectOptions(screen.getByLabelText("Platform"), "youtube");

    expect(
      screen.getByText("A second sanitized highlight for test coverage"),
    ).toBeVisible();
    expect(screen.queryByText("9,200")).not.toBeInTheDocument();
  });
});
