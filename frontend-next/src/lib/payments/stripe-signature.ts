const DEFAULT_TOLERANCE_SECONDS = 300;

type SignatureParts = {
  timestamp: number;
  signatures: string[];
};
const parseSignature = (header: string): SignatureParts | null => {
  const values = header.split(",").map((part) => part.trim().split("=", 2));
  const timestamp = Number(values.find(([key]) => key === "t")?.[1]);
  const signatures = values
    .filter(([key]) => key === "v1")
    .map(([, value]) => value)
    .filter((value): value is string => Boolean(value));
  return Number.isFinite(timestamp) && signatures.length > 0 ? { timestamp, signatures } : null;
};

const toHex = (bytes: ArrayBuffer): string =>
  Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, "0")).join("");

const constantTimeEqual = (left: string, right: string): boolean => {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
};

export const verifyStripeSignature = async ({
  payload,
  header,
  secret,
  nowSeconds = Math.floor(Date.now() / 1000),
  toleranceSeconds = DEFAULT_TOLERANCE_SECONDS,
}: {
  payload: string;
  header: string;
  secret: string;
  nowSeconds?: number;
  toleranceSeconds?: number;
}): Promise<boolean> => {
  const parts = parseSignature(header);
  if (!parts || !secret || Math.abs(nowSeconds - parts.timestamp) > toleranceSeconds) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${parts.timestamp}.${payload}`),
  );
  const expected = toHex(digest);
  return parts.signatures.some((signature) => constantTimeEqual(signature, expected));
};
