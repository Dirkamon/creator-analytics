import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import { PostThumbnail } from "@/components/recent-performance/post-thumbnail";

afterEach(cleanup);

describe("PostThumbnail", () => {
  it("loads the hosted still lazily without a proxy or page referrer", () => {
    const src = "https://images.buffer.com/thumbnail/test-clip";
    render(<PostThumbnail src={src} clipName="Halo clip" />);
    const image = screen.getByRole("img", { name: "Thumbnail for Halo clip" });
    expect(image).toHaveAttribute("src", src);
    expect(image).toHaveAttribute("loading", "lazy");
    expect(image).toHaveAttribute("referrerpolicy", "no-referrer");
  });

  it("uses a stable placeholder when the URL is missing or the image fails", () => {
    const view = render(<PostThumbnail src={null} clipName="Halo clip" />);
    expect(screen.getByText("No thumbnail available")).toBeVisible();
    expect(screen.queryByRole("img")).not.toBeInTheDocument();
    view.rerender(
      <PostThumbnail
        src="https://images.buffer.com/thumbnail/test-expired"
        clipName="Halo clip"
      />,
    );
    fireEvent.error(screen.getByRole("img"));
    expect(screen.queryByRole("img")).not.toBeInTheDocument();
    expect(screen.getByText("No thumbnail available")).toBeVisible();
    view.rerender(
      <PostThumbnail
        src="https://images.buffer.com/thumbnail/test-refreshed"
        clipName="Halo clip"
      />,
    );
    expect(screen.getByRole("img")).toHaveAttribute(
      "src",
      "https://images.buffer.com/thumbnail/test-refreshed",
    );
  });

  it("does not issue image requests to an untrusted source", () => {
    render(
      <PostThumbnail src="https://example.invalid/image.jpg" clipName="Clip" />,
    );
    expect(screen.queryByRole("img")).not.toBeInTheDocument();
    expect(screen.getByText("No thumbnail available")).toBeVisible();
  });
});
