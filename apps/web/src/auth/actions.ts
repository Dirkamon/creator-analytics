"use server";

import { redirect } from "next/navigation";
import { z } from "zod";

import { isEmailAllowed } from "@/auth/allowlist";
import type { MagicLinkState } from "@/auth/magic-link-state";
import { ConfigurationError } from "@/config/errors";
import { getServerEnvironment } from "@/config/env-server";
import { createServerAuthClient } from "@/lib/supabase/server-auth";

const magicLinkSchema = z.object({
  email: z.email().transform((email) => email.trim().toLowerCase()),
});

const neutralMagicLinkMessage =
  "If this address is approved and already registered, a secure sign-in link is on its way.";

export async function requestMagicLink(
  _previousState: MagicLinkState,
  formData: FormData,
): Promise<MagicLinkState> {
  const parsed = magicLinkSchema.safeParse({
    email: formData.get("email"),
  });

  if (!parsed.success) {
    return {
      status: "error",
      message: "Enter a valid email address.",
    };
  }

  try {
    const environment = getServerEnvironment();

    if (!isEmailAllowed(parsed.data.email, environment.allowedEmails)) {
      return { status: "success", message: neutralMagicLinkMessage };
    }

    const supabase = await createServerAuthClient();
    const { error } = await supabase.auth.signInWithOtp({
      email: parsed.data.email,
      options: {
        shouldCreateUser: false,
        emailRedirectTo: new URL(
          "/auth/callback",
          environment.CREATOR_ANALYTICS_APP_ORIGIN,
        ).toString(),
      },
    });

    if (error) {
      return {
        status: "error",
        message: "The sign-in link could not be sent. Try again later.",
      };
    }

    return { status: "success", message: neutralMagicLinkMessage };
  } catch (error) {
    return {
      status: "error",
      message:
        error instanceof ConfigurationError
          ? "Local authentication configuration is incomplete. See apps/web/.env.example."
          : "The sign-in link could not be sent. Try again later.",
    };
  }
}

export async function signOut() {
  const supabase = await createServerAuthClient();
  await supabase.auth.signOut();
  redirect("/sign-in");
}
