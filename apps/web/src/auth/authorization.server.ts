import "server-only";

import { cache } from "react";

import { authorizeIdentity } from "@/auth/authorize";
import { getServerEnvironment } from "@/config/env-server";
import { createServerAuthClient } from "@/lib/supabase/server-auth";

export const requireAuthorizedUser = cache(async () => {
  const environment = getServerEnvironment();

  return authorizeIdentity({
    allowedEmails: environment.allowedEmails,
    loadIdentity: async () => {
      const supabase = await createServerAuthClient();
      const { data, error } = await supabase.auth.getUser();

      if (error || !data.user) {
        return null;
      }

      return {
        id: data.user.id,
        email: data.user.email ?? null,
      };
    },
  });
});
