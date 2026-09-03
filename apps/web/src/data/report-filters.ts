import type { ReportingPost } from "@/data/models";
import { DEFAULT_DISPLAY_TIMEZONE, localDateKey } from "@/lib/format";

export type ReportFilterValue = {
  platform: string;
  game: string;
  dateFrom: string;
  dateTo: string;
};

export const EMPTY_REPORT_FILTERS: ReportFilterValue = {
  platform: "",
  game: "",
  dateFrom: "",
  dateTo: "",
};

export function reportFilterOptions(posts: readonly ReportingPost[]) {
  const unique = (values: (string | null)[]) =>
    Array.from(
      new Set(values.filter((value): value is string => Boolean(value))),
    ).sort((left, right) => left.localeCompare(right));

  return {
    platforms: unique(posts.map((post) => post.platform)),
    games: unique(posts.map((post) => post.game)),
  };
}

export function filterReportingPosts(
  posts: readonly ReportingPost[],
  filters: ReportFilterValue,
  timezone = DEFAULT_DISPLAY_TIMEZONE,
): ReportingPost[] {
  return posts.filter((post) => {
    if (filters.platform && post.platform !== filters.platform) return false;
    if (filters.game && post.game !== filters.game) return false;

    if (!filters.dateFrom && !filters.dateTo) return true;
    if (!post.publishedAt) return false;

    const publishedDate = localDateKey(post.publishedAt, timezone);
    if (filters.dateFrom && publishedDate < filters.dateFrom) return false;
    if (filters.dateTo && publishedDate > filters.dateTo) return false;
    return true;
  });
}

export function hasActiveReportFilters(filters: ReportFilterValue): boolean {
  return Object.values(filters).some(Boolean);
}
