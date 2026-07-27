import type { ZodType } from "zod";

const configuredBaseUrl = (import.meta.env.VITE_API_BASE_URL ?? "").trim().replace(/\/+$/, "");

export type AccessTokenProvider = () => string | null | Promise<string | null>;

let accessTokenProvider: AccessTokenProvider | undefined;

/**
 * Collega il provider di identità scelto dall'applicazione senza vincolare
 * questo client a Supabase, Auth0 o a un altro vendor.
 */
export function configureAccessTokenProvider(provider?: AccessTokenProvider): void {
  accessTokenProvider = provider;
}

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export function apiUrl(path: string): string {
  if (!path.startsWith("/")) {
    throw new Error(`Il percorso API deve iniziare con "/": ${path}`);
  }
  return `${configuredBaseUrl}${path}`;
}

export async function apiResponse(path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  if (!headers.has("Accept")) headers.set("Accept", "application/json");
  const accessToken = await accessTokenProvider?.();
  if (accessToken && !headers.has("Authorization")) {
    headers.set("Authorization", `Bearer ${accessToken}`);
  }

  const response = await fetch(apiUrl(path), {
    ...init,
    // Le API private usano Bearer token. Non inviare cookie cross-origin:
    // il backend mantiene CORS credentials disabilitato intenzionalmente.
    credentials: "omit",
    headers,
  });

  if (!response.ok) {
    throw new ApiError("La richiesta non è stata completata.", response.status);
  }
  return response;
}

export async function apiJson<T>(
  path: string,
  schema: ZodType<T>,
  init: RequestInit = {},
): Promise<T> {
  const response = await apiResponse(path, init);
  return schema.parse(await response.json());
}

export function jsonRequest(body: unknown, init: RequestInit = {}): RequestInit {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json");
  return {
    ...init,
    headers,
    body: JSON.stringify(body),
  };
}
