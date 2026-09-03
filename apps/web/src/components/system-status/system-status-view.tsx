import {
  AlertTriangle,
  CheckCircle2,
  Database,
  RadioTower,
} from "lucide-react";

import {
  EmptyState,
  PartialErrorState,
  StaleNotice,
} from "@/components/states/feedback-states";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/page-header";
import { PlatformBadge } from "@/components/ui/platform-badge";
import { SectionCard } from "@/components/ui/section-card";
import type { FreshnessState, SystemStatusData } from "@/data/models";
import {
  DEFAULT_DISPLAY_TIMEZONE,
  formatDateTime,
  formatLocalWallTime,
} from "@/lib/format";

function displayCount(value: number | null): string {
  return value === null ? "Unavailable" : value.toLocaleString("en-US");
}

function SummaryCard({
  label,
  value,
  detail,
}: {
  label: string;
  value: number | null;
  detail: string;
}) {
  return (
    <div className="rounded-2xl border border-white/10 bg-slate-950/55 p-5">
      <p className="text-xs font-semibold tracking-[0.1em] text-slate-500 uppercase">
        {label}
      </p>
      <p className="mt-2 text-2xl font-semibold text-white">
        {displayCount(value)}
      </p>
      <p className="mt-1 text-xs leading-5 text-slate-600">{detail}</p>
    </div>
  );
}

function attentionTone(attention: number) {
  return attention > 0 ? ("warning" as const) : ("positive" as const);
}

function freshnessTone(state: FreshnessState) {
  if (state === "Fresh") return "positive" as const;
  if (state === "Stale") return "danger" as const;
  return "warning" as const;
}

