import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  createServerClient: vi.fn(),
  getPublicEnvironment: vi.fn(),
  getClaims: vi.fn(),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: mocks.createServerClient,
}));
vi.mock("@/config/env-public", () => ({
  getPublicEnvironment: mocks.getPublicEnvironment,
}));

import { refreshAuthSession } from "@/lib/supabase/proxy";

function nextRequest(path: string) {
  const url = new URL(path, "https://analytics.example.invalid");
  return {
    cookies: {
      getAll: () => [],
      set: vi.fn(),
    },
    headers: new Headers(),
    nextUrl: Object.assign(url, {
      clone: () => new URL(url),
    }),
    url: url.toString(),
  } as never;
}

describe("protected-route proxy", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getPublicEnvironment.mockReturnValue({
      NEXT_PUBLIC_SUPABASE_URL: "https://project-ref.supabase.co",
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "publishable-placeholder",
    });
    mocks.createServerClient.mockReturnValue({
      auth: { getClaims: mocks.getClaims },
    });
  });

  it("redirects an unauthenticated protected request", async () => {
    mocks.getClaims.mockResolvedValue({ data: { claims: null } });

    const response = await refreshAuthSession(nextRequest("/dashboard"));

    expect(response.headers.get("location")).toBe(
      "https://analytics.example.invalid/sign-in?reason=session-required",
    );
  });

  it("allows a request with a verified claim through to server authorization", async () => {
    mocks.getClaims.mockResolvedValue({
      data: { claims: { sub: "sanitized-user" } },
    });

    const response = await refreshAuthSession(nextRequest("/analytics"));

    expect(response.headers.get("location")).toBeNull();
    expect(response.headers.get("x-middleware-next")).toBe("1");
  });

  it("does not turn missing local configuration into an auth bypass decision", async () => {
    mocks.getPublicEnvironment.mockImplementation(() => {
      throw new Error("not configured");
    });

    const response = await refreshAuthSession(nextRequest("/dashboard"));

    expect(response.headers.get("location")).toBeNull();
    expect(response.headers.get("x-middleware-next")).toBe("1");
  });
});
