import "server-only";

import { ConfigurationError } from "@/config/errors";
import {
  getServerEnvironment,
  isApprovedDatabaseUrl,
} from "@/config/env-server";

const stagingOrigin = "https://creator-analytics-staging.vercel.app";
const stagingProject = "iepwctcayajdpvsmfmgl";
const productionOrigin = "https://creator-analytics-theta.vercel.app";
const productionProject = "ppgrvebsgefoogulolhs";

export function preferencesUiAvailable(
  input: Record<string, string | undefined>,
) {
  return (
    input.CREATOR_ANALYTICS_PREFERENCES_ENABLED === "true" &&
    (input.CREATOR_ANALYTICS_APP_ORIGIN === stagingOrigin ||
      (input.CREATOR_ANALYTICS_APP_ORIGIN === productionOrigin &&
        input.CREATOR_ANALYTICS_PREFERENCES_PRODUCTION_APPROVED === "true"))
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
      "Scheduling preferences are available only in an explicitly approved deployment.",
    );
  }
  const environment =
    input.CREATOR_ANALYTICS_APP_ORIGIN === productionOrigin
      ? ("production" as const)
      : ("staging" as const);
  const project =
    environment === "production" ? productionProject : stagingProject;
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
        decodeURIComponent(new URL(value).username) !== `${role}.${project}` ||
        !new URL(value).password
      ) {
        throw new Error("Invalid database identity");
      }
    } catch {
      throw new ConfigurationError(
        "Scheduling preferences require separate restricted reader and settings credentials for this deployment.",
      );
    }
  }
  if (new URL(readerUrl!).host !== new URL(writerUrl!).host) {
    throw new ConfigurationError(
      "Scheduling preference connections must use the same database.",
    );
  }
  return {
    writerUrl: writerUrl!,
    environment,
    activationAllowed:
      environment === "staging" ||
      input.CREATOR_ANALYTICS_PREFERENCES_ACTIVATION_APPROVED === "true",
  };
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
    CREATOR_ANALYTICS_PREFERENCES_PRODUCTION_APPROVED:
      process.env.CREATOR_ANALYTICS_PREFERENCES_PRODUCTION_APPROVED,
    CREATOR_ANALYTICS_PREFERENCES_ACTIVATION_APPROVED:
      process.env.CREATOR_ANALYTICS_PREFERENCES_ACTIVATION_APPROVED,
  });
}
