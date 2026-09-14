import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { afterEach, expect, it } from "vitest";
import { PostingPreferencesPreview } from "@/components/preferences/posting-preferences-preview";

afterEach(cleanup);

it("clearly separates the local draft from active production settings", () => {
  render(<PostingPreferencesPreview />);
  expect(screen.getByText("Local draft · Not active")).toBeInTheDocument();
  expect(
    screen.getByText(/Illustration only—not your current queue/),
  ).toBeInTheDocument();
  expect(
    screen.getByText(/No settings are saved to the scheduler here/),
  ).toBeInTheDocument();
  expect(screen.getByLabelText("TikTok weekly target")).toHaveValue(14);
  expect(screen.getByLabelText("YouTube Shorts weekly target")).toHaveValue(14);
  expect(
    screen.getAllByText("All 7 days covered in this example."),
  ).toHaveLength(2);
  expect(
    screen.queryByRole("button", { name: /save|apply|approve/i }),
  ).not.toBeInTheDocument();
});

it("records unrestricted posting hours without presenting the draft as live", () => {
  render(<PostingPreferencesPreview />);
  const timing = within(screen.getByRole("region", { name: "Posting times" }));
  expect(timing.getByText("Any hour · America/Denver")).toBeInTheDocument();
  expect(
    timing.getByText(/All 24 hours are allowed, including overnight/),
  ).toHaveTextContent(
    "Let analytics rank the suggested posting times for each platform",
  );
  expect(
    timing.getByText(/Daily coverage and spacing still come first/),
  ).toHaveTextContent("not a change to live posting rules");
  expect(
    screen.queryByText(/Preferred hours .* need to be chosen/),
  ).not.toBeInTheDocument();
});

it("states the 12-hour limit in both directions without promising daily coverage", () => {
  render(<PostingPreferencesPreview />);
  const movement = within(
    screen.getByRole("region", { name: "Rescheduling limit" }),
  );
  expect(
    movement.getByText("Up to 12 hours earlier or later"),
  ).toBeInTheDocument();
  expect(
    movement.getByText(/Measure each proposal from the time you set in Buffer/),
  ).toHaveTextContent("Repeated proposals must not keep extending that window");
  expect(
    movement.getByText(/If daily coverage cannot be met within this limit/),
  ).toHaveTextContent("Nothing moves without your approval");
  expect(
    screen.getByText(/Illustration only—not your current queue/),
  ).toHaveTextContent("it does not check actual Buffer times");
  expect(
    screen.queryByText(/How far a proposal .* needs to be chosen/),
  ).not.toBeInTheDocument();
});

it("shows insufficient-stock warnings without extras on already-covered days", () => {
  render(<PostingPreferencesPreview />);
  fireEvent.change(screen.getByLabelText("Example clips available"), {
    target: { value: "6" },
  });
  expect(screen.getAllByText(/1 uncovered days/)).toHaveLength(2);
  expect(
    screen.getAllByText("8 more clips needed to reach the weekly target."),
  ).toHaveLength(2);
  const table = screen.getByRole("table", {
    name: "Illustrative weekly post counts",
  });
  expect(within(table).getAllByRole("cell", { name: "1" })).toHaveLength(12);
});

it("keeps platform controls independent and offers a reset", () => {
  render(<PostingPreferencesPreview />);
  fireEvent.change(screen.getByLabelText("TikTok weekly target"), {
    target: { value: "7" },
  });
  expect(screen.getByLabelText("YouTube Shorts weekly target")).toHaveValue(14);
  expect(
    screen.getByText(
      "7 clips left outside this example week. They are not forced into extra slots.",
    ),
  ).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Reset example" }));
  expect(screen.getByLabelText("TikTok weekly target")).toHaveValue(14);
  expect(screen.getByRole("status")).toHaveTextContent(
    "Draft reset to 14 per week",
  );
});

it("does not display plausible-looking results when the inputs are invalid", () => {
  render(<PostingPreferencesPreview />);
  fireEvent.change(screen.getByLabelText("TikTok daily ceiling"), {
    target: { value: "1" },
  });
  expect(screen.getByRole("alert")).toHaveTextContent(
    "The weekly target is higher than your daily ceiling allows.",
  );
  expect(screen.getByLabelText("TikTok weekly target")).toHaveAttribute(
    "aria-invalid",
    "true",
  );
  expect(
    screen.getByText("Correct the settings above to see an example."),
  ).toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("TikTok weekly target"), {
    target: { value: "" },
  });
  expect(screen.getByRole("alert")).toHaveTextContent(
    "Choose at least 7 posts per week",
  );
});
