import { z } from "zod";

const emailSchema = z.email().transform((email) => email.trim().toLowerCase());

export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

export function parseEmailAllowlist(value: string): ReadonlySet<string> {
  const entries = value
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);

  if (entries.length === 0) {
    throw new Error("At least one approved email address is required.");
  }

  const parsed = entries.map((entry) => emailSchema.parse(entry));
  return new Set(parsed);
}

export function isEmailAllowed(
  email: string,
  allowedEmails: ReadonlySet<string>,
): boolean {
  return allowedEmails.has(normalizeEmail(email));
}
