import { z } from "zod";

const wholeNumber = z
  .string()
  .regex(/^\d+$/)
  .transform(Number)
  .pipe(z.number().int());
export const preferencesFormSchema = z
  .object({
    revision: z.number().int().positive(),
    tiktok_weekly: wholeNumber.pipe(z.number().min(7).max(28)),
    tiktok_ceiling: wholeNumber.pipe(z.number().min(1).max(4)),
    youtube_weekly: wholeNumber.pipe(z.number().min(7).max(28)),
    youtube_ceiling: wholeNumber.pipe(z.number().min(1).max(4)),
    enabled: z.enum(["true", "false"]).transform((value) => value === "true"),
    confirm: z.literal("on"),
  })
  .refine(
    (value) =>
      value.tiktok_weekly <= value.tiktok_ceiling * 7 &&
      value.youtube_weekly <= value.youtube_ceiling * 7,
  );

export const savedPreferenceSchema = z.object({
  platform: z.enum(["tiktok", "youtube"]),
  posts_per_week: z.number().int().min(7).max(28),
  max_posts_per_day: z.number().int().min(1).max(4),
  min_gap_hours: z.number().int().nonnegative(),
  protected_hours: z.number().int().nonnegative(),
  timezone_name: z.string().min(1),
  revision: z.number().int().positive(),
  enabled: z.boolean(),
  daily_floor: z.literal(1),
  max_shift_hours: z.literal(12),
  allowed_hours: z.literal("all"),
});
export type SavedPreference = z.infer<typeof savedPreferenceSchema>;
export const coverageSchema = z.object({
  buffer_channel_id: z.string().min(1),
  platform: z.enum(["tiktok", "youtube"]),
  timezone_name: z.string().min(1),
  local_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  scheduled_count: z.number().int().nonnegative(),
  planned_count: z.number().int().nonnegative(),
  coverage_note: z.string().nullable(),
});
export type CoverageDay = z.infer<typeof coverageSchema>;
export type PreferencesActionState = {
  status: "idle" | "success" | "error";
  message: string;
  revision?: number;
};
