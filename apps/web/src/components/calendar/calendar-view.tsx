"use client";

import { useRef, useState, type KeyboardEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowUpRight, ChevronLeft, ChevronRight } from "lucide-react";
import { PartialErrorState } from "@/components/states/feedback-states";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/page-header";
import {
  calendarDateLabel,
  isCalendarMonth,
  monthCells,
  postsByDay,
  shiftMonth,
  type CalendarData,
} from "@/data/calendar";
import { DEFAULT_DISPLAY_TIMEZONE, formatDateTime } from "@/lib/format";

const weekdays = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];
const control =
  "border-line bg-surface text-secondary hover:bg-surface-raised inline-flex min-h-11 items-center justify-center rounded-xl border px-3 text-sm font-medium transition";

export function CalendarView({
  data,
  preview = false,
}: {
  data: CalendarData;
  preview?: boolean;
}) {
  const router = useRouter();
  const [selected, setSelected] = useState(
    data.today.startsWith(data.month) ? data.today : `${data.month}-01`,
  );
  const dayButtons = useRef(new Map<string, HTMLButtonElement>());
  const detailsPanel = useRef<HTMLElement>(null);
  const groups = postsByDay(data.posts);
  const cells = monthCells(data.month);
  const rows = Array.from({ length: cells.length / 7 }, (_, index) =>
    cells.slice(index * 7, index * 7 + 7),
  );
  const selectedPosts = groups.get(selected) ?? [];
  const incomplete = data.partialErrors.length > 0;
  const monthName = calendarDateLabel(data.month, true);
  const monthHref = (month: string) =>
    preview
      ? `/design-preview?view=calendar&month=${month}`
      : `/calendar?month=${month}`;
  const previous = shiftMonth(data.month, -1);
  const next = shiftMonth(data.month, 1);
  const scheduledCount = data.posts.filter(
    (post) => post.status === "scheduled",
  ).length;
  const publishedCount = data.posts.length - scheduledCount;

  function handleDayKey(event: KeyboardEvent<HTMLButtonElement>, date: string) {
    const day = Number(date.slice(-2));
    const shifts: Record<string, number> = {
      ArrowLeft: -1,
      ArrowRight: 1,
      ArrowUp: -7,
      ArrowDown: 7,
    };
    const offset = shifts[event.key];
    if (offset === undefined) return;
    const nextDate = `${data.month}-${String(day + offset).padStart(2, "0")}`;
    const target = dayButtons.current.get(nextDate);
    event.preventDefault();
    if (target) {
      setSelected(nextDate);
      target.focus();
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Calendar"
        eyebrow="Your publishing month"
        description="See what’s going out, spot open days, and look back at published posts."
        aside={<Badge tone="info">{DEFAULT_DISPLAY_TIMEZONE}</Badge>}
      />
      <PartialErrorState errors={data.partialErrors} />

      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2
            id="calendar-month"
            className="text-foreground text-2xl font-semibold tracking-tight"
          >
            {monthName}
          </h2>
          <p className="text-muted mt-1 text-sm" aria-live="polite">
            {data.posts.length}{" "}
            {incomplete
              ? "loaded posts · counts incomplete"
              : `posts · ${scheduledCount} scheduled · ${publishedCount} published`}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <label className="sr-only" htmlFor="calendar-month-picker">
            Go to month
          </label>
          <input
            id="calendar-month-picker"
            type="month"
            min="1900-01"
            max="2100-12"
            value={data.month}
            className={`${control} max-w-44`}
            onChange={(event) => {
              if (isCalendarMonth(event.target.value))
                router.push(monthHref(event.target.value));
            }}
          />
          <Link
            href={monthHref(data.today.slice(0, 7))}
            className={control}
            onClick={() => setSelected(data.today)}
          >
            Today
          </Link>
          {isCalendarMonth(previous) && (
            <Link
              href={monthHref(previous)}
              aria-label="Previous month"
              className={control}
            >
              <ChevronLeft aria-hidden size={19} />
            </Link>
          )}
          {isCalendarMonth(next) && (
            <Link
              href={monthHref(next)}
              aria-label="Next month"
              className={control}
            >
              <ChevronRight aria-hidden size={19} />
            </Link>
          )}
        </div>
      </div>

      <div className="grid items-start gap-5 2xl:grid-cols-[minmax(0,1fr)_22rem]">
        <div className="min-w-0">
          <div className="border-line bg-surface overflow-hidden rounded-2xl border">
            <table
              className="w-full table-fixed border-collapse"
              aria-labelledby="calendar-month"
            >
              <thead>
                <tr>
                  {weekdays.map((day) => (
                    <th
                      key={day}
                      scope="col"
                      className="border-line text-muted border-b py-3 text-center text-xs font-medium sm:text-sm"
                    >
                      <abbr title={day} className="no-underline">
                        {day.slice(0, 3)}
                      </abbr>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((week, rowIndex) => (
                  <tr key={rowIndex}>
                    {week.map((date, columnIndex) => {
                      const posts = date ? (groups.get(date) ?? []) : [];
                      const active = date === selected;
                      const today = date === data.today;
                      return (
                        <td
                          key={date ?? `blank-${columnIndex}`}
                          className="border-line border-r border-b p-0 align-top last:border-r-0"
                        >
                          {date ? (
                            <button
                              type="button"
                              ref={(node) => {
                                if (node) dayButtons.current.set(date, node);
                                else dayButtons.current.delete(date);
                              }}
                              aria-label={`${calendarDateLabel(date)}: ${posts.length} ${incomplete ? "loaded " : ""}${posts.length === 1 ? "post" : "posts"}${incomplete ? "; counts incomplete" : ""}`}
                              aria-pressed={active}
                              aria-current={today ? "date" : undefined}
                              aria-controls="calendar-day-details"
                              onClick={() => {
                                setSelected(date);
                                if (
                                  window.matchMedia?.("(max-width: 1535px)")
                                    .matches
                                ) {
                                  detailsPanel.current?.scrollIntoView({
                                    block: "start",
                                  });
                                }
                              }}
                              onKeyDown={(event) => handleDayKey(event, date)}
                              className={`relative flex min-h-24 w-full flex-col p-1.5 text-left transition sm:min-h-36 sm:p-3 ${active ? "bg-accent/10 ring-accent ring-2 ring-inset" : "hover:bg-surface-raised"}`}
                            >
                              <span className="flex w-full flex-wrap items-center justify-between gap-1">
                                <span
                                  className={`inline-flex size-7 items-center justify-center rounded-full text-sm font-semibold ${today ? "bg-accent-solid text-on-accent" : "text-foreground"}`}
                                >
                                  {Number(date.slice(-2))}
                                </span>
                                {posts.length > 0 && (
                                  <span className="text-accent bg-accent/10 rounded-md px-1.5 py-0.5 text-xs font-semibold">
                                    {posts.length}
                                    <span className="sr-only"> posts</span>
                                  </span>
                                )}
                              </span>
                              <span
                                aria-hidden
                                className="mt-2 hidden w-full space-y-1.5 md:block"
                              >
                                {posts.slice(0, 2).map((post) => (
                                  <span
                                    key={post.key}
                                    className={`block truncate rounded-md border-l-2 px-1.5 py-1 text-xs ${post.status === "scheduled" ? "border-accent bg-accent/10 text-accent" : "border-success bg-success/10 text-success"}`}
                                    title={`${post.title} · ${post.platform}`}
                                  >
                                    {post.title}
                                  </span>
                                ))}
                                {posts.length > 2 && (
                                  <span className="text-muted block text-xs">
                                    +{posts.length - 2} more
                                  </span>
                                )}
                              </span>
                              {posts.length > 0 && (
                                <span
                                  aria-hidden
                                  className="mt-2 flex flex-wrap gap-1 md:hidden"
                                >
                                  {posts.slice(0, 4).map((post) => (
                                    <span
                                      key={post.key}
                                      className={`size-1.5 rounded-full ${post.status === "scheduled" ? "bg-accent" : "bg-success"}`}
                                    />
                                  ))}
                                </span>
                              )}
                            </button>
                          ) : (
                            <div
                              aria-hidden
                              className="bg-canvas/70 min-h-24 sm:min-h-36"
                            />
                          )}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="text-muted mt-3 flex flex-wrap items-center gap-x-5 gap-y-2 text-sm">
            <span className="inline-flex items-center gap-2">
              <span className="bg-accent size-2 rounded-full" />
              Scheduled
            </span>
            <span className="inline-flex items-center gap-2">
              <span className="bg-success size-2 rounded-full" />
              Published
            </span>
            <span>Select a day to see every post.</span>
          </div>
          <p className="text-muted mt-3 text-xs leading-5">
            Based on the latest synchronized data, not a live Buffer check.
            Pending proposals don’t move posts here. Each platform post counts
            separately.
          </p>
        </div>

        <section
          id="calendar-day-details"
          ref={detailsPanel}
          aria-labelledby="calendar-day-heading"
          className="border-line bg-surface min-w-0 scroll-mt-48 rounded-2xl border p-5 sm:p-6"
          aria-live="polite"
        >
          <p className="text-accent text-xs font-semibold tracking-widest uppercase">
            Day details
          </p>
          <h2
            id="calendar-day-heading"
            className="text-foreground mt-2 text-xl font-semibold"
          >
            {calendarDateLabel(selected)}
          </h2>
          <p className="text-muted mt-1 text-sm">
            {selectedPosts.length}{" "}
            {incomplete
              ? "loaded posts · counts incomplete"
              : selectedPosts.length === 1
                ? "post"
                : "posts"}
          </p>
          {selectedPosts.length === 0 ? (
            <p className="text-muted mt-6 text-sm leading-6">
              {incomplete
                ? "Some post data is unavailable. Refresh before treating this as an open day."
                : "No scheduled or published posts on this day in the synchronized data."}
            </p>
          ) : (
            <div className="mt-5 space-y-4">
              {selectedPosts.map((post) => (
                <article
                  key={post.key}
                  className="border-line rounded-xl border p-4"
                >
                  <div className="flex flex-wrap gap-2">
                    <Badge
                      tone={post.status === "scheduled" ? "info" : "positive"}
                    >
                      {post.status === "scheduled" ? "Scheduled" : "Published"}
                    </Badge>
                    <Badge>{post.platform}</Badge>
                  </div>
                  <h3 className="text-foreground mt-3 text-base font-semibold break-words">
                    {post.title}
                  </h3>
                  <p className="text-secondary mt-2 text-sm">
                    {formatDateTime(post.at)}
                  </p>
                  {post.channel && (
                    <p className="text-muted mt-1 text-sm break-words">
                      {post.channel}
                    </p>
                  )}
                  {post.caption !== post.title && (
                    <p className="text-muted mt-3 text-sm leading-6 break-words">
                      {post.caption}
                    </p>
                  )}
                  {post.externalLink && (
                    <a
                      href={post.externalLink}
                      target="_blank"
                      rel="noreferrer"
                      className="text-accent mt-3 inline-flex min-h-11 items-center gap-1 text-sm font-medium"
                    >
                      Open post
                      <ArrowUpRight aria-hidden size={16} />
                    </a>
                  )}
                </article>
              ))}
            </div>
          )}
        </section>
      </div>
    </div>
  );
}
