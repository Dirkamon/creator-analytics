import Link from "next/link";

import { PermissionErrorState } from "@/components/states/feedback-states";
import { ConfigurationError } from "@/config/errors";

export function AccessFailure({ error }: { error: unknown }) {
  if (error instanceof ConfigurationError) {
    return (
      <div className="mx-auto max-w-2xl py-16">
        <PermissionErrorState title="Local configuration is incomplete">
          Add local values using <code>apps/web/.env.example</code> as the
          template. Do not commit the resulting environment file. No database
          request was made.
        </PermissionErrorState>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl py-16">
      <PermissionErrorState title="This account is not approved">
        The authenticated email is not on the server-side allowlist. Return to
        the{" "}
        <Link className="font-medium text-cyan-200 underline" href="/sign-in">
          sign-in page
        </Link>{" "}
        or ask the operator to review local configuration.
      </PermissionErrorState>
    </div>
  );
}