export function SystemStatusView({ data }: { data: SystemStatusData }) {
  const hasObservedRows =
    data.postSyncFreshness.length > 0 ||
    data.metricsFreshness.length > 0 ||
    data.cadenceSettings.length > 0 ||
    data.previewReadiness.length > 0 ||
    data.recentProposalErrors.length > 0 ||
    data.blockedReasons.length > 0;

  return (
    <div className="space-y-7">
      <PageHeader
        aside={<Badge tone="info">Database-observed</Badge>}
        description={`Read-only freshness, configuration, proposal, preview, and Label Queue evidence. Display timestamps use ${DEFAULT_DISPLAY_TIMEZONE} unless the database records another timezone.`}
        eyebrow="Operational evidence"
        title="System Status"
      />

      <PartialErrorState errors={data.partialErrors} />

      <StaleNotice title="This is not live service monitoring">
        Status on this page is derived only from synchronized database records.
        It does not verify live Buffer queues, Make executions, Google Sheets,
        or network availability. A stale database timestamp can indicate lag,
        but cannot identify the external cause by itself.
      </StaleNotice>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <SummaryCard
          detail={`Platforms whose newest post-sync observation is missing or older than ${data.thresholds.postSyncStaleHours} hours.`}
          label="Post-sync platforms needing attention"
          value={data.summary.postSyncPlatformsNeedingAttention}
        />
        <SummaryCard
          detail={`Platforms whose newest sent-post metric observation is missing or older than ${data.thresholds.metricsStaleHours} hours.`}
          label="Metrics platforms needing attention"
          value={data.summary.metricsPlatformsNeedingAttention}
        />
        <SummaryCard
          detail="Approved records currently blocked by database application preflight."
          label="Blocked approved"
          value={data.summary.blockedApprovedProposals}
        />
        <SummaryCard
          detail="Unlinked records no longer present in the pending-export view."
          label="Exported, still unlinked"
          value={data.summary.exportedStillUnlinked}
        />
      </div>

      {!hasObservedRows && data.partialErrors.length === 0 ? (
        <EmptyState title="No database status rows were returned">
          The observed tables and views are empty. This does not establish the
          health of any external automation.
        </EmptyState>
      ) : (
        <>
          <div className="grid gap-6 xl:grid-cols-2">
            <SectionCard
              description={`Current health uses the newest last_synced_at per platform and a ${data.thresholds.postSyncStaleHours}-hour threshold. Older row coverage is informational only.`}
              title="Post synchronization freshness"
            >
              <div className="space-y-3">
                {data.postSyncFreshness.map((row) => (
                  <article
                    className="rounded-xl border border-white/5 bg-white/[0.025] p-4"
                    key={row.platform}
                  >
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <PlatformBadge platform={row.platform} />
                      <Badge tone={freshnessTone(row.state)}>{row.state}</Badge>
                    </div>
                    <p className="mt-3 text-sm text-slate-300">
                      Latest observed sync:{" "}
                      {row.latestSyncedAt
                        ? formatDateTime(row.latestSyncedAt)
                        : "not recorded"}
                    </p>
                    <p className="mt-2 text-xs leading-5 text-slate-600">
                      Historical coverage: {row.observedPosts} records ·{" "}
                      {row.recordsWithTimestamp} with timestamps ·{" "}
                      {row.historicalRowsOutsideThreshold} older than the
                      current threshold · {row.missingTimestamps} missing. These
                      row counts do not represent current pipeline failures.
                    </p>
                  </article>
                ))}
              </div>
            </SectionCard>

            <SectionCard
              description={`Current health uses the newest sent-post latest_metric_captured_at per platform and a ${data.thresholds.metricsStaleHours}-hour threshold. Older row coverage is informational only.`}
              title="Metrics freshness"
            >
              <div className="space-y-3">
                {data.metricsFreshness.map((row) => (
                  <article
                    className="rounded-xl border border-white/5 bg-white/[0.025] p-4"
                    key={row.platform}
                  >
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <PlatformBadge platform={row.platform} />
                      <Badge tone={freshnessTone(row.state)}>{row.state}</Badge>
                    </div>
                    <p className="mt-3 text-sm text-slate-300">
                      Latest observed metric capture:{" "}
                      {row.latestCapturedAt
                        ? formatDateTime(row.latestCapturedAt)
                        : "not recorded"}
                    </p>
                    <p className="mt-2 text-xs leading-5 text-slate-600">
                      Historical sent-post coverage: {row.observedSentPosts}{" "}
                      records · {row.recordsWithTimestamp} with timestamps ·{" "}
                      {row.historicalRowsOutsideThreshold} older than the
                      current threshold · {row.missingTimestamps} missing. These
                      row counts do not establish current external-service
                      health.
                    </p>
                  </article>
                ))}
              </div>
            </SectionCard>
          </div>

          <div className="grid gap-6 xl:grid-cols-[0.8fr_1.2fr]">
            <SectionCard
              description="Existing cadence rows expose active flags and required scheduling configuration."
              title="Channel configuration flags"
            >
              <div className="space-y-3">
                {data.cadenceSettings.map((row) => (
                  <article
                    className="rounded-xl border border-white/5 bg-white/[0.025] p-4"
                    key={`${row.platform}-${row.contentFormat}`}
                  >
                    <div className="flex flex-wrap items-center gap-2">
                      <PlatformBadge platform={row.platform} />
                      <Badge tone={row.isActive ? "positive" : "danger"}>
                        {row.isActive ? "Active" : "Inactive"}
                      </Badge>
                    </div>
                    <p className="mt-3 text-sm text-slate-300">
                      {row.contentFormat} · {row.postsPerWeek}/week ·{" "}
                      {row.maxPostsPerDay}/day · {row.minGapHours}h gap
                    </p>
                    <p className="mt-1 text-xs text-slate-600">
                      {row.timezoneName} · {row.protectedHours}h protected ·{" "}
                      {row.minimumSampleSize} sample minimum
                    </p>
                  </article>
                ))}
              </div>
            </SectionCard>

            <SectionCard
              description="Current rows in the existing proposal-preview summary; this page does not refresh the preview."
              title="Proposal preview readiness"
            >
              <div className="grid gap-3 sm:grid-cols-2">
                {data.previewReadiness.map((row) => (
                  <article
                    className="rounded-xl border border-white/5 bg-white/[0.025] p-4"
                    key={row.platform}
                  >
                    <div className="flex flex-wrap items-center gap-2">
                      <PlatformBadge platform={row.platform} />
                      <Badge tone={attentionTone(row.blockedRows)}>
                        {row.readyRows} ready · {row.blockedRows} blocked
                      </Badge>
                    </div>
                    <p className="mt-3 text-sm text-slate-300">
                      {row.previewRows} preview rows · {row.guardrailPassRows}{" "}
                      pass guardrails
                    </p>
                    <p className="mt-2 text-xs leading-5 text-slate-500">
                      Blocks: {row.activeProposalBlocks} active proposal ·{" "}
                      {row.sameChannelBlocks} channel collision ·{" "}
                      {row.channelIdentityBlocks} identity ·{" "}
                      {row.configurationBlocks} configuration ·{" "}
                      {row.dailyCapacityBlocks} daily ·{" "}
                      {row.weeklyCapacityBlocks} weekly
                    </p>
                    <p className="mt-2 text-xs text-slate-600">
                      {row.contentSpecificRows} content-specific ·{" "}
                      {row.platformFallbackRows} platform fallback
                    </p>
                    <p className="mt-1 text-xs text-slate-600">
                      Range{" "}
                      {row.firstProposedAtLocal
                        ? formatLocalWallTime(row.firstProposedAtLocal)
                        : "unavailable"}
                      {row.lastProposedAtLocal
                        ? ` to ${formatLocalWallTime(row.lastProposedAtLocal)}`
                        : ""}
                    </p>
                  </article>
                ))}
              </div>
            </SectionCard>
          </div>

          <div className="grid gap-6 xl:grid-cols-2">
            <SectionCard
              description="Application-preflight reasons for Approved proposals that are not ready."
              title="Blocked approved proposals"
            >
              {data.blockedReasons.length > 0 ? (
                <div className="space-y-3">
                  {data.blockedReasons.map((row) => (
                    <div
                      className="flex items-start justify-between gap-4 rounded-xl border border-amber-400/10 bg-amber-400/[0.04] p-4"
                      key={row.reason}
                    >
                      <p className="text-sm leading-5 text-slate-300">
                        {row.reason}
                      </p>
                      <Badge tone="warning">{row.count}</Badge>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-slate-500">
                  No blocked Approved proposal rows were observed.
                </p>
              )}
            </SectionCard>

            <SectionCard
              description="Proposal records currently carrying Error status. No external execution logs are queried."
              title="Proposal errors"
            >
              {data.recentProposalErrors.length > 0 ? (
                <div className="space-y-3">
                  {data.recentProposalErrors.map((row, index) => (
                    <div
                      className="flex items-center justify-between gap-3 rounded-xl border border-rose-400/10 bg-rose-400/[0.04] p-4"
                      key={`${row.platform}-${row.updatedAt}-${index}`}
                    >
                      <div className="flex items-center gap-2">
                        <AlertTriangle
                          aria-hidden
                          className="text-rose-300"
                          size={16}
                        />
                        <PlatformBadge platform={row.platform} />
                      </div>
                      <p className="text-xs text-slate-500">
                        {formatDateTime(row.updatedAt)}
                      </p>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="flex items-center gap-2 text-sm text-slate-500">
                  <CheckCircle2 aria-hidden size={16} /> No proposal Error rows
                  were observed.
                </p>
              )}
            </SectionCard>
          </div>
        </>
      )}

      <div className="grid gap-6 xl:grid-cols-2">
        <SectionCard
          description="Counts are derived from current unlinked and pending-export database views."
          title="Label Queue backlog"
        >
          <div className="grid grid-cols-3 gap-3 text-center">
            <div className="rounded-xl border border-white/5 bg-white/[0.025] p-3">
              <p className="text-xl font-semibold text-white">
                {displayCount(data.summary.unlinkedPosts)}
              </p>
              <p className="mt-1 text-xs text-slate-500">unlinked</p>
            </div>
            <div className="rounded-xl border border-white/5 bg-white/[0.025] p-3">
              <p className="text-xl font-semibold text-white">
                {displayCount(data.summary.pendingLabelExports)}
              </p>
              <p className="mt-1 text-xs text-slate-500">pending export</p>
            </div>
            <div className="rounded-xl border border-white/5 bg-white/[0.025] p-3">
              <p className="text-xl font-semibold text-white">
                {displayCount(data.summary.exportedStillUnlinked)}
              </p>
              <p className="mt-1 text-xs text-slate-500">
                exported, still unlinked
              </p>
            </div>
          </div>
          <p className="mt-4 text-xs leading-5 text-amber-200/80">
            The exported-but-unlinked total is database state. It is not proof
            that Google Sheets or Make failed; operator or live-system evidence
            is required to determine why a record remains unlinked.
          </p>
        </SectionCard>

        <SectionCard
          description="Repository evidence determines what this app can safely claim."
          title="Automation telemetry"
        >
          <div className="flex items-start gap-3 rounded-xl border border-white/5 bg-white/[0.025] p-4">
            <div className="rounded-lg border border-white/10 bg-white/5 p-2 text-slate-300">
              <RadioTower aria-hidden size={17} />
            </div>
            <div>
              <Badge tone="warning">Unavailable</Badge>
              <p className="mt-3 text-sm leading-6 text-slate-400">
                {data.automationTelemetry.explanation}
              </p>
            </div>
          </div>
        </SectionCard>
      </div>

      <p className="flex items-center gap-2 text-xs text-slate-600">
        <Database aria-hidden size={14} /> Read-only database observation only.
      </p>
    </div>
  );
}
