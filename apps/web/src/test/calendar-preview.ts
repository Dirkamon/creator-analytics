import {
  calendarMonth,
  type CalendarData,
  type CalendarPost,
} from "@/data/calendar";

export function calendarPreview(month?: string): CalendarData {
  const titles = [
    "Castle Circuit — perfect finish",
    "Nebula Raiders — squad chaos",
    "Rift Racers — last-second win",
  ];
  const posts: CalendarPost[] = [2, 4, 6, 11, 12, 13, 14, 18, 25].flatMap(
    (day, index) =>
      ["tiktok", "youtube"].map((platform, platformIndex) => ({
        key: `sample-${day}-${platform}`,
        title: titles[index % titles.length],
        caption: `Fictional sample clip ${index + 1} for the calendar preview.`,
        platform,
        channel: `Demo ${platform}`,
        at: `2026-09-${String(day).padStart(2, "0")}T${platformIndex ? "23" : "16"}:00:00Z`,
        status: day <= 6 ? ("published" as const) : ("scheduled" as const),
        externalLink: null,
      })),
  );
  const selectedMonth = calendarMonth(month, new Date("2026-09-07T02:00:00Z"));
  return {
    month: selectedMonth,
    today: "2026-09-06",
    posts: selectedMonth === "2026-09" ? posts : [],
    partialErrors: [],
  };
}
