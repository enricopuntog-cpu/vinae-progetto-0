import { NextRequest, NextResponse } from "next/server";
import { buildPageCsp } from "./lib/csp";

export function proxy(request: NextRequest) {
  const nonce = Buffer.from(crypto.randomUUID()).toString("base64");
  const policy = buildPageCsp(nonce, process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NODE_ENV === "development");
  const headers = new Headers(request.headers);
  // Overwrite client-supplied values before Next renders its inline bootstrap.
  headers.set("x-nonce", nonce);
  headers.set("Content-Security-Policy", policy);
  const response = NextResponse.next({ request: { headers } });
  response.headers.set("Content-Security-Policy", policy);
  response.headers.set("Cache-Control", "private, no-store");
  response.headers.set("Netlify-CDN-Cache-Control", "no-store");
  return response;
}

export const config = {
  // Include RSC/prefetch requests as well: never let a forged prefetch header
  // bypass the policy on a document navigation. Static assets don't need nonce.
  matcher: ["/((?!api/|_next/static/|_next/image|images/|favicon.ico|robots.txt|sitemap.xml).*)"],
};
