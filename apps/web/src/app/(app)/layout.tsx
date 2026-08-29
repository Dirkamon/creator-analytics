import { redirect } from "next/navigation";
import type { ReactNode } from "react";

import { ForbiddenError, UnauthenticatedError } from "@/auth/errors";
import { requireAuthorizedUser } from "@/auth/authorization.server";
import { AppShell } from "@/components/shell/app-shell";
import { AccessFailure } from "@/components/states/access-failure";

export const dynamic = "force-dynamic";

export default async function AuthenticatedLayout({
  children,
}: {
  children: ReactNode;
}) {
  let user;

  try {
    user = await requireAuthorizedUser();
  } catch (error) {
    if (error instanceof UnauthenticatedError) {
      redirect("/sign-in?reason=session-required");
    }

    if (error instanceof ForbiddenError) {
      return <AccessFailure error={error} />;
    }

    return <AccessFailure error={error} />;
  }

  return <AppShell userEmail={user.email}>{children}</AppShell>;
}
