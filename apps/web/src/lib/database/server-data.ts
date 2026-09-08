import "server-only";

import postgres from "postgres";

import {
  getServerEnvironment,
  requireDatabaseUrl,
  requireLabelDatabaseUrl,
  requireScheduleDatabaseUrl,
} from "@/config/env-server";
import { postgresDateText } from "@/lib/database/postgres-types";
import { getPreferencesConfiguration } from "@/config/preferences-server";
import { getDatabaseSslOptions } from "@/lib/database/supabase-tls";

export type ServerDataClient = ReturnType<typeof postgres>;

let serverDataClient: ServerDataClient | undefined;
let serverLabelingClient: ServerDataClient | undefined;
let serverScheduleDecisionClient: ServerDataClient | undefined;
let serverPreferencesClient: ServerDataClient | undefined;

export function getServerPreferencesClient(): ServerDataClient {
  // Validate the staging gate even when a connection pool already exists.
  const { writerUrl } = getPreferencesConfiguration();
  serverPreferencesClient ??= createServerDataClient({
    applicationName: "creator-analytics-web-scheduler",
    connectionUrl: writerUrl,
    max: 1,
  });
  return serverPreferencesClient;
}

function createServerDataClient(options: {
  applicationName: string;
  connectionUrl: string;
  max: number;
}): ServerDataClient {
  return postgres(options.connectionUrl, {
    connect_timeout: 10,
    connection: {
      application_name: options.applicationName,
    },
    idle_timeout: 20,
    max: options.max,
    max_lifetime: 10 * 60,
    onnotice: () => undefined,
    prepare: false,
    ssl: getDatabaseSslOptions(options.connectionUrl),
    types: {
      dateText: postgresDateText,
    },
  });
}

export function getServerDataClient(): ServerDataClient {
  if (serverDataClient) {
    return serverDataClient;
  }

  const environment = getServerEnvironment();
  const connectionUrl = requireDatabaseUrl(environment);

  serverDataClient = createServerDataClient({
    applicationName: "creator-analytics-web-reader",
    connectionUrl,
    max: 3,
  });

  return serverDataClient;
}

export function getServerLabelingClient(): ServerDataClient {
  if (serverLabelingClient) {
    return serverLabelingClient;
  }

  const environment = getServerEnvironment();
  const connectionUrl = requireLabelDatabaseUrl(environment);

  serverLabelingClient = createServerDataClient({
    applicationName: "creator-analytics-web-labeler",
    connectionUrl,
    max: 2,
  });

  return serverLabelingClient;
}

export function getServerScheduleDecisionClient(): ServerDataClient {
  if (serverScheduleDecisionClient) {
    return serverScheduleDecisionClient;
  }

  const environment = getServerEnvironment();
  const connectionUrl = requireScheduleDatabaseUrl(environment);

  serverScheduleDecisionClient = createServerDataClient({
    applicationName: "creator-analytics-web-approver",
    connectionUrl,
    max: 2,
  });

  return serverScheduleDecisionClient;
}
