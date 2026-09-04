import { existsSync, readFileSync, readdirSync } from "node:fs";
import { extname, join } from "node:path";

import { describe, expect, it } from "vitest";

function sourceFiles(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory()
      ? sourceFiles(path)
      : [".ts", ".tsx"].includes(extname(entry.name))
        ? [path]
        : [];
  });
}

describe("production source boundaries", () => {
  const sourceRoot = join(process.cwd(), "src");
  const productionFiles = sourceFiles(sourceRoot).filter(
    (path) => !path.endsWith(".test.ts") && !path.endsWith(".test.tsx"),
  );

  it("does not retain the legacy broad server credential path", () => {
    const forbiddenName = ["SUPABASE", "SERVER", "SECRET", "KEY"].join("_");
    const source = productionFiles
      .map((path) => readFileSync(path, "utf8"))
      .join("\n");

    expect(source).not.toContain(forbiddenName);
  });

  it("keeps PostgreSQL and private-schema details out of client modules", () => {
    const clientSource = productionFiles
      .map((path) => ({ path, source: readFileSync(path, "utf8") }))
      .filter(({ source }) => /^["']use client["'];/m.test(source));

    for (const { source } of clientSource) {
      expect(source).not.toMatch(
        /\bpostgres\b|creator_app|CREATOR_ANALYTICS_(?:(?:LABEL|SCHEDULE)_)?DATABASE_URL|creator_analytics_web_(?:reader|labeler|approver)|\/rest\/v1\//,
      );
    }
  });

  it("keeps database connectivity in the server-only module", () => {
    const databaseModule = join(
      sourceRoot,
      "lib",
      "database",
      "server-data.ts",
    );
    expect(existsSync(databaseModule)).toBe(true);
    expect(readFileSync(databaseModule, "utf8")).toContain(
      'import "server-only"',
    );

    const postgresImports = productionFiles.filter((path) =>
      /from ["']postgres["']/.test(readFileSync(path, "utf8")),
    );
    expect(postgresImports).toEqual([databaseModule]);
  });
});
