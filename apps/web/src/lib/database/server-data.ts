import "server-only";

import postgres from "postgres";

import { getServerEnvironment, requireDatabaseUrl } from "@/config/env-server";
import { postgresDateText } from "@/lib/database/postgres-types";
import { getDatabaseSslOptions } from "@/lib/database/supabase-tls";

export type ServerDataClient = ReturnType<typeof postgres>;

let serverDataClient: ServerDataClient | undefined;

export function getServerDataClient(): ServerDataClient {
  if (serverDataClient) {
    return serverDataClient;
  }

  const environment = getServerEnvironment();
  const connectionUrl = requireDatabaseUrl(environment);

  serverDataClient = postgres(connectionUrl, {
    connect_timeout: 10,
    connection: {
      application_name: "creator-analytics-web",
    },
    idle_timeout: 20,
    max: 3,
    max_lifetime: 10 * 60,
    onnotice: () => undefined,
    prepare: false,
    ssl: getDatabaseSslOptions(connectionUrl),
    types: {
      dateText: postgresDateText,
    },
  });

  return serverDataClient;
}
