import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";

import { Navigation } from "@/components/shell/navigation";

vi.mock("next/navigation", () => ({
  usePathname: () => "/label-queue",
}));

afterEach(cleanup);

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
  expect(
    screen.queryByRole("link", { name: "Scheduling Preferences" }),
  ).not.toBeInTheDocument();
});

it("exposes the draft preferences only through sample preview navigation", () => {
  render(<Navigation previewPath="/scheduling-preferences" />);
  expect(
    screen.getByRole("link", { name: "Scheduling Preferences" }),
  ).toHaveAttribute("href", "/design-preview?view=scheduling-preferences");
  expect(
    screen.getByRole("link", { name: "Scheduling Preferences" }),
  ).toHaveAttribute("aria-current", "page");
  for (const link of screen.getAllByRole("link")) {
    expect(link.getAttribute("href")).toMatch(/^\/design-preview\?view=/);
  }
});
