import "server-only";

import { z } from "zod";

import { parseEmailAllowlist } from "@/auth/allowlist";
import { ConfigurationError } from "@/config/errors";

const blankToUndefined = (value: unknown) =>
  typeof value === "string" && value.trim() === "" ? undefined : value;

const restrictedReaderRole = "creator_analytics_web_reader";
const restrictedLabelerRole = "creator_analytics_web_labeler";
const restrictedApproverRole = "creator_analytics_web_approver";
const approvedProductionMutationHostname = "creator-analytics-theta.vercel.app";
const supabaseProjectRefPattern = /^[a-z0-9]{20}$/;
const supabasePoolerHostnamePattern =
  /^[a-z0-9-]+(?:\.[a-z0-9-]+)*\.pooler\.supabase\.com$/;

export function isApprovedDatabaseUrl(value: string, requiredRole: string) {
  try {
    const url = new URL(value);
    const username = decodeURIComponent(url.username);
    const hostname = url.hostname.replace(/^\[|\]$/g, "");
    const isLocal = ["127.0.0.1", "::1", "localhost"].includes(hostname);
    const sslModes = url.searchParams.getAll("sslmode");
    const rootCertificates = url.searchParams.getAll("sslrootcert");

    if (isLocal) {
      return (
        username === requiredRole &&
        sslModes.length === 1 &&
        sslModes[0] === "disable"
      );
    }

    const [role, projectRef, unexpectedSegment] = username.split(".");
    const hasApprovedTlsSetting =
      sslModes[0] === "verify-full" || rootCertificates[0] === "system";
    const hasOnlyApprovedTlsSettings =
      sslModes.length <= 1 &&
      rootCertificates.length <= 1 &&
      sslModes.every((mode) => mode === "verify-full") &&
      rootCertificates.every((certificate) => certificate === "system");

    return (
      role === requiredRole &&
      projectRef !== undefined &&
      unexpectedSegment === undefined &&
      supabaseProjectRefPattern.test(projectRef) &&
      supabasePoolerHostnamePattern.test(url.hostname) &&
      url.port === "5432" &&
      url.pathname === "/postgres" &&
      hasApprovedTlsSetting &&
      hasOnlyApprovedTlsSettings
    );
  } catch {
    return false;
  }
}

const labelingEnabledValue = (value: unknown) => {
  if (typeof value !== "string") return value;
  const normalized = value.trim().toLowerCase();
  if (normalized === "true") return true;
  if (normalized === "false" || normalized === "") return false;
  return value;
};

function isApprovedMutationOrigin(
  value: string,
  productionMutationApproved: boolean,
) {
  try {
    const url = new URL(value);
    const hostname = url.hostname.toLowerCase();
    return (
      hostname === "localhost" ||
      hostname === "127.0.0.1" ||
      hostname === "::1" ||
      /(^|[.-])staging([.-]|$)/.test(hostname) ||
      (productionMutationApproved &&
        url.protocol === "https:" &&
        hostname === approvedProductionMutationHostname)
    );
  } catch {
    return false;
  }
}

const postgresUrl = (requiredRole: string, message: string) =>
  z
    .url()
    .refine(
      (value) =>
        value.startsWith("postgres://") || value.startsWith("postgresql://"),
      "must use the postgres or postgresql protocol",
    )
    .refine((value) => isApprovedDatabaseUrl(value, requiredRole), message);

const serverEnvironmentSchema = z
  .object({
    CREATOR_ANALYTICS_ALLOWED_EMAILS: z.string().min(3),
    CREATOR_ANALYTICS_APP_ORIGIN: z.url(),
    CREATOR_ANALYTICS_DATABASE_URL: z.preprocess(
      blankToUndefined,
      postgresUrl(
        restrictedReaderRole,
        "must use the restricted web reader and approved TLS settings",
      ).optional(),
    ),
    CREATOR_ANALYTICS_LABELING_ENABLED: z.preprocess(
      labelingEnabledValue,
      z.boolean().default(false),
    ),
    CREATOR_ANALYTICS_LABELING_PRODUCTION_APPROVED: z.preprocess(
      labelingEnabledValue,
      z.boolean().default(false),
    ),
    CREATOR_ANALYTICS_LABEL_DATABASE_URL: z.preprocess(
      blankToUndefined,
      postgresUrl(
        restrictedLabelerRole,
        "must use the restricted web labeler and approved TLS settings",
      ).optional(),
    ),
    CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED: z.preprocess(
      labelingEnabledValue,
      z.boolean().default(false),
    ),
    CREATOR_ANALYTICS_SCHEDULE_DECISIONS_PRODUCTION_APPROVED: z.preprocess(
      labelingEnabledValue,
      z.boolean().default(false),
    ),
    CREATOR_ANALYTICS_SCHEDULE_DATABASE_URL: z.preprocess(
      blankToUndefined,
      postgresUrl(
        restrictedApproverRole,
        "must use the restricted web approver and approved TLS settings",
      ).optional(),
    ),
    CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS: z.preprocess(
      blankToUndefined,
      z.coerce.number().int().min(1).max(168).default(15),
    ),
    CREATOR_ANALYTICS_METRICS_STALE_HOURS: z.preprocess(
      blankToUndefined,
      z.coerce.number().int().min(1).max(720).default(48),
    ),
  })
  .superRefine((environment, context) => {
    if (environment.CREATOR_ANALYTICS_LABELING_ENABLED) {
      if (!environment.CREATOR_ANALYTICS_LABEL_DATABASE_URL) {
        context.addIssue({
          code: "custom",
          path: ["CREATOR_ANALYTICS_LABEL_DATABASE_URL"],
          message: "is required when labeling is enabled",
        });
      }

      if (
        !isApprovedMutationOrigin(
          environment.CREATOR_ANALYTICS_APP_ORIGIN,
          environment.CREATOR_ANALYTICS_LABELING_PRODUCTION_APPROVED,
        )
      ) {
        context.addIssue({
          code: "custom",
          path: ["CREATOR_ANALYTICS_LABELING_ENABLED"],
          message:
            "may be enabled only for local or staging origins unless the approved production deployment is explicitly enabled",
        });
      }
    }

    if (environment.CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED) {
      if (!environment.CREATOR_ANALYTICS_SCHEDULE_DATABASE_URL) {
        context.addIssue({
          code: "custom",
          path: ["CREATOR_ANALYTICS_SCHEDULE_DATABASE_URL"],
          message: "is required when schedule decisions are enabled",
        });
      }

      if (
        !isApprovedMutationOrigin(
          environment.CREATOR_ANALYTICS_APP_ORIGIN,
          environment.CREATOR_ANALYTICS_SCHEDULE_DECISIONS_PRODUCTION_APPROVED,
        )
      ) {
        context.addIssue({
          code: "custom",
          path: ["CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED"],
          message:
            "may be enabled only for local or staging origins unless the approved production deployment is explicitly enabled",
        });
      }
    }
  });

