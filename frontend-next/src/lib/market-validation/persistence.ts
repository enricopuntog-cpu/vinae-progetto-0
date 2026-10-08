import type {
  MarketValidationParticipantCode,
  MarketValidationSession,
} from "@/services/types";

const STORAGE_KEY = "vinea:market-validation:session:v1";
// QV2 usa una chiave propria: una capability MV1 rimasta nel browser non può
// essere ripresa dal questionario (il database la rifiuta) e non deve bloccare
// l'avvio di un nuovo test.
export const QV2_SESSION_STORAGE_KEY = "vinea:market-validation:qv2-session:v1";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PARTICIPANT_CODE = /^V(00[1-9]|0[1-9][0-9]|[1-9][0-9]{2})$/;

type BrowserStorage = Pick<Storage, "getItem" | "setItem" | "removeItem">;

/** Il browser conserva solo la capability e il codice necessari alla ripresa. */
export type MarketValidationSessionReference = Readonly<{
  participantCode: MarketValidationParticipantCode;
  capability: string;
}>;

function isSessionReference(value: unknown): value is MarketValidationSessionReference {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Record<string, unknown>;
  return (
    Object.keys(candidate).length === 2 &&
    typeof candidate.capability === "string" &&
    UUID.test(candidate.capability) &&
    typeof candidate.participantCode === "string" &&
    PARTICIPANT_CODE.test(candidate.participantCode)
  );
}

/** LocalStorage è un aiuto di ripresa, mai una fonte autorevole. */
export function readMarketValidationSession(
  storage: BrowserStorage | null | undefined,
  key: string = STORAGE_KEY,
): MarketValidationSessionReference | null {
  if (!storage) return null;
  try {
    const raw = storage.getItem(key);
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (isSessionReference(parsed)) return parsed;
    storage.removeItem(key);
  } catch {
    // Storage bloccato o payload corrotto: la route resta utilizzabile da zero.
  }
  return null;
}

export function writeMarketValidationSession(
  storage: BrowserStorage | null | undefined,
  session: MarketValidationSession,
  key: string = STORAGE_KEY,
): boolean {
  const reference: MarketValidationSessionReference = {
    participantCode: session.participantCode,
    capability: session.capability,
  };
  if (!storage || !isSessionReference(reference)) return false;
  try {
    storage.setItem(key, JSON.stringify(reference));
    return true;
  } catch {
    return false;
  }
}

export function clearMarketValidationSession(
  storage: BrowserStorage | null | undefined,
  key: string = STORAGE_KEY,
): void {
  if (!storage) return;
  try {
    storage.removeItem(key);
  } catch {
    // Nessun cookie o fallback: una storage indisponibile resta semplicemente vuota.
  }
}

export function newMarketValidationCapability(): string {
  return crypto.randomUUID();
}
