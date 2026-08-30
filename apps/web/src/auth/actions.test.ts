import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getServerEnvironment: vi.fn(),
  createServerAuthClient: vi.fn(),
  redirect: vi.fn(),
  signInWithOtp: vi.fn(),
  signOut: vi.fn(),
}));

vi.mock("next/navigation", () => ({ redirect: mocks.redirect }));
vi.mock("@/config/env-server", () => ({
  getServerEnvironment: mocks.getServerEnvironment,
}));
vi.mock("@/lib/supabase/server-auth", () => ({
  createServerAuthClient: mocks.createServerAuthClient,
}));

import { requestMagicLink, signOut } from "@/auth/actions";
import { initialMagicLinkState } from "@/auth/magic-link-state";

const neutralMessage =
  "If this address is approved and already registered, a secure sign-in link is on its way.";

describe("authentication actions", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getServerEnvironment.mockReturnValue({
      CREATOR_ANALYTICS_APP_ORIGIN: "https://analytics.example.invalid",
      allowedEmails: new Set(["operator@example.invalid"]),
    });
    mocks.createServerAuthClient.mockResolvedValue({
      auth: {
        signInWithOtp: mocks.signInWithOtp,
        signOut: mocks.signOut,
      },
    });
    mocks.signInWithOtp.mockResolvedValue({ error: null });
    mocks.signOut.mockResolvedValue({ error: null });
  });

  it("does not contact Auth for an address outside the server allowlist", async () => {
    const formData = new FormData();
    formData.set("email", "outsider@example.invalid");

    await expect(
      requestMagicLink(initialMagicLinkState, formData),
    ).resolves.toEqual({
      status: "success",
      message: neutralMessage,
    });
    expect(mocks.createServerAuthClient).not.toHaveBeenCalled();
  });

  it("requests a non-signup magic link for an allowlisted address", async () => {
    const formData = new FormData();
    formData.set("email", "Operator@Example.Invalid");

    await expect(
      requestMagicLink(initialMagicLinkState, formData),
    ).resolves.toEqual({
      status: "success",
      message: neutralMessage,
    });
    expect(mocks.signInWithOtp).toHaveBeenCalledWith({
      email: "operator@example.invalid",
      options: {
        shouldCreateUser: false,
        emailRedirectTo: "https://analytics.example.invalid/auth/callback",
      },
    });
  });

  it("clears the Supabase session before redirecting on sign-out", async () => {
    await signOut();

    expect(mocks.signOut).toHaveBeenCalledOnce();
    expect(mocks.redirect).toHaveBeenCalledWith("/sign-in");
  });

  it("does not redirect when sign-out fails", async () => {
    mocks.signOut.mockResolvedValue({ error: new Error("sanitized") });

    await expect(signOut()).rejects.toThrow("Sign out could not be completed.");
    expect(mocks.redirect).not.toHaveBeenCalled();
  });
});