export type ServerEnvironment = z.infer<typeof serverEnvironmentSchema> & {
  allowedEmails: ReadonlySet<string>;
};

export function parseServerEnvironment(
  input: Record<string, string | undefined>,
): ServerEnvironment {
  const result = serverEnvironmentSchema.safeParse(input);

  if (!result.success) {
    const fields = Array.from(
      new Set(result.error.issues.map((issue) => issue.path.join("."))),
    ).join(", ");
    throw new ConfigurationError(
      `Server configuration is missing or invalid: ${fields}.`,
    );
  }

  try {
    return {
      ...result.data,
      allowedEmails: parseEmailAllowlist(
        result.data.CREATOR_ANALYTICS_ALLOWED_EMAILS,
      ),
    };
  } catch {
    throw new ConfigurationError(
      "CREATOR_ANALYTICS_ALLOWED_EMAILS must contain valid comma-separated email addresses.",
    );
  }
}

export function getServerEnvironment(): ServerEnvironment {
  return parseServerEnvironment({
    CREATOR_ANALYTICS_ALLOWED_EMAILS:
      process.env.CREATOR_ANALYTICS_ALLOWED_EMAILS,
    CREATOR_ANALYTICS_APP_ORIGIN: process.env.CREATOR_ANALYTICS_APP_ORIGIN,
    CREATOR_ANALYTICS_DATABASE_URL: process.env.CREATOR_ANALYTICS_DATABASE_URL,
    CREATOR_ANALYTICS_LABELING_ENABLED:
      process.env.CREATOR_ANALYTICS_LABELING_ENABLED,
    CREATOR_ANALYTICS_LABELING_PRODUCTION_APPROVED:
      process.env.CREATOR_ANALYTICS_LABELING_PRODUCTION_APPROVED,
    CREATOR_ANALYTICS_LABEL_DATABASE_URL:
      process.env.CREATOR_ANALYTICS_LABEL_DATABASE_URL,
    CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED:
      process.env.CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED,
    CREATOR_ANALYTICS_SCHEDULE_DECISIONS_PRODUCTION_APPROVED:
      process.env.CREATOR_ANALYTICS_SCHEDULE_DECISIONS_PRODUCTION_APPROVED,
    CREATOR_ANALYTICS_SCHEDULE_DATABASE_URL:
      process.env.CREATOR_ANALYTICS_SCHEDULE_DATABASE_URL,
    CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS:
      process.env.CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS,
    CREATOR_ANALYTICS_METRICS_STALE_HOURS:
      process.env.CREATOR_ANALYTICS_METRICS_STALE_HOURS,
  });
}

export function requireDatabaseUrl(environment: ServerEnvironment): string {
  if (!environment.CREATOR_ANALYTICS_DATABASE_URL) {
    throw new ConfigurationError(
      "CREATOR_ANALYTICS_DATABASE_URL is not configured for server-side read access.",
    );
  }

  return environment.CREATOR_ANALYTICS_DATABASE_URL;
}

export function requireLabelDatabaseUrl(
  environment: ServerEnvironment,
): string {
  if (
    !environment.CREATOR_ANALYTICS_LABELING_ENABLED ||
    !environment.CREATOR_ANALYTICS_LABEL_DATABASE_URL
  ) {
    throw new ConfigurationError(
      "Controlled labeling is not configured for this deployment.",
    );
  }

  return environment.CREATOR_ANALYTICS_LABEL_DATABASE_URL;
}

export function requireScheduleDatabaseUrl(
  environment: ServerEnvironment,
): string {
  if (
    !environment.CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED ||
    !environment.CREATOR_ANALYTICS_SCHEDULE_DATABASE_URL
  ) {
    throw new ConfigurationError(
      "Controlled schedule decisions are not configured for this deployment.",
    );
  }

  return environment.CREATOR_ANALYTICS_SCHEDULE_DATABASE_URL;
}
