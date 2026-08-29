import "server-only";

import { createClient } from "@supabase/supabase-js";

import {
  getServerEnvironment,
  requireServerDataSecret,
} from "@/config/env-server";
import { getPublicEnvironment } from "@/config/env-public";

export function createServerDataClient() {
  const publicEnvironment = getPublicEnvironment();
  const serverEnvironment = getServerEnvironment();
  const serverSecret = requireServerDataSecret(serverEnvironment);

  return createClient(
    publicEnvironment.NEXT_PUBLIC_SUPABASE_URL,
    serverSecret,
    {
      auth: {
        autoRefreshToken: false,
        detectSessionInUrl: false,
        persistSession: false,
      },
    },
  );
}
