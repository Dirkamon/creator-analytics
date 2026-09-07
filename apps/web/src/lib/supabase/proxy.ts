import { createServerClient } from "@supabase/ssr";
import { type NextRequest, NextResponse } from "next/server";

import { getPublicEnvironment } from "@/config/env-public";

const protectedPaths = [
  "/dashboard",
  "/calendar",
  "/upcoming-posts",
  "/label-queue",
  "/schedule-approvals",
  "/analytics",
  "/system-status",
];

export async function refreshAuthSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  try {
    const environment = getPublicEnvironment();
    const supabase = createServerClient(
      environment.NEXT_PUBLIC_SUPABASE_URL,
      environment.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
      {
        cookies: {
          getAll: () => request.cookies.getAll(),
          setAll(cookiesToSet) {
            cookiesToSet.forEach(({ name, value }) => {
              request.cookies.set(name, value);
            });
            response = NextResponse.next({ request });
            cookiesToSet.forEach(({ name, value, options }) => {
              response.cookies.set(name, value, options);
            });
          },
        },
      },
    );

    const { data } = await supabase.auth.getClaims();
    const hasSession = Boolean(data?.claims?.sub);
    const isProtected = protectedPaths.some(
      (path) =>
        request.nextUrl.pathname === path ||
        request.nextUrl.pathname.startsWith(`${path}/`),
    );

    if (isProtected && !hasSession) {
      const signInUrl = request.nextUrl.clone();
      signInUrl.pathname = "/sign-in";
      signInUrl.searchParams.set("reason", "session-required");
      return NextResponse.redirect(signInUrl);
    }
  } catch {
    // Missing local configuration is rendered by the page-level configuration state.
  }

  return response;
}
