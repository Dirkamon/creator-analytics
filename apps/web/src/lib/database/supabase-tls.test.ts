import { describe, expect, it } from "vitest";

import { getDatabaseSslOptions } from "@/lib/database/supabase-tls";

describe("database TLS options", () => {
  it("uses the Supabase root CA for verified hosted connections", () => {
    const options = getDatabaseSslOptions(
      "postgresql://creator_analytics_web_reader.project-ref:password@aws-0-us-west-2.pooler.supabase.com:5432/postgres?sslmode=verify-full",
    );

    expect(options).toMatchObject({
      rejectUnauthorized: true,
    });
    expect(options).toHaveProperty(
      "ca",
      expect.stringContaining("BEGIN CERTIFICATE"),
    );
  });

  it("keeps local validation connections unencrypted", () => {
    expect(
      getDatabaseSslOptions(
        "postgresql://creator_analytics_web_reader:password@127.0.0.1:5432/postgres?sslmode=disable",
      ),
    ).toBe(false);
  });
});
