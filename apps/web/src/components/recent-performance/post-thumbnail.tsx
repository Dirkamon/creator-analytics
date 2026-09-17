"use client";

import { ImageOff } from "lucide-react";
import Image from "next/image";
import { useState } from "react";
import { sanitizeThumbnailUrl } from "@/lib/thumbnail-url";

/** The read model supplies a validated thumbnail URL, never a video source. */
export function PostThumbnail({
  src,
  clipName,
}: {
  src: string | null;
  clipName: string;
}) {
  const [failedSrc, setFailedSrc] = useState<string | null>(null);
  const safeSrc = sanitizeThumbnailUrl(src);
  const unavailable = !safeSrc || failedSrc === safeSrc;

  return (
    <div className="border-line bg-canvas relative aspect-[9/16] w-24 shrink-0 overflow-hidden rounded-xl border sm:w-32">
      {unavailable ? (
        <div className="text-muted flex h-full flex-col items-center justify-center gap-2 p-3 text-center">
          <ImageOff aria-hidden size={22} />
          <span className="text-xs leading-5">No thumbnail available</span>
        </div>
      ) : (
        <Image
          src={safeSrc!}
          alt={`Thumbnail for ${clipName}`}
          fill
          sizes="(min-width: 640px) 128px, 96px"
          className="object-contain"
          loading="lazy"
          decoding="async"
          referrerPolicy="no-referrer"
          // Reuse the hosted still directly: no image proxy, storage, or video download.
          unoptimized
          onError={() => setFailedSrc(safeSrc)}
        />
      )}
    </div>
  );
}
