import { PlatformBadge } from "@/components/ui/platform-badge";
import {
  EmptyState,
  PartialErrorState,
  StaleNotice,
} from "@/components/states/feedback-states";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/page-header";
import { SectionCard } from "@/components/ui/section-card";
import type { AnalyticsData } from "@/data/models";
import {
  DEFAULT_DISPLAY_TIMEZONE,
  formatCompactNumber,
  formatDateTime,
  formatHour,
  formatPercentage,
} from "@/lib/format";

function freshnessTone(status: string) {
  if (status.toLowerCase() === "fresh") return "positive" as const;
  if (status.toLowerCase() === "stale") return "danger" as const;
  return "warning" as const;
}

function hasAnalyticsRows(data: AnalyticsData): boolean {
  return [
    data.contentPerformance,
    data.postingWindows,
    data.recommendations,
    data.fallbackSelections,
    data.cadenceSettings,
    data.weeklySlots,
  ].some((rows) => rows.length > 0);
}

function platforms(data: AnalyticsData): string[] {
  return Array.from(
    new Set([
      ...data.contentPerformance.map((row) => row.platform),
      ...data.postingWindows.map((row) => row.platform),
      ...data.recommendations.map((row) => row.platform),
      ...data.fallbackSelections.map((row) => row.platform),
      ...data.cadenceSettings.map((row) => row.platform),
      ...data.weeklySlots.map((row) => row.platform),
    ]),
  ).sort((left, right) => left.localeCompare(right));
}

