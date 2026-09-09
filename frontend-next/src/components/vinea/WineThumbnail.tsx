"use client";

import Image from "next/image";
import { useState } from "react";
import { SafeImage } from "@/components/vinea/States";
import { immaginePubblicaOttimizzabile } from "@/lib/images/immagini-pubbliche";

export function WineThumbnail({ src, alt, className, sizes }: {
  src?: string;
  alt: string;
  className: string;
  sizes: string;
}) {
  const [fallita, setFallita] = useState<string | null>(null);
  if (!src || fallita === src || !immaginePubblicaOttimizzabile(src, process.env.NEXT_PUBLIC_SUPABASE_URL)) {
    return <SafeImage src={fallita === src ? undefined : src} alt={alt} className={className} fallbackLabel="Foto non disponibile" />;
  }
  return (
    <Image src={src} alt={alt} width={600} height={750} sizes={sizes}
      className={className} onError={() => setFallita(src)} />
  );
}
