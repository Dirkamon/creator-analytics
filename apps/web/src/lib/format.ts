export const DEFAULT_DISPLAY_TIMEZONE = "America/Denver";

export function formatCompactNumber(value: number): string {
  return new Intl.NumberFormat("en-US", {
    notation: value >= 10_000 ? "compact" : "standard",
    maximumFractionDigits: value >= 10_000 ? 1 : 0,
  }).format(value);
}

export function formatPercentage(value: number | null): string {
  if (value === null) return "—";
  return `${new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 }).format(value)}%`;
}

export function formatDateTime(
  value: string | Date,
  timezone = DEFAULT_DISPLAY_TIMEZONE,
): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZoneName: "short",
  }).format(new Date(value));
}

export function formatDate(
  value: string | Date,
  timezone = DEFAULT_DISPLAY_TIMEZONE,
): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    weekday: "long",
    month: "long",
    day: "numeric",
  }).format(new Date(value));
}

export function formatShortDate(
  value: string | Date,
  timezone = DEFAULT_DISPLAY_TIMEZONE,
): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    month: "short",
    day: "numeric",
  }).format(new Date(value));
}

export function formatHour(hour: number): string {
  const normalized = ((hour % 24) + 24) % 24;
  const suffix = normalized >= 12 ? "PM" : "AM";
  const display = normalized % 12 || 12;
  return `${display}:00 ${suffix}`;
}

export function localDateKey(
  value: string | Date,
  timezone = DEFAULT_DISPLAY_TIMEZONE,
): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(value));
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((item) => item.type === type)?.value ?? "";
  return `${part("year")}-${part("month")}-${part("day")}`;
}

export function sanitizeExternalUrl(value: string | null): string | null {
  if (!value) return null;

  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:"
      ? url.toString()
      : null;
  } catch {
    return null;
  }
}

export function isCalendarDateStale(options: {
  value: string;
  now: Date;
  maxAgeDays: number;
  timezone?: string;
}): boolean {
  const timezone = options.timezone ?? DEFAULT_DISPLAY_TIMEZONE;
  const valueDate = Date.parse(`${options.value.slice(0, 10)}T00:00:00Z`);
  const currentDate = Date.parse(
    `${localDateKey(options.now, timezone)}T00:00:00Z`,
  );
  return currentDate - valueDate > options.maxAgeDays * 86_400_000;
}
