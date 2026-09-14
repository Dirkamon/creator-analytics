import { existsSync, readFileSync, readdirSync } from "node:fs";
import { extname, join, relative } from "node:path";

const root = process.cwd();
const textExtensions = new Set([
  ".js",
  ".json",
  ".md",
  ".mjs",
  ".ts",
  ".tsx",
  ".yaml",
  ".yml",
]);
const ignoredDirectories = new Set([
  ".git",
  ".next",
  "coverage",
  "node_modules",
  "test-results",
]);

function filesBelow(directory) {
  if (!existsSync(directory)) return [];
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (entry.isDirectory() && ignoredDirectories.has(entry.name)) return [];
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return filesBelow(path);
    return textExtensions.has(extname(entry.name)) ||
      entry.name === ".env.example"
      ? [path]
      : [];
  });
}

const scanFiles = [
  ...filesBelow(join(root, "src")),
  ...filesBelow(join(root, "tests")),
  join(root, ".env.example"),
  join(root, "README.md"),
  join(root, "next.config.ts"),
].filter(existsSync);

const legacyServerSecretName = ["SUPABASE", "SERVER", "SECRET", "KEY"].join(
  "_",
);
const secretPatterns = [
  {
    label: "legacy broad server-secret configuration",
    pattern: new RegExp(legacyServerSecretName),
  },
  { label: "Supabase secret key", pattern: /sb_secret_[A-Za-z0-9_-]{12,}/ },
  {
    label: "private key",
    pattern: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  },
  {
    label: "database password embedded in a PostgreSQL URL",
    pattern:
      /postgres(?:ql)?:\/\/[^:\s/]+:(?!(?:placeholder|replace-me)(?:@|%40))[^@\s]+@/i,
  },
];

const failures = [];
for (const path of scanFiles) {
  const source = readFileSync(path, "utf8");
  for (const rule of secretPatterns) {
    if (rule.pattern.test(source)) {
      failures.push(`${relative(root, path)}: ${rule.label}`);
    }
  }

  if (path.includes(`${join("src", "data")}`) && !path.endsWith(".test.ts")) {
    if (/\.(?:insert|update|upsert|delete|rpc)\s*\(/.test(source)) {
      failures.push(
        `${relative(root, path)}: mutation or RPC call in data layer`,
      );
    }
    if (/select\s*\(\s*["']\*["']/.test(source)) {
      failures.push(`${relative(root, path)}: wildcard SELECT`);
    }
  }

  if (/^["']use client["'];/m.test(source)) {
    if (
      /(?:\bpostgres\b|creator_app|CREATOR_ANALYTICS_(?:LABEL_|PREFERENCES_|SCHEDULE_)?DATABASE_URL|creator_analytics_web_(?:reader|labeler|approver|scheduler)|\/rest\/v1\/)/.test(
        source,
      )
    ) {
      failures.push(
        `${relative(root, path)}: server data access in a browser module`,
      );
    }
  }
}

const staticDirectory = join(root, ".next", "static");
for (const path of filesBelow(staticDirectory)) {
  const source = readFileSync(path, "utf8");
  if (
    /CREATOR_ANALYTICS_(?:LABEL_)?DATABASE_URL|creator_analytics_web_(?:reader|labeler)|creator_app/.test(
      source,
    )
  ) {
    failures.push(
      `${relative(root, path)}: server database detail in browser build output`,
    );
  }
}

if (failures.length > 0) {
  throw new Error(`Security scan failed:\n${failures.join("\n")}`);
}

console.log(
  `Security scan passed (${scanFiles.length} source/configuration files checked).`,
);
