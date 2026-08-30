import { describe, expect, it } from "vitest";

import { ConfigurationError } from "@/config/errors";
import { parsePublicEnvironment } from "@/config/env-public";
import {
  parseServerEnvironment,
  requireServerDataSecret,
} from "@/config/env-server";

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
      SUPABASE_SERVER_SECRET_KEY: undefined,
    });

    expect(environment.allowedEmails.has("operator@example.invalid")).toBe(
      true,
    );
    expect(environment.CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS).toBe(15);
    expect(environment.CREATOR_ANALYTICS_METRICS_STALE_HOURS).toBe(48);
  });

  it("validates configurable freshness thresholds", () => {
    const environment = parseServerEnvironment({
      CREATOR_ANALYTICS_ALLOWED_EMAILS: "analyst@example.invalid",
      CREATOR_ANALYTICS_APP_ORIGIN: "http://localhost:3000",
      SUPABASE_SERVER_SECRET_KEY: undefined,
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
      SUPABASE_SERVER_SECRET_KEY: undefined,
    });

    expect(() => requireServerDataSecret(environment)).toThrow(
      ConfigurationError,
    );
  });
});
