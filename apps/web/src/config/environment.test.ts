import { describe, expect, it } from "vitest";

import { ConfigurationError } from "@/config/errors";
import { parsePublicEnvironment } from "@/config/env-public";
import {
  parseServerEnvironment,
  requireDatabaseUrl,
  requireLabelDatabaseUrl,
} from "@/config/env-server";

const serverEnvironmentBase = {
  CREATOR_ANALYTICS_ALLOWED_EMAILS: "analyst@example.invalid",
  CREATOR_ANALYTICS_APP_ORIGIN: "http://localhost:3000",
};

const testProjectRef = "abcdefghijklmnopqrst";
const remoteDatabaseUrl = (
  overrides: {
    database?: string;
    host?: string;
    port?: string;
    query?: string;
    username?: string;
  } = {},
) =>
  `postgresql://${overrides.username ?? `creator_analytics_web_reader.${testProjectRef}`}:placeholder@${overrides.host ?? "aws-0-us-west-2.pooler.supabase.com"}:${overrides.port ?? "5432"}/${overrides.database ?? "postgres"}?${overrides.query ?? "sslmode=verify-full"}`;

function expectDatabaseUrlRejected(databaseUrl: string) {
  let caughtError: unknown;

  try {
    parseServerEnvironment({
      ...serverEnvironmentBase,
      CREATOR_ANALYTICS_DATABASE_URL: databaseUrl,
    });
  } catch (error) {
    caughtError = error;
  }

  expect(caughtError).toBeInstanceOf(ConfigurationError);
  expect(String(caughtError)).not.toContain("placeholder");
}

