import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it } from "vitest";

import { RecentPerformanceView } from "@/components/recent-performance/recent-performance-view";
import type {
  RecentPerformanceData,
  RecentPerformancePost,
} from "@/data/models";
import { dashboardFixture } from "@/test/fixtures";

afterEach(cleanup);
const now = new Date("2026-09-17T18:00:00Z");
function post(
  overrides: Partial<RecentPerformancePost> = {},
): RecentPerformancePost {
  return {
    ...dashboardFixture.filterablePosts[0],
    latestMetricDate: "2026-09-17",
    ...overrides,
  };
}
function show(
  posts: RecentPerformancePost[],
  partialErrors: RecentPerformanceData["partialErrors"] = [],
) {
  return render(
    <RecentPerformanceView data={{ posts, partialErrors }} now={now} />,
  );
}
function metric(article: HTMLElement, label: string) {
  return within(article).getByText(label).parentElement?.querySelector("dd");
}

describe("RecentPerformanceView", () => {
  it("orders by publication time, not views, and keeps each platform post separate", () => {
    const posts = [
      post({
        key: "older",
        publishedAt: "2026-09-15T18:00:00Z",
        views: 999999,
      }),
      post({
        key: "newer",
        platform: "youtube",
        publishedAt: "2026-09-16T18:00:00Z",
        views: 12345,
      }),
    ];
    show(posts);
    const articles = screen.getAllByRole("article");
    expect(articles).toHaveLength(2);
    expect(articles[0]).toHaveAccessibleName("youtube: Sample Clip Alpha");
    expect(metric(articles[0], "Views")).toHaveTextContent("12,345");
    expect(articles[1]).toHaveAccessibleName("tiktok: Sample Clip Alpha");
    expect(posts.map((item) => item.key)).toEqual(["older", "newer"]);
  });

  it("shows individual metrics, labeling details, dates and a safe original-post link", () => {
    show([
      post({
        reactions: 1234,
        comments: 78,
        shares: 56,
        saves: 34,
        interactionRate: 8.765,
      }),
    ]);
    const article = screen.getByRole("article");
    for (const [label, value] of [
      ["Likes / reactions", "1,234"],
      ["Comments", "78"],
      ["Shares", "56"],
      ["Saves", "34"],
      ["Interaction rate", "8.77%"],
    ]) {
      expect(metric(article, label)).toHaveTextContent(value);
    }
    expect(within(article).getByText("Sample Game")).toBeVisible();
    expect(within(article).getByText("Highlight")).toBeVisible();
    expect(within(article).getByText("2026-09-17")).toHaveAttribute(
      "datetime",
      "2026-09-17",
    );
    expect(
      within(article).getByRole("link", { name: /Open tiktok post/ }),
    ).toHaveAttribute("href", "https://example.invalid/posts/sample-one");
    expect(within(article).getByRole("link")).toHaveAttribute(
      "rel",
      "noreferrer",
    );
  });

  it("distinguishes missing values from measured zero and missing dates from stale dates", () => {
    show([
      post({
        key: "unknown",
        clipGroup: "Missing metrics",
        latestMetricDate: null,
        views: null,
        reactions: null,
        comments: 0,
        shares: null,
        saves: 0,
        interactionRate: null,
        externalLink: null,
      }),
      post({
        key: "stale",
        clipGroup: "Older metrics",
        latestMetricDate: "2026-09-13",
      }),
    ]);
    const article = screen.getByRole("article", {
      name: "tiktok: Missing metrics",
    });
    expect(metric(article, "Views")).toHaveTextContent("—");
    expect(metric(article, "Likes / reactions")).toHaveTextContent("—");
    expect(metric(article, "Comments")).toHaveTextContent("0");
    expect(metric(article, "Shares")).toHaveTextContent("—");
    expect(metric(article, "Saves")).toHaveTextContent("0");
    expect(metric(article, "Interaction rate")).toHaveTextContent("—");
    expect(within(article).queryByRole("link")).not.toBeInTheDocument();
    expect(within(article).getByText("Metrics date unavailable")).toBeVisible();
    expect(
      within(
        screen.getByRole("article", { name: "tiktok: Older metrics" }),
      ).getByText("Metrics may be out of date"),
    ).toBeVisible();
  });

  it("filters platform and game without changing the source data", async () => {
    const user = userEvent.setup();
    show([
      post({ key: "one" }),
      post({ key: "two", platform: "youtube" }),
      post({ key: "three", platform: "youtube", game: "Other Game" }),
    ]);
    await user.selectOptions(screen.getByLabelText("Platform"), "youtube");
    expect(screen.getAllByRole("article")).toHaveLength(2);
    await user.selectOptions(screen.getByLabelText("Game"), "Other Game");
    expect(screen.getAllByRole("article")).toHaveLength(1);
    expect(
      within(screen.getByRole("article")).getByText("Other Game"),
    ).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Clear" }));
    expect(screen.getAllByRole("article")).toHaveLength(3);
  });

  it("uses inclusive Denver publication dates and excludes invalid or missing dates when filtering", () => {
    show([
      post({ key: "outside", publishedAt: "2026-09-17T06:00:00Z" }),
      post({
        key: "inside",
        publishedAt: "2026-09-17T05:59:00Z",
        clipGroup: "Late-night clip",
      }),
      post({ key: "missing", publishedAt: null }),
      post({ key: "invalid", publishedAt: "not a date" }),
    ]);
    expect(screen.getAllByText("Publication time unavailable")).toHaveLength(2);
    fireEvent.change(screen.getByLabelText("From date"), {
      target: { value: "2026-09-16" },
    });
    fireEvent.change(screen.getByLabelText("Through date"), {
      target: { value: "2026-09-16" },
    });
    expect(screen.getAllByRole("article")).toHaveLength(1);
    expect(screen.getByRole("article")).toHaveAccessibleName(
      "tiktok: Late-night clip",
    );
    fireEvent.change(screen.getByLabelText("From date"), {
      target: { value: "2026-09-15" },
    });
    fireEvent.change(screen.getByLabelText("Through date"), {
      target: { value: "2026-09-15" },
    });
    expect(screen.getByText("No posts match these filters")).toBeVisible();
  });

  it("paginates and resets to the first page when filters change", async () => {
    const user = userEvent.setup();
    show(
      Array.from({ length: 12 }, (_, index) =>
        post({
          key: String(index).padStart(2, "0"),
          clipGroup: `Clip ${index}`,
          platform: index < 11 ? "tiktok" : "youtube",
        }),
      ),
    );
    expect(screen.getAllByRole("article")).toHaveLength(10);
    expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
    await user.click(screen.getByRole("button", { name: "Next" }));
    expect(screen.getAllByRole("article")).toHaveLength(2);
    expect(screen.getByText("Page 2 of 2")).toBeVisible();
    expect(screen.getByRole("button", { name: "Next" })).toBeDisabled();
    await user.selectOptions(screen.getByLabelText("Platform"), "tiktok");
    expect(screen.getAllByRole("article")).toHaveLength(10);
    expect(screen.getByText("Page 1 of 2")).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Next" }));
    await user.click(screen.getByRole("button", { name: "Previous" }));
    expect(screen.getByText("Page 1 of 2")).toBeVisible();
  });

  it("keeps load failure distinct from an empty result", () => {
    const view = show(
      [],
      [
        {
          section: "Post performance",
          message: "Post performance is temporarily unavailable.",
        },
      ],
    );
    expect(
      screen.getByText("Post performance is temporarily unavailable."),
    ).toBeVisible();
    expect(
      screen.queryByText("No published posts yet"),
    ).not.toBeInTheDocument();
    expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
    view.rerender(
      <RecentPerformanceView
        data={{ posts: [], partialErrors: [] }}
        now={now}
      />,
    );
    expect(screen.getByText("No published posts yet")).toBeVisible();
  });
});
