export const dynamic = "force-dynamic";

/** Liveness only. No database, provider calls, sessions or configuration output. */
export function GET() {
  return Response.json({ status: "ok", service: "vinea-next" }, {
    headers: { "Cache-Control": "no-store" },
  });
}
