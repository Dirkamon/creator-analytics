import { describe, expect, it } from "vitest";
import {
  parsePreferencesConfiguration,
  preferencesUiAvailable,
} from "@/config/preferences-server";

const database = (role: string, project = "iepwctcayajdpvsmfmgl") =>
  `postgresql://${role}.${project}:placeholder@aws-1-us-west-2.pooler.supabase.com:5432/postgres?sslmode=verify-full`;
const valid = () => ({
  CREATOR_ANALYTICS_PREFERENCES_ENABLED: "true",
  CREATOR_ANALYTICS_APP_ORIGIN: "https://creator-analytics-staging.vercel.app",
  CREATOR_ANALYTICS_DATABASE_URL: database("creator_analytics_web_reader"),
  CREATOR_ANALYTICS_PREFERENCES_DATABASE_URL: database(
    "creator_analytics_web_scheduler",
  ),
});

describe("staging preference configuration", () => {
  it("is hidden by default and accepts only the exact staging origin", () => {
    expect(preferencesUiAvailable({})).toBe(false);
    expect(parsePreferencesConfiguration(valid()).writerUrl).toContain(
      "creator_analytics_web_scheduler",
    );
  });
  it.each([
    "https://creator-analytics-theta.vercel.app",
    "https://evil-staging.example",
    "http://127.0.0.1:3107",
  ])("rejects %s", (origin) => {
    expect(() =>
      parsePreferencesConfiguration({
        ...valid(),
        CREATOR_ANALYTICS_APP_ORIGIN: origin,
      }),
    ).toThrow();
  });
  it.each([
    "creator_analytics_web_reader",
    "creator_analytics_web_approver",
    "postgres",
    "service_role",
  ])("rejects the %s writer identity", (role) => {
    expect(() =>
      parsePreferencesConfiguration({
        ...valid(),
        CREATOR_ANALYTICS_PREFERENCES_DATABASE_URL: database(role),
      }),
    ).toThrow();
  });
  it("rejects either connection pointing at production and rejects weak TLS", () => {
    for (const field of [
      "CREATOR_ANALYTICS_DATABASE_URL",
      "CREATOR_ANALYTICS_PREFERENCES_DATABASE_URL",
    ] as const) {
      const input = valid();
      input[field] = input[field].replace(
        "iepwctcayajdpvsmfmgl",
        "ppgrvebsgefoogulolhs",
      );
      expect(() => parsePreferencesConfiguration(input)).toThrow();
    }
    expect(() =>
      parsePreferencesConfiguration({
        ...valid(),
        CREATOR_ANALYTICS_PREFERENCES_DATABASE_URL:
          valid().CREATOR_ANALYTICS_PREFERENCES_DATABASE_URL.replace(
            "verify-full",
            "require",
          ),
      }),
    ).toThrow();
  });
});
