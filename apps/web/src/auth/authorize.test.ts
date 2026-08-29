import { describe, expect, it } from "vitest";

import { parseEmailAllowlist } from "@/auth/allowlist";
import { authorizeIdentity } from "@/auth/authorize";
import { ForbiddenError, UnauthenticatedError } from "@/auth/errors";

describe("email allowlist authorization", () => {
  const allowedEmails = parseEmailAllowlist(
    "analyst@example.invalid, operator@example.invalid",
  );

  it("normalizes configured and authenticated email addresses", async () => {
    await expect(
      authorizeIdentity({
        allowedEmails,
        loadIdentity: async () => ({
          id: "sanitized-user-id",
          email: " Analyst@Example.Invalid ",
        }),
      }),
    ).resolves.toEqual({
      id: "sanitized-user-id",
      email: "analyst@example.invalid",
    });
  });

  it("rejects a request without a validated session", async () => {
    await expect(
      authorizeIdentity({
        allowedEmails,
        loadIdentity: async () => null,
      }),
    ).rejects.toBeInstanceOf(UnauthenticatedError);
  });

  it("rejects an authenticated account outside the allowlist", async () => {
    await expect(
      authorizeIdentity({
        allowedEmails,
        loadIdentity: async () => ({
          id: "sanitized-user-id",
          email: "viewer@example.invalid",
        }),
      }),
    ).rejects.toBeInstanceOf(ForbiddenError);
  });
});
