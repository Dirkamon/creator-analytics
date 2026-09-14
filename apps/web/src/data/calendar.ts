import type { PartialDataError } from "@/data/models";
import { localDateKey } from "@/lib/format";

export type CalendarPost = {
  key: string;
  title: string;
  caption: string;
  platform: string;
  channel: string | null;
  at: string;
  status: "scheduled" | "published";
  externalLink: string | null;
};

export type CalendarData = {
  month: string;
  today: string;
  posts: CalendarPost[];
  partialErrors: PartialDataError[];
};

export function isCalendarMonth(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^(19\d{2}|20\d{2}|2100)-(0[1-9]|1[0-2])$/.test(value)
  );
}

export function calendarMonth(value: unknown, now = new Date()): string {
  return isCalendarMonth(value) ? value : localDateKey(now).slice(0, 7);
}

export function shiftMonth(month: string, offset: number): string {
  const [year, number] = month.split("-").map(Number);
  return new Date(Date.UTC(year, number - 1 + offset, 1))
    .toISOString()
    .slice(0, 7);
}

export function monthCells(month: string): (string | null)[] {
  const [year, number] = month.split("-").map(Number);
  const offset = new Date(Date.UTC(year, number - 1, 1)).getUTCDay();
  const days = new Date(Date.UTC(year, number, 0)).getUTCDate();
  return Array.from(
    { length: Math.ceil((offset + days) / 7) * 7 },
    (_, index) => {
      const day = index - offset + 1;
      return day >= 1 && day <= days
        ? `${month}-${String(day).padStart(2, "0")}`
        : null;
    },
  );
}

// These are calendar labels, not instants in the user's timezone.
export function calendarDateLabel(date: string, monthOnly = false): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "UTC",
    year: "numeric",
    month: "long",
    ...(monthOnly ? {} : { weekday: "long" as const, day: "numeric" as const }),
  }).format(new Date(`${date.length === 7 ? `${date}-01` : date}T12:00:00Z`));
}

export function postsByDay(
  posts: readonly CalendarPost[],
): Map<string, CalendarPost[]> {
  const groups = new Map<string, CalendarPost[]>();
  for (const post of [...posts].sort(
    (a, b) => Date.parse(a.at) - Date.parse(b.at) || a.key.localeCompare(b.key),
  )) {
    const date = localDateKey(post.at);
    groups.set(date, [...(groups.get(date) ?? []), post]);
  }
  return groups;
}

export function calendarQueryBounds(month: string) {
  if (!isCalendarMonth(month)) throw new Error("Invalid calendar month");
  // Read a one-day UTC margin, then group/filter by America/Denver. This
  // includes month edges during both standard time and daylight saving time.
  const first = Date.parse(`${month}-01T00:00:00Z`);
  const next = Date.parse(`${shiftMonth(month, 1)}-01T00:00:00Z`);
  return {
    from: new Date(first - 86_400_000).toISOString(),
    through: new Date(next + 86_400_000).toISOString(),
  };
}
