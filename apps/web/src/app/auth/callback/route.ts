import { NextResponse, type NextRequest } from "next/server";

import { authorizeIdentity } from "@/auth/authorize";
import { getServerEnvironment } from "@/config/env-server";
import { createServerAuthClient } from "@/lib/supabase/server-auth";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const destination = new URL("/dashboard", request.url);

  if (!code) {
    return NextResponse.redirect(
      new URL("/sign-in?reason=invalid-link", request.url),
    );
  }

  try {
    const supabase = await createServerAuthClient();
    const { data, error } = await supabase.auth.exchangeCodeForSession(code);

    if (error || !data.user) {
      return NextResponse.redirect(
        new URL("/sign-in?reason=invalid-link", request.url),
      );
    }

    const environment = getServerEnvironment();
    await authorizeIdentity({
      allowedEmails: environment.allowedEmails,
      loadIdentity: async () => ({
        id: data.user.id,
        email: data.user.email ?? null,
      }),
    });

    return NextResponse.redirect(destination);
  } catch {
    const supabase = await createServerAuthClient();
    await supabase.auth.signOut();
    return NextResponse.redirect(
      new URL("/sign-in?reason=not-authorized", request.url),
    );
  }
}
