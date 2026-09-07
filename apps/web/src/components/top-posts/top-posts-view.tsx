"use client";

import {
  ArrowDown,
  ArrowUp,
  ArrowUpRight,
  ChevronLeft,
  ChevronRight,
} from "lucide-react";
import { useMemo, useState } from "react";

import { ReportFilters } from "@/components/reporting/report-filters";
import {
  EmptyState,
  PartialErrorState,
} from "@/components/states/feedback-states";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/page-header";
import { PlatformBadge } from "@/components/ui/platform-badge";
import type { ReportingPost, TopPostsData } from "@/data/models";
import {
  EMPTY_REPORT_FILTERS,
  filterReportingPosts,
  reportFilterOptions,
} from "@/data/report-filters";
import {
  DEFAULT_DISPLAY_TIMEZONE,
  formatCompactNumber,
  formatDateTime,
  formatPercentage,
} from "@/lib/format";

type SortKey =
  | "publishedAt"
  | "views"
  | "reactions"
  | "comments"
  | "shares"
  | "interactionRate";

const PAGE_SIZE = 25;

function numberValue(post: ReportingPost, key: SortKey): number {
  if (key === "publishedAt") {
    return post.publishedAt ? Date.parse(post.publishedAt) : -Infinity;
  }
  return post[key] ?? -Infinity;
}

function SortButton({
  active,
  direction,
  label,
  onClick,
}: {
  active: boolean;
  direction: "ascending" | "descending";
  label: string;
  onClick: () => void;
}) {
  const Icon = direction === "ascending" ? ArrowUp : ArrowDown;

  return (
    <button
      aria-label={`Sort by ${label}`}
      className={`inline-flex items-center gap-1 font-semibold transition ${active ? "text-accent" : "text-muted hover:text-foreground"}`}
      onClick={onClick}
      type="button"
    >
      {label}
      {active && <Icon aria-hidden size={13} />}
    </button>
  );
}