export function AnalyticsView({ data }: { data: AnalyticsData }) {
  const observedPlatforms = platforms(data);
  const staleRecommendations = data.recommendations.some(
    (row) => row.metricsStatus.toLowerCase() !== "fresh",
  );

  return (
    <div className="space-y-7">
      <PageHeader
        aside={
          <div className="flex flex-wrap gap-2">
            <Badge tone="info">Database-computed</Badge>
            <Badge>{DEFAULT_DISPLAY_TIMEZONE}</Badge>
          </div>
        }
        description={`Content performance, evidence strength, recommendation fallbacks, and cadence plans from existing reporting views. Times display in ${DEFAULT_DISPLAY_TIMEZONE} unless a stored setting says otherwise.`}
        eyebrow="Read-only reporting"
        title="Analytics"
      />

      <PartialErrorState errors={data.partialErrors} />

      <StaleNotice title="Sample size and freshness matter">
        Each result shows its observed post count where the database exposes it.
        Small samples are directional, not conclusive. Recommendation choices,
        scores, fallbacks, and slot plans come from the database; this interface
        does not reproduce scheduling calculations in TypeScript.
        {staleRecommendations &&
          " At least one recommendation reports delayed or stale metrics."}
      </StaleNotice>

      {!hasAnalyticsRows(data) ? (
        <EmptyState title="No analytics rows were returned">
          The reporting views may not yet have enough sent-post metrics, or an
          unavailable section may be listed above.
        </EmptyState>
      ) : (
        <>
          <div className="grid gap-6 xl:grid-cols-2">
            <SectionCard
              description="Observed performance grouped by the repository reporting view."
              title="Content performance"
            >
              <div className="space-y-3">
                {data.contentPerformance.slice(0, 12).map((row, index) => (
                  <article
                    className="border-line bg-foreground/[0.025] rounded-xl border p-4"
                    key={`${row.platform}-${row.game}-${row.contentType}-${row.vibe}-${index}`}
                  >
                    <div className="flex flex-wrap items-center gap-2">
                      <PlatformBadge platform={row.platform} />
                      <Badge>{row.postCount} posts</Badge>
                    </div>
                    <p className="text-foreground mt-3 text-sm font-medium">
                      {row.game ?? "Unspecified game"} ·{" "}
                      {row.contentType ?? "Unspecified type"}
                    </p>
                    <p className="text-muted mt-1 text-xs">
                      {row.vibe ?? "No vibe"} · {row.hookType ?? "No hook type"}
                    </p>
                    <div className="mt-3 grid grid-cols-3 gap-2 text-xs">
                      <p className="text-muted">
                        <span className="text-foreground block font-semibold">
                          {formatCompactNumber(row.averageViews)}
                        </span>
                        average views
                      </p>
                      <p className="text-muted">
                        <span className="text-foreground block font-semibold">
                          {formatCompactNumber(row.medianViews)}
                        </span>
                        median views
                      </p>
                      <p className="text-muted">
                        <span className="text-foreground block font-semibold">
                          {formatPercentage(row.averageInteractionRate)}
                        </span>
                        interaction rate
                      </p>
                    </div>
                  </article>
                ))}
              </div>
            </SectionCard>

            <SectionCard
              description="Day and hour observations remain separated by platform and channel."
              title="Posting day and time"
            >
              <div className="space-y-3">
                {data.postingWindows.slice(0, 16).map((row, index) => (
                  <article
                    className="border-line bg-foreground/[0.025] flex flex-col gap-3 rounded-xl border p-4 sm:flex-row sm:items-center sm:justify-between"
                    key={`${row.platform}-${row.channelName}-${row.day}-${row.hour}-${index}`}
                  >
                    <div>
                      <div className="flex flex-wrap items-center gap-2">
                        <PlatformBadge platform={row.platform} />
                        <Badge>{row.postCount} posts</Badge>
                      </div>
                      <p className="text-foreground mt-2 text-sm font-medium">
                        {row.day} · {formatHour(row.hour)}
                      </p>
                      <p className="text-muted mt-1 text-xs">
                        {row.channelName}
                      </p>
                    </div>
                    <div className="text-left sm:text-right">
                      <p className="text-accent text-sm font-semibold">
                        {formatCompactNumber(row.averageViews)} avg
                      </p>
                      <p className="text-muted text-xs">
                        {formatCompactNumber(row.medianViews)} median ·{" "}
                        {formatPercentage(row.averageInteractionRate)} rate
                      </p>
                    </div>
                  </article>
                ))}
              </div>
            </SectionCard>
          </div>

          <SectionCard
            description="Joint day-and-time recommendations ranked by the database, with their supporting sample sizes."
            title="Platform recommendations"
          >
            <div className="grid gap-4 lg:grid-cols-2">
              {observedPlatforms.map((platform) => (
                <div
                  className="border-line bg-foreground/[0.025] rounded-xl border p-4"
                  key={platform}
                >
                  <PlatformBadge platform={platform} />
                  <div className="mt-3 space-y-3">
                    {data.recommendations
                      .filter((row) => row.platform === platform)
                      .map((row) => (
                        <article
                          className="border-line bg-canvas/60 rounded-xl border p-3"
                          key={`${row.platform}-${row.rank}`}
                        >
                          <div className="flex flex-wrap items-center justify-between gap-2">
                            <p className="text-foreground text-sm font-semibold">
                              #{row.rank} · {row.recommendedSlot}
                            </p>
                            <Badge tone={freshnessTone(row.metricsStatus)}>
                              {row.metricsStatus}
                            </Badge>
                          </div>
                          <p className="text-muted mt-2 text-xs leading-5">
                            {row.sampleSize} posts in this slot ·{" "}
                            {row.platformSampleSize} platform posts · confidence{" "}
                            {row.confidence} · score {row.score}
                          </p>
                          <p className="text-muted mt-1 text-xs">
                            {row.readyForApprovalMode
                              ? "Database marks this recommendation ready"
                              : "Database does not mark this recommendation ready"}
                            {row.latestMetricDate
                              ? ` · latest metric ${row.latestMetricDate}`
                              : " · metric date unavailable"}
                          </p>
                        </article>
                      ))}
                    {data.recommendations.every(
                      (row) => row.platform !== platform,
                    ) && (
                      <p className="text-muted text-sm">
                        No ranked recommendation rows returned.
                      </p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </SectionCard>

          <SectionCard
            description="The selected database model level shows when sparse content groups fall back to broader evidence."
            title="Recommendation hierarchy and fallback"
          >
            <div className="grid gap-3 lg:grid-cols-2">
              {data.fallbackSelections.slice(0, 16).map((row, index) => (
                <article
                  className="border-line bg-foreground/[0.025] rounded-xl border p-4"
                  key={`${row.platform}-${row.game}-${row.contentType}-${row.vibe}-${index}`}
                >
                  <div className="flex flex-wrap items-center gap-2">
                    <PlatformBadge platform={row.platform} />
                    <Badge tone={row.readyForPreview ? "positive" : "warning"}>
                      {row.readyForPreview ? "Ready" : "Not ready"}
                    </Badge>
                    <Badge>{row.selectedModelLevel}</Badge>
                  </div>
                  <p className="text-foreground mt-3 text-sm font-medium">
                    {row.game ?? "All games"} ·{" "}
                    {row.contentType ?? "All content types"} ·{" "}
                    {row.vibe ?? "All vibes"}
                  </p>
                  <p className="text-muted mt-1 text-xs leading-5">
                    {row.fallbackReason}
                  </p>
                  <p className="text-muted mt-2 text-xs">
                    {row.groupSampleSize} observed / {row.minimumSampleSize}
                    minimum · {row.recommendedSlot} · {row.confidence} ·{" "}
                    {row.metricsStatus}
                  </p>
                </article>
              ))}
            </div>
          </SectionCard>

          <div className="grid gap-6 xl:grid-cols-[0.8fr_1.2fr]">
            <SectionCard
              description="Active flags and guardrails read directly from cadence settings."
              title="Cadence settings"
            >
              <div className="space-y-3">
                {data.cadenceSettings.map((row) => (
                  <article
                    className="border-line bg-foreground/[0.025] rounded-xl border p-4"
                    key={`${row.platform}-${row.contentFormat}`}
                  >
                    <div className="flex flex-wrap items-center gap-2">
                      <PlatformBadge platform={row.platform} />
                      <Badge tone={row.isActive ? "positive" : "neutral"}>
                        {row.isActive ? "Active" : "Inactive"}
                      </Badge>
                      <Badge>{row.contentFormat}</Badge>
                    </div>
                    <div className="text-muted mt-3 grid grid-cols-2 gap-2 text-xs">
                      <p>{row.postsPerWeek} posts / week</p>
                      <p>{row.maxPostsPerDay} max / day</p>
                      <p>{row.minGapHours}h minimum gap</p>
                      <p>{row.protectedHours}h protected window</p>
                      <p>{row.minimumSampleSize} sample minimum</p>
                      <p>{row.metricsFreshnessLimitDays}d metrics limit</p>
                    </div>
                    <p className="text-muted mt-3 text-xs">
                      {row.timezoneName} · updated{" "}
                      {formatDateTime(row.updatedAt, row.timezoneName)}
                    </p>
                  </article>
                ))}
              </div>
            </SectionCard>

            <SectionCard
              description="Weekly slots generated by the existing database plan."
              title="Weekly slot plans"
            >
              <div className="grid gap-3 sm:grid-cols-2">
                {data.weeklySlots.map((row) => (
                  <article
                    className="border-line bg-foreground/[0.025] rounded-xl border p-4"
                    key={`${row.platform}-${row.contentFormat}-${row.slotRank}`}
                  >
                    <div className="flex flex-wrap items-center gap-2">
                      <PlatformBadge platform={row.platform} />
                      <Badge>Slot {row.slotRank}</Badge>
                    </div>
                    <p className="text-foreground mt-3 text-sm font-semibold">
                      {row.day} · {formatHour(row.hour)}
                    </p>
                    <p className="text-muted mt-1 text-xs">
                      {row.recommendedWindow} · {row.contentFormat}
                    </p>
                    <p className="text-muted mt-2 text-xs">
                      {row.sampleSize} samples · {row.confidence} ·{" "}
                      {row.metricsStatus} · {row.timezoneName}
                    </p>
                  </article>
                ))}
              </div>
            </SectionCard>
          </div>
        </>
      )}
    </div>
  );
}
