import "server-only";

import { z } from "zod";

import { parseEmailAllowlist } from "@/auth/allowlist";
import { ConfigurationError } from "@/config/errors";

const blankToUndefined = (value: unknown) =>
  typeof value === "string" && value.trim() === "" ? undefined : value;

const serverEnvironmentSchema = z.object({
  CREATOR_ANALYTICS_ALLOWED_EMAILS: z.string().min(3),
  CREATOR_ANALYTICS_APP_ORIGIN: z.url(),
  SUPABASE_SERVER_SECRET_KEY: z.preprocess(
    blankToUndefined,
    z.string().min(20).optional(),
  ),
  CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS: z.preprocess(
    blankToUndefined,
    z.coerce.number().int().min(1).max(168).default(6),
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
    SUPABASE_SERVER_SECRET_KEY: process.env.SUPABASE_SERVER_SECRET_KEY,
    CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS:
      process.env.CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS,
    CREATOR_ANALYTICS_METRICS_STALE_HOURS:
      process.env.CREATOR_ANALYTICS_METRICS_STALE_HOURS,
  });
}

export function requireServerDataSecret(
  environment: ServerEnvironment,
): string {
  if (!environment.SUPABASE_SERVER_SECRET_KEY) {
    throw new ConfigurationError(
      "SUPABASE_SERVER_SECRET_KEY is not configured for server-side read access.",
    );
  }

  return environment.SUPABASE_SERVER_SECRET_KEY;
}
