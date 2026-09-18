import { createCspReportHandler } from "@/lib/csp-report";

export const runtime = "nodejs";
export const POST = createCspReportHandler((reports) => {
  console.info("[CSP]", JSON.stringify(reports));
});
