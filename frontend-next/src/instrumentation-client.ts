import { reportClientEvent } from "./lib/observability/client";

window.addEventListener("error", () => reportClientEvent("client_error"));
window.addEventListener("unhandledrejection", () => reportClientEvent("client_rejection"));
