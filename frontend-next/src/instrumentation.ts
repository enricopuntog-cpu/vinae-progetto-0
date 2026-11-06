import type { Instrumentation } from "next";

/** Native Next hook, both runtimes. Deliberately never inspect error/request. */
export const onRequestError: Instrumentation.onRequestError = (_error, _request, context) => {
  const kind = ["render", "route", "action", "proxy"].includes(context.routeType)
    ? context.routeType : "unknown";
  console.error("[VINEA_OBS]", JSON.stringify({ event: "server_error", kind }));
};
