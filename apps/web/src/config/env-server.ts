import "server-only";

import { z } from "zod";

import { parseEmailAllowlist } from "@/auth/allowlist";
import { ConfigurationError } from "@/config/errors";

const blankToUndefined = (value: unknown) =>
  typeof value === "string" && value.trim() === "" ? undefined : value;

function isApprovedDatabaseUrl(value: string) {
  const url = new URL(value);
  const isLocal = ["127.0.0.1", "::1", "localhost"].includes(url.hostname);

  return (
    decodeURIComponent(url.username) === "creator_analytics_web_reader" &&
    (isLocal
      ? url.searchParams.get("sslmode") === "disable"
      : url.searchParams.get("sslmode") === "verify-full" ||
        url.searchParams.get("sslrootcert") === "system")
  );
}

const serverEnvironmentSchema = z.object({
  CREATOR_ANALYTICS_ALLOWED_EMAILS: z.string().min(3),
  CREATOR_ANALYTICS_APP_ORIGIN: z.url(),
  CREATOR_ANALYTICS_DATABASE_URL: z.preprocess(
    blankToUndefined,
    z
      .url()
      .refine(
        (value) =>
          value.startsWith("postgres://") || value.startsWith("postgresql://"),
        "must use the postgres or postgresql protocol",
      )
      .refine(
        isApprovedDatabaseUrl,
        "must use the restricted web reader and approved TLS settings",
      )
      .optional(),
  ),
  CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS: z.preprocess(
    blankToUndefined,
    z.coerce.number().int().min(1).max(168).default(15),
  ),
  CREATOR_ANALYTICS_METRICS_STALE_HOURS: z.preprocess(
    blankToUndefined,
    z.coerce.number().int().min(1).max(720).default(48),
  ),
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
