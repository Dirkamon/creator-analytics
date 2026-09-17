// Only Buffer's verified static-thumbnail endpoint is allowed. Do not pass
// original video URLs, arbitrary remote images, or database payloads to the UI.
export const BUFFER_THUMBNAIL_ORIGIN = "https://images.buffer.com";

export function sanitizeThumbnailUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 4096) return null;
  try {
    const url = new URL(value.trim());
    if (
      url.origin !== BUFFER_THUMBNAIL_ORIGIN ||
      url.username ||
      url.password ||
      !url.pathname.startsWith("/thumbnail/") ||
      url.pathname === "/thumbnail/"
    )
      return null;
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}
