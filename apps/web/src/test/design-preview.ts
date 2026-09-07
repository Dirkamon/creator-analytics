import { dashboardFixture } from "@/test/fixtures";
import type { DashboardData } from "@/data/models";

const captions = [
  "The squad had a plan. It lasted about three seconds.",
  "One heart left and absolutely no backup plan",
  "That teammate who turns every round into a highlight",
  "A quiet day in RLCraft. Famous last words.",
  "The clutch nobody saw coming",
  "When the game decides you have had enough fun",
];

// Fictional, local-only sample content for visual review.
export const previewDashboard: DashboardData = {
  ...dashboardFixture,
  filterablePosts: Array.from({ length: 12 }, (_, index) => ({
    ...dashboardFixture.filterablePosts[index % 2],
    key: `DESIGN_SAMPLE_${index}`,
    caption: captions[index % captions.length],
    externalLink: null,
    game: index % 3 === 0 ? "Rainbow Six Siege" : "RLCraft",
    contentType: index % 3 === 0 ? "Highlight" : "Funny Moment",
    vibe: "Chaotic",
    clipGroup: `Sample clip ${Math.floor(index / 2) + 1}`,
    labelStatus: "labeled",
    publishedAt: `2026-09-${String(6 - Math.floor(index / 2)).padStart(2, "0")}T20:00:00Z`,
    publishDay: [
      "Sunday",
      "Saturday",
      "Friday",
      "Thursday",
      "Wednesday",
      "Tuesday",
    ][Math.floor(index / 2)],
    publishHour: 14,
    views: 3600 + index * 320,
    reactions: 230 + index * 9,
    comments: 20 + index * 2,
    shares: 12 + index,
    saves: 0,
    interactionRate: ((262 + index * 12) / (3600 + index * 320)) * 100,
  })),
  growth: [
    { platform: "tiktok", capturedOn: "2026-09-06", viewsGained: 4200 },
    { platform: "youtube", capturedOn: "2026-09-06", viewsGained: 2800 },
    { platform: "tiktok", capturedOn: "2026-09-05", viewsGained: 3100 },
    { platform: "youtube", capturedOn: "2026-09-05", viewsGained: 2350 },
    { platform: "tiktok", capturedOn: "2026-09-04", viewsGained: 3600 },
    { platform: "youtube", capturedOn: "2026-09-04", viewsGained: 1950 },
  ],
  latestMetricDate: "2026-09-06",
};
