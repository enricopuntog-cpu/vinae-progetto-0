import type { NextConfig } from "next";
import { SECURITY_HEADERS } from "./src/lib/security-headers";

const nextConfig: NextConfig = {
  poweredByHeader: false,
  // Solo il vecchio host pubblico: le anteprime conservano il proprio URL.
  redirects: async () => [{
    source: "/:path*",
    has: [{ type: "host", value: "timely-lokum-43a12e.netlify.app" }],
    destination: "https://vineawineclub.com/:path*",
    permanent: true,
  }],
  images: {
    remotePatterns: process.env.NEXT_PUBLIC_SUPABASE_URL
      ? [new URL("/storage/v1/object/public/annunci/**", process.env.NEXT_PUBLIC_SUPABASE_URL)]
      : [],
  },
  headers: async () => [
    {
      source: "/:path*",
      headers: [{ key: "X-Robots-Tag", value: "noindex, nofollow" }, ...SECURITY_HEADERS],
    },
  ],
};

export default nextConfig;