export function TopPostsView({ data }: { data: TopPostsData }) {
  const [filters, setFilters] = useState(EMPTY_REPORT_FILTERS);
  const [sortKey, setSortKey] = useState<SortKey>("views");
  const [direction, setDirection] = useState<"ascending" | "descending">(
    "descending",
  );
  const [page, setPage] = useState(1);
  const options = useMemo(() => reportFilterOptions(data.posts), [data.posts]);
  const filteredPosts = useMemo(
    () => filterReportingPosts(data.posts, filters),
    [data.posts, filters],
  );
  const sortedPosts = useMemo(
    () =>
      [...filteredPosts].sort((left, right) => {
        const comparison =
          numberValue(left, sortKey) - numberValue(right, sortKey);
        return direction === "ascending" ? comparison : -comparison;
      }),
    [direction, filteredPosts, sortKey],
  );
  const pageCount = Math.max(1, Math.ceil(sortedPosts.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const visiblePosts = sortedPosts.slice(
    (safePage - 1) * PAGE_SIZE,
    safePage * PAGE_SIZE,
  );

  const changeSort = (nextKey: SortKey) => {
    if (sortKey === nextKey) {
      setDirection((current) =>
        current === "ascending" ? "descending" : "ascending",
      );
    } else {
      setSortKey(nextKey);
      setDirection("descending");
    }
    setPage(1);
  };

  return (
    <div className="space-y-7">
      <PageHeader
        aside={<Badge tone="info">{DEFAULT_DISPLAY_TIMEZONE}</Badge>}
        description="All sent posts from the reporting view, sortable by performance and filterable without changing source data."
        eyebrow="Performance ranking"
        title="Top Posts"
      />

      <PartialErrorState errors={data.partialErrors} />

      {data.posts.length === 0 ? (
        <EmptyState title="No post performance is available">
          The reporting view returned no sent posts.
        </EmptyState>
      ) : (
        <>
          <ReportFilters
            games={options.games}
            onChange={(nextFilters) => {
              setFilters(nextFilters);
              setPage(1);
            }}
            platforms={options.platforms}
            value={filters}
          />

          <section className="border-line bg-surface overflow-hidden rounded-2xl border">
            <div className="border-line flex flex-col gap-2 border-b px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 className="text-foreground font-semibold">
                  Performance table
                </h2>
                <p className="text-muted mt-1 text-xs">
                  {formatCompactNumber(sortedPosts.length)} matching posts · 25
                  per page
                </p>
              </div>
              <p className="text-muted text-xs">
                Page {safePage} of {pageCount}
              </p>
            </div>

            {visiblePosts.length === 0 ? (
              <div className="p-5">
                <EmptyState title="No posts match these filters">
                  Clear or broaden the filters to see reporting results.
                </EmptyState>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[76rem] border-collapse text-left text-sm">
                  <thead className="bg-foreground/[0.025] text-muted text-xs tracking-wide uppercase">
                    <tr>
                      <th className="px-5 py-3 font-semibold">Post</th>
                      <th className="px-4 py-3 font-semibold">Platform</th>
                      <th className="px-4 py-3 font-semibold">Game</th>
                      <th className="px-4 py-3">
                        <SortButton
                          active={sortKey === "publishedAt"}
                          direction={direction}
                          label="Published"
                          onClick={() => changeSort("publishedAt")}
                        />
                      </th>
                      <th className="px-4 py-3 text-right">
                        <SortButton
                          active={sortKey === "views"}
                          direction={direction}
                          label="Views"
                          onClick={() => changeSort("views")}
                        />
                      </th>
                      <th className="px-4 py-3 text-right">
                        <SortButton
                          active={sortKey === "reactions"}
                          direction={direction}
                          label="Reactions"
                          onClick={() => changeSort("reactions")}
                        />
                      </th>
                      <th className="px-4 py-3 text-right">
                        <SortButton
                          active={sortKey === "comments"}
                          direction={direction}
                          label="Comments"
                          onClick={() => changeSort("comments")}
                        />
                      </th>
                      <th className="px-4 py-3 text-right">
                        <SortButton
                          active={sortKey === "shares"}
                          direction={direction}
                          label="Shares"
                          onClick={() => changeSort("shares")}
                        />
                      </th>
                      <th className="px-4 py-3 text-right">
                        <SortButton
                          active={sortKey === "interactionRate"}
                          direction={direction}
                          label="Interaction rate"
                          onClick={() => changeSort("interactionRate")}
                        />
                      </th>
                      <th className="px-4 py-3">
                        <span className="sr-only">Open post</span>
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-line divide-y">
                    {visiblePosts.map((post) => (
                      <tr
                        className="hover:bg-foreground/[0.025] align-top transition"
                        key={post.key}
                      >
                        <td className="max-w-md px-5 py-4">
                          <p className="text-secondary line-clamp-2 leading-6">
                            {post.caption}
                          </p>
                          <p className="text-muted mt-1 text-xs">
                            {post.clipGroup ?? "Unlabeled clip"}
                          </p>
                        </td>
                        <td className="px-4 py-4">
                          <PlatformBadge platform={post.platform} />
                        </td>
                        <td className="text-muted px-4 py-4">
                          {post.game ?? "—"}
                        </td>
                        <td className="text-muted px-4 py-4 whitespace-nowrap">
                          {post.publishedAt
                            ? formatDateTime(post.publishedAt)
                            : "—"}
                        </td>
                        <td className="text-foreground px-4 py-4 text-right font-semibold">
                          {post.views === null
                            ? "—"
                            : formatCompactNumber(post.views)}
                        </td>
                        <td className="text-secondary px-4 py-4 text-right">
                          {formatCompactNumber(post.reactions)}
                        </td>
                        <td className="text-secondary px-4 py-4 text-right">
                          {formatCompactNumber(post.comments)}
                        </td>
                        <td className="text-secondary px-4 py-4 text-right">
                          {formatCompactNumber(post.shares)}
                        </td>
                        <td className="text-accent px-4 py-4 text-right">
                          {formatPercentage(post.interactionRate)}
                        </td>
                        <td className="px-4 py-4">
                          {post.externalLink && (
                            <a
                              aria-label={`Open ${post.platform} post`}
                              className="border-line text-muted hover:border-accent/30 hover:text-accent inline-flex rounded-lg border p-2 transition"
                              href={post.externalLink}
                              rel="noreferrer"
                              target="_blank"
                            >
                              <ArrowUpRight aria-hidden size={15} />
                            </a>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            <div className="border-line flex items-center justify-between gap-4 border-t px-5 py-4">
              <button
                className="border-line text-secondary hover:border-accent/30 hover:text-foreground inline-flex items-center gap-2 rounded-xl border px-3 py-2 text-sm font-medium transition disabled:cursor-not-allowed disabled:opacity-40"
                disabled={safePage <= 1}
                onClick={() => setPage((current) => Math.max(1, current - 1))}
                type="button"
              >
                <ChevronLeft aria-hidden size={16} /> Previous
              </button>
              <span className="text-muted text-xs">
                Showing{" "}
                {visiblePosts.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1}
                –{Math.min(safePage * PAGE_SIZE, sortedPosts.length)} of{" "}
                {sortedPosts.length}
              </span>
              <button
                className="border-line text-secondary hover:border-accent/30 hover:text-foreground inline-flex items-center gap-2 rounded-xl border px-3 py-2 text-sm font-medium transition disabled:cursor-not-allowed disabled:opacity-40"
                disabled={safePage >= pageCount}
                onClick={() =>
                  setPage((current) => Math.min(pageCount, current + 1))
                }
                type="button"
              >
                Next <ChevronRight aria-hidden size={16} />
              </button>
            </div>
          </section>
        </>
      )}
    </div>
  );
}
