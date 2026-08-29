import { isEmailAllowed } from "@/auth/allowlist";
import { ForbiddenError, UnauthenticatedError } from "@/auth/errors";

export type AuthenticatedIdentity = {
  id: string;
  email: string | null;
};

export type AuthorizedUser = {
  id: string;
  email: string;
};

export async function authorizeIdentity(options: {
  loadIdentity: () => Promise<AuthenticatedIdentity | null>;
  allowedEmails: ReadonlySet<string>;
}): Promise<AuthorizedUser> {
  const identity = await options.loadIdentity();

  if (!identity) {
    throw new UnauthenticatedError();
  }

  if (
    !identity.email ||
    !isEmailAllowed(identity.email, options.allowedEmails)
  ) {
    throw new ForbiddenError();
  }

  return {
    id: identity.id,
    email: identity.email.trim().toLowerCase(),
  };
}
