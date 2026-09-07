import { render, screen } from "@testing-library/react";
import { expect, it, vi } from "vitest";

import { Navigation } from "@/components/shell/navigation";

vi.mock("next/navigation", () => ({
  usePathname: () => "/label-queue",
}));

it("includes every authenticated read-only destination", () => {
  render(<Navigation />);

  expect(screen.getByRole("link", { name: "Calendar" })).toHaveAttribute(
    "href",
    "/calendar",
  );

  expect(screen.getByRole("link", { name: "Label Queue" })).toHaveAttribute(
    "href",
    "/label-queue",
  );
  expect(
    screen.getByRole("link", { name: "Schedule Approvals" }),
  ).toHaveAttribute("href", "/schedule-approvals");
  expect(screen.getByRole("link", { name: "Label Queue" })).toHaveAttribute(
    "aria-current",
    "page",
  );
  expect(screen.getByRole("link", { name: "Analytics" })).toHaveAttribute(
    "href",
    "/analytics",
  );
  expect(screen.getByRole("link", { name: "Top Posts" })).toHaveAttribute(
    "href",
    "/top-posts",
  );
  expect(screen.getByRole("link", { name: "System Status" })).toHaveAttribute(
    "href",
    "/system-status",
  );
});
