export function PlatformBadge({ platform }: { platform: string }) {
  const normalized = platform.trim().toLowerCase();
  const tone =
    normalized === "youtube"
      ? "border-red-400/25 bg-red-400/10 text-red-200"
      : normalized === "tiktok"
        ? "border-accent/25 bg-accent/10 text-accent"
        : "border-line bg-foreground/5 text-secondary";
  const label =
    normalized === "tiktok"
      ? "TikTok"
      : normalized === "youtube"
        ? "YouTube"
        : platform;

  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-1 text-[0.68rem] font-semibold tracking-[0.08em] uppercase ${tone}`}
    >
      {label}
    </span>
  );
}
