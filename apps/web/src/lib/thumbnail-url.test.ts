import { describe, expect, it } from "vitest";
import { sanitizeThumbnailUrl } from "@/lib/thumbnail-url";

describe("thumbnail URL boundary", () => {
  it("preserves Buffer's signed thumbnail query without exposing a fragment", () => {
    expect(
      sanitizeThumbnailUrl(
        " https://images.buffer.com/thumbnail/example?url=https%3A%2F%2Fexample.invalid%2Fclip.mp4#fragment ",
      ),
    ).toBe(
      "https://images.buffer.com/thumbnail/example?url=https%3A%2F%2Fexample.invalid%2Fclip.mp4",
    );
  });

  it.each([
    undefined,
    null,
    "",
    {},
    123,
    "javascript:alert(1)",
    "data:image/svg+xml,test",
    "//images.buffer.com/thumbnail/example",
    "http://images.buffer.com/thumbnail/example",
    "https://images.buffer.com.evil.invalid/thumbnail/example",
    "https://evil.invalid/thumbnail/example",
    "https://localhost/thumbnail/example",
    "https://127.0.0.1/thumbnail/example",
    "https://user:password@images.buffer.com/thumbnail/example",
    "https://images.buffer.com:444/thumbnail/example",
    "https://images.buffer.com/clip.mp4",
    "https://images.buffer.com/thumbnail/",
    "https://images.buffer.com/thumbnail/../clip.mp4",
    "https://images.buffer.com/thumbnail/" + "a".repeat(4096),
  ])("rejects unsupported image source %j", (value) => {
    expect(sanitizeThumbnailUrl(value)).toBeNull();
  });
});
