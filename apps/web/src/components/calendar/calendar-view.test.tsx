import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { CalendarView } from "@/components/calendar/calendar-view";
import { calendarPreview } from "@/test/calendar-preview";

const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));
afterEach(cleanup);

it("shows month totals, individual platform posts, and full names for a selected day", () => {
  render(<CalendarView data={calendarPreview()} />);
  expect(
    screen.getByRole("heading", { name: "September 2026" }),
  ).toBeInTheDocument();
  expect(
    screen.getByText("18 posts · 12 scheduled · 6 published"),
  ).toBeInTheDocument();
  fireEvent.click(
    screen.getByRole("button", { name: "Friday, September 11, 2026: 2 posts" }),
  );
  const details = screen.getByRole("region", {
    name: "Friday, September 11, 2026",
  });
  expect(within(details).getAllByRole("article")).toHaveLength(2);
  expect(
    within(details).getAllByRole("heading", {
      name: "Castle Circuit — perfect finish",
    }),
  ).toHaveLength(2);
  expect(within(details).getAllByText("Scheduled")).toHaveLength(2);
  expect(
    within(details).getByText("Fri, Sep 11, 10:00 AM MDT"),
  ).toBeInTheDocument();
  expect(
    screen.queryByRole("button", { name: /approve|save|reschedule/i }),
  ).not.toBeInTheDocument();
});

it("supports keyboard day navigation and clear empty states", () => {
  render(<CalendarView data={calendarPreview()} />);
  const today = screen.getByRole("button", {
    name: "Sunday, September 6, 2026: 2 posts",
  });
  expect(today).toHaveAttribute("aria-current", "date");
  fireEvent.keyDown(today, { key: "ArrowRight" });
  expect(
    screen.getByRole("button", { name: "Monday, September 7, 2026: 0 posts" }),
  ).toHaveFocus();
  expect(
    screen.getByText(
      "No scheduled or published posts on this day in the synchronized data.",
    ),
  ).toBeInTheDocument();
});

it("navigates months and years with a direct month picker", () => {
  render(<CalendarView data={calendarPreview("2026-12")} />);
  expect(screen.getByRole("link", { name: "Next month" })).toHaveAttribute(
    "href",
    "/calendar?month=2027-01",
  );
  expect(screen.getByRole("link", { name: "Previous month" })).toHaveAttribute(
    "href",
    "/calendar?month=2026-11",
  );
  expect(screen.getByRole("link", { name: "Today" })).toHaveAttribute(
    "href",
    "/calendar?month=2026-09",
  );
  fireEvent.change(screen.getByLabelText("Go to month"), {
    target: { value: "2024-02" },
  });
  expect(push).toHaveBeenCalledWith("/calendar?month=2024-02");
});

it("does not call a failed read an empty schedule", () => {
  render(
    <CalendarView
      data={{
        ...calendarPreview(),
        posts: [],
        partialErrors: [
          { section: "Scheduled posts", message: "Refresh to try again." },
        ],
      }}
    />,
  );
  expect(
    screen.getByText("Some sections could not be loaded"),
  ).toBeInTheDocument();
  expect(
    screen.getByText(
      "Some post data is unavailable. Refresh before treating this as an open day.",
    ),
  ).toBeInTheDocument();
  expect(
    screen.queryByText(
      "No scheduled or published posts on this day in the synchronized data.",
    ),
  ).not.toBeInTheDocument();
});

it("keeps preview navigation separate from live data", () => {
  render(<CalendarView data={calendarPreview()} preview />);
  expect(screen.getByRole("link", { name: "Next month" })).toHaveAttribute(
    "href",
    "/design-preview?view=calendar&month=2026-10",
  );
});
