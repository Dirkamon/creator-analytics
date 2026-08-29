export class UnauthenticatedError extends Error {
  constructor() {
    super("An authenticated Supabase session is required.");
    this.name = "UnauthenticatedError";
  }
}

export class ForbiddenError extends Error {
  constructor() {
    super("This account is not approved for Creator Analytics.");
    this.name = "ForbiddenError";
  }
}

export function isAuthorizationError(error: unknown): boolean {
  return (
    error instanceof UnauthenticatedError || error instanceof ForbiddenError
  );
}
