import "server-only";

import { ConfigurationError } from "@/config/errors";
import {
  getServerEnvironment,
  isApprovedDatabaseUrl,
} from "@/config/env-server";

const stagingOrigin = "https://creator-analytics-staging.vercel.app";
const stagingProject = "iepwctcayajdpvsmfmgl";

export function preferencesUiAvailable(
  input: Record<string, string | undefined>,
) {
  return (
    input.CREATOR_ANALYTICS_PREFERENCES_ENABLED === "true" &&
    input.CREATOR_ANALYTICS_APP_ORIGIN === stagingOrigin
  );
}

export function isPreferencesUiAvailable() {
  return preferencesUiAvailable(process.env);
}

export function parsePreferencesConfiguration(
  input: Record<string, string | undefined>,
) {
  if (!preferencesUiAvailable(input)) {
    throw new ConfigurationError(
      "Scheduling preferences are available only in the approved staging deployment.",
    );
  }
  const readerUrl = input.CREATOR_ANALYTICS_DATABASE_URL;
  const writerUrl = input.CREATOR_ANALYTICS_PREFERENCES_DATABASE_URL;
  for (const [value, role] of [
    [readerUrl, "creator_analytics_web_reader"],
    [writerUrl, "creator_analytics_web_scheduler"],
  ] as const) {
    try {
      if (
        !value ||
        !/^postgres(?:ql)?:\/\//.test(value) ||
        !isApprovedDatabaseUrl(value, role) ||
        decodeURIComponent(new URL(value).username) !==
          `${role}.${stagingProject}` ||
        !new URL(value).password
      ) {
        throw new Error("Invalid database identity");
      }
    } catch {
      throw new ConfigurationError(
        "Scheduling preferences require separate restricted staging reader and settings credentials.",
      );
    }
  }
  if (new URL(readerUrl!).host !== new URL(writerUrl!).host) {
    throw new ConfigurationError(
      "Scheduling preference connections must use the same staging database.",
    );
  }
  return { writerUrl: writerUrl! };
}

export function getPreferencesConfiguration() {
  const environment = getServerEnvironment();
  return parsePreferencesConfiguration({
    CREATOR_ANALYTICS_APP_ORIGIN: environment.CREATOR_ANALYTICS_APP_ORIGIN,
    CREATOR_ANALYTICS_DATABASE_URL: environment.CREATOR_ANALYTICS_DATABASE_URL,
    CREATOR_ANALYTICS_PREFERENCES_DATABASE_URL:
      process.env.CREATOR_ANALYTICS_PREFERENCES_DATABASE_URL,
    CREATOR_ANALYTICS_PREFERENCES_ENABLED:
      process.env.CREATOR_ANALYTICS_PREFERENCES_ENABLED,
  });
}