describe("environment validation", () => {
  it("accepts placeholder-shaped public configuration", () => {
    expect(
      parsePublicEnvironment({
        NEXT_PUBLIC_SUPABASE_URL: "https://project-ref.supabase.co",
        NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "publishable-key-placeholder",
      }),
    ).toEqual({
      NEXT_PUBLIC_SUPABASE_URL: "https://project-ref.supabase.co",
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "publishable-key-placeholder",
    });
  });

  it("reports field names without echoing invalid values", () => {
    const secretLikeValue = "must-not-appear-in-error-output";

    expect(() =>
      parsePublicEnvironment({
        NEXT_PUBLIC_SUPABASE_URL: secretLikeValue,
        NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "short",
      }),
    ).toThrow(ConfigurationError);

    try {
      parsePublicEnvironment({
        NEXT_PUBLIC_SUPABASE_URL: secretLikeValue,
        NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "short",
      });
    } catch (error) {
      expect(String(error)).not.toContain(secretLikeValue);
    }
  });

  it("parses the allowlist without requiring a server data secret", () => {
    const environment = parseServerEnvironment({
      CREATOR_ANALYTICS_ALLOWED_EMAILS:
        "analyst@example.invalid,operator@example.invalid",
      CREATOR_ANALYTICS_APP_ORIGIN: "http://localhost:3000",
      CREATOR_ANALYTICS_DATABASE_URL: undefined,
    });

    expect(environment.allowedEmails.has("operator@example.invalid")).toBe(
      true,
    );
    expect(environment.CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS).toBe(15);
    expect(environment.CREATOR_ANALYTICS_METRICS_STALE_HOURS).toBe(48);
    expect(environment.CREATOR_ANALYTICS_LABELING_ENABLED).toBe(false);
    expect(environment.CREATOR_ANALYTICS_LABELING_PRODUCTION_APPROVED).toBe(
      false,
    );
  });

  it("validates configurable freshness thresholds", () => {
    const environment = parseServerEnvironment({
      CREATOR_ANALYTICS_ALLOWED_EMAILS: "analyst@example.invalid",
      CREATOR_ANALYTICS_APP_ORIGIN: "http://localhost:3000",
      CREATOR_ANALYTICS_DATABASE_URL: undefined,
      CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS: "12",
      CREATOR_ANALYTICS_METRICS_STALE_HOURS: "72",
    });

    expect(environment.CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS).toBe(12);
    expect(environment.CREATOR_ANALYTICS_METRICS_STALE_HOURS).toBe(72);

    expect(() =>
      parseServerEnvironment({
        CREATOR_ANALYTICS_ALLOWED_EMAILS: "analyst@example.invalid",
        CREATOR_ANALYTICS_APP_ORIGIN: "http://localhost:3000",
        CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS: "0",
      }),
    ).toThrow(ConfigurationError);
  });

  it("keeps the server data secret optional until a data query is attempted", () => {
    const environment = parseServerEnvironment({
      CREATOR_ANALYTICS_ALLOWED_EMAILS: "analyst@example.invalid",
      CREATOR_ANALYTICS_APP_ORIGIN: "http://localhost:3000",
      CREATOR_ANALYTICS_DATABASE_URL: undefined,
    });

    expect(() => requireDatabaseUrl(environment)).toThrow(ConfigurationError);
    expect(() => requireLabelDatabaseUrl(environment)).toThrow(
      ConfigurationError,
    );
  });

  it("requires an explicit, exact production opt-in for the dedicated labeler", () => {
    const labelerUrl = remoteDatabaseUrl({
      username: `creator_analytics_web_labeler.${testProjectRef}`,
    });
    const environment = parseServerEnvironment({
      ...serverEnvironmentBase,
      CREATOR_ANALYTICS_APP_ORIGIN:
        "https://creator-analytics-staging.vercel.app",
      CREATOR_ANALYTICS_LABELING_ENABLED: "true",
      CREATOR_ANALYTICS_LABEL_DATABASE_URL: labelerUrl,
    });

    expect(requireLabelDatabaseUrl(environment)).toBe(labelerUrl);

    expect(() =>
      parseServerEnvironment({
        ...serverEnvironmentBase,
        CREATOR_ANALYTICS_APP_ORIGIN: "https://analytics.example.com",
        CREATOR_ANALYTICS_LABELING_ENABLED: "true",
        CREATOR_ANALYTICS_LABEL_DATABASE_URL: labelerUrl,
      }),
    ).toThrow(ConfigurationError);

    expect(() =>
      parseServerEnvironment({
        ...serverEnvironmentBase,
        CREATOR_ANALYTICS_APP_ORIGIN:
          "https://creator-analytics-theta.vercel.app",
        CREATOR_ANALYTICS_LABELING_ENABLED: "true",
        CREATOR_ANALYTICS_LABEL_DATABASE_URL: labelerUrl,
      }),
    ).toThrow(ConfigurationError);

    const productionEnvironment = parseServerEnvironment({
      ...serverEnvironmentBase,
      CREATOR_ANALYTICS_APP_ORIGIN:
        "https://creator-analytics-theta.vercel.app",
      CREATOR_ANALYTICS_LABELING_ENABLED: "true",
      CREATOR_ANALYTICS_LABELING_PRODUCTION_APPROVED: "true",
      CREATOR_ANALYTICS_LABEL_DATABASE_URL: labelerUrl,
    });

    expect(requireLabelDatabaseUrl(productionEnvironment)).toBe(labelerUrl);

    expect(() =>
      parseServerEnvironment({
        ...serverEnvironmentBase,
        CREATOR_ANALYTICS_APP_ORIGIN: "https://creator-notstaging.example.com",
        CREATOR_ANALYTICS_LABELING_ENABLED: "true",
        CREATOR_ANALYTICS_LABELING_PRODUCTION_APPROVED: "true",
        CREATOR_ANALYTICS_LABEL_DATABASE_URL: labelerUrl,
      }),
    ).toThrow(ConfigurationError);

    expect(() =>
      parseServerEnvironment({
        ...serverEnvironmentBase,
        CREATOR_ANALYTICS_APP_ORIGIN:
          "http://creator-analytics-theta.vercel.app",
        CREATOR_ANALYTICS_LABELING_ENABLED: "true",
        CREATOR_ANALYTICS_LABELING_PRODUCTION_APPROVED: "true",
        CREATOR_ANALYTICS_LABEL_DATABASE_URL: labelerUrl,
      }),
    ).toThrow(ConfigurationError);
  });

  it("requires an exact labeler connection when labeling is enabled", () => {
    expect(() =>
      parseServerEnvironment({
        ...serverEnvironmentBase,
        CREATOR_ANALYTICS_LABELING_ENABLED: "true",
      }),
    ).toThrow(ConfigurationError);

    expect(() =>
      parseServerEnvironment({
        ...serverEnvironmentBase,
        CREATOR_ANALYTICS_LABELING_ENABLED: "true",
        CREATOR_ANALYTICS_LABEL_DATABASE_URL: remoteDatabaseUrl(),
      }),
    ).toThrow(ConfigurationError);
  });

  it("accepts only PostgreSQL connection URLs for server data access", () => {
    const environment = parseServerEnvironment({
      CREATOR_ANALYTICS_ALLOWED_EMAILS: "analyst@example.invalid",
      CREATOR_ANALYTICS_APP_ORIGIN: "http://localhost:3000",
      CREATOR_ANALYTICS_DATABASE_URL:
        "postgresql://creator_analytics_web_reader:placeholder@127.0.0.1:6543/postgres?sslmode=disable",
    });

    expect(requireDatabaseUrl(environment)).toMatch(
      /^postgresql:\/\/creator_analytics_web_reader:/,
    );

    expect(() =>
      parseServerEnvironment({
        CREATOR_ANALYTICS_ALLOWED_EMAILS: "analyst@example.invalid",
        CREATOR_ANALYTICS_APP_ORIGIN: "http://localhost:3000",
        CREATOR_ANALYTICS_DATABASE_URL: "https://example.invalid/database",
      }),
    ).toThrow(ConfigurationError);
  });

  it("preserves exact local reader access for IPv4 and IPv6 loopback", () => {
    for (const host of ["localhost", "127.0.0.1", "[::1]"]) {
      const environment = parseServerEnvironment({
        ...serverEnvironmentBase,
        CREATOR_ANALYTICS_DATABASE_URL: `postgresql://creator_analytics_web_reader:placeholder@${host}:6543/postgres?sslmode=disable`,
      });

      expect(environment.CREATOR_ANALYTICS_DATABASE_URL).toBeDefined();
    }
  });

  it("accepts approved session-pooler URLs and encoded username separators", () => {
    for (const databaseUrl of [
      remoteDatabaseUrl(),
      remoteDatabaseUrl({
        query: "sslrootcert=system",
        username: `creator_analytics_web_reader%2E${testProjectRef}`,
      }),
    ]) {
      const environment = parseServerEnvironment({
        ...serverEnvironmentBase,
        CREATOR_ANALYTICS_DATABASE_URL: databaseUrl,
      });

      expect(environment.CREATOR_ANALYTICS_DATABASE_URL).toBeDefined();
    }
  });

  it("rejects remote bare readers and malformed project-ref suffixes", () => {
    expectDatabaseUrlRejected(
      remoteDatabaseUrl({ username: "creator_analytics_web_reader" }),
    );
    expectDatabaseUrlRejected(
      remoteDatabaseUrl({
        username: "creator_analytics_web_reader.too-short",
      }),
    );
    expectDatabaseUrlRejected(
      remoteDatabaseUrl({
        username: "creator_analytics_web_reader.ABCDEFGHIJKLMNOPQRST",
      }),
    );
  });

  it("rejects broad, admin, and incorrectly segmented remote roles", () => {
    expectDatabaseUrlRejected(
      remoteDatabaseUrl({ username: `postgres.${testProjectRef}` }),
    );
    expectDatabaseUrlRejected(
      remoteDatabaseUrl({
        username: `creator_analytics_web_reader.${testProjectRef}.extra`,
      }),
    );
  });

  it("rejects non-Supabase hosts, wrong ports, and wrong database paths", () => {
    expectDatabaseUrlRejected(
      remoteDatabaseUrl({ host: "pooler.example.invalid" }),
    );
    expectDatabaseUrlRejected(remoteDatabaseUrl({ port: "6543" }));
    expectDatabaseUrlRejected(remoteDatabaseUrl({ database: "analytics" }));
  });

  it("rejects weakened or ambiguous remote TLS settings", () => {
    expectDatabaseUrlRejected(remoteDatabaseUrl({ query: "sslmode=require" }));
    expectDatabaseUrlRejected(
      remoteDatabaseUrl({
        query: "sslmode=require&sslrootcert=system",
      }),
    );
    expectDatabaseUrlRejected(
      remoteDatabaseUrl({
        query: "sslmode=verify-full&sslmode=require",
      }),
    );
  });

  it("converts malformed encoded usernames into sanitized configuration errors", () => {
    expectDatabaseUrlRejected(
      remoteDatabaseUrl({
        username: "creator_analytics_web_reader%2E%E0%A4%A",
      }),
    );
  });
});
