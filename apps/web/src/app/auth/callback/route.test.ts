import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getServerEnvironment: vi.fn(),
  createServerAuthClient: vi.fn(),
  exchangeCodeForSession: vi.fn(),
  signOut: vi.fn(),
}));

vi.mock("@/config/env-server", () => ({
  getServerEnvironment: mocks.getServerEnvironment,
}));
vi.mock("@/lib/supabase/server-auth", () => ({
  createServerAuthClient: mocks.createServerAuthClient,
}));

import { GET } from "@/app/auth/callback/route";

function callbackRequest(query = "") {
  const url = new URL(
    `https://analytics.example.invalid/auth/callback${query}`,
  );
  return { nextUrl: url, url: url.toString() } as never;
}

describe("magic-link callback", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getServerEnvironment.mockReturnValue({
      allowedEmails: new Set(["operator@example.invalid"]),
    });
    mocks.createServerAuthClient.mockResolvedValue({
      auth: {
        exchangeCodeForSession: mocks.exchangeCodeForSession,
        signOut: mocks.signOut,
      },
    });
    mocks.signOut.mockResolvedValue({ error: null });
  });

  it("rejects a callback without a code before creating an auth client", async () => {
    const response = await GET(callbackRequest());

    expect(response.headers.get("location")).toBe(
      "https://analytics.example.invalid/sign-in?reason=invalid-link",
    );
    expect(mocks.createServerAuthClient).not.toHaveBeenCalled();
  });

  it("accepts a valid session only when its email is allowlisted", async () => {
    mocks.exchangeCodeForSession.mockResolvedValue({
      data: {
        user: { id: "sanitized-user", email: "Operator@Example.Invalid" },
      },
      error: null,
    });

    const response = await GET(callbackRequest("?code=sanitized-code"));

    expect(response.headers.get("location")).toBe(
      "https://analytics.example.invalid/dashboard",
    );
    expect(mocks.signOut).not.toHaveBeenCalled();
  });

  it("clears a valid session whose email is outside the allowlist", async () => {
    mocks.exchangeCodeForSession.mockResolvedValue({
      data: {
        user: { id: "sanitized-user", email: "outsider@example.invalid" },
      },
      error: null,
    });

    const response = await GET(callbackRequest("?code=sanitized-code"));

    expect(mocks.signOut).toHaveBeenCalledOnce();
    expect(response.headers.get("location")).toBe(
      "https://analytics.example.invalid/sign-in?reason=not-authorized",
    );
  });

  it("rejects an invalid or expired code", async () => {
    mocks.exchangeCodeForSession.mockResolvedValue({
      data: { user: null },
      error: new Error("invalid"),
    });

    const response = await GET(callbackRequest("?code=expired-code"));

    expect(response.headers.get("location")).toBe(
      "https://analytics.example.invalid/sign-in?reason=invalid-link",
    );
  });

  it("fails closed when the server auth client is unavailable", async () => {
    mocks.createServerAuthClient.mockRejectedValue(new Error("not configured"));

    const response = await GET(callbackRequest("?code=sanitized-code"));

    expect(response.headers.get("location")).toBe(
      "https://analytics.example.invalid/sign-in?reason=not-authorized",
    );
    expect(mocks.signOut).not.toHaveBeenCalled();
  });
});
