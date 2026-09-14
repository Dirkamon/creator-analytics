import { describe, expect, it } from "vitest";

import nextConfig from "../../next.config";

describe("production security headers", () => {
  it("sets global browser hardening headers", async () => {
    const rules = await nextConfig.headers?.();
    const globalRule = rules?.find((rule) => rule.source === "/:path*");
    const headers = new Map(
      globalRule?.headers.map((header) => [header.key, header.value]),
    );

    expect(headers.get("Content-Security-Policy")).toContain(
      "frame-ancestors 'none'",
    );
    expect(headers.get("Content-Security-Policy")).toContain(
      "object-src 'none'",
    );
    expect(headers.get("X-Content-Type-Options")).toBe("nosniff");
    expect(headers.get("X-Frame-Options")).toBe("DENY");
    expect(headers.get("X-Robots-Tag")).toContain("noindex");
  });

  it("marks every auth and protected route private and non-cacheable", async () => {
    const rules = await nextConfig.headers?.();
    const privateSources = new Set(
      rules
        ?.filter((rule) =>
          rule.headers.some(
            (header) =>
              header.key === "Cache-Control" &&
              header.value === "private, no-store, max-age=0",
          ),
        )
        .map((rule) => rule.source),
    );

    expect(privateSources).toEqual(
      new Set([
        "/dashboard/:path*",
        "/calendar/:path*",
        "/upcoming-posts/:path*",
        "/label-queue/:path*",
        "/schedule-approvals/:path*",
        "/analytics/:path*",
        "/system-status/:path*",
        "/auth/callback",
        "/sign-in",
      ]),
    );
  });
});
