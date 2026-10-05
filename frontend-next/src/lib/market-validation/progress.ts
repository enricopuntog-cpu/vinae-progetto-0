import { MARKET_VALIDATION_DEMO_LISTINGS } from "./demo-data";

export const MARKET_VALIDATION_PROGRESS_STORAGE_KEY =
  "vinea:market-validation:progress:v2";

export type MarketValidationDemoId = `mv_demo_${string}`;

export type MarketValidationProgress = Readonly<{
  buyerCompleted: boolean;
  sellerCompleted: boolean;
  aiPreviewViewed: boolean;
  aiInterest: boolean;
  clubViewed: boolean;
  favoriteDemoIds: readonly MarketValidationDemoId[];
}>;

export const INITIAL_MARKET_VALIDATION_PROGRESS: MarketValidationProgress = {
  buyerCompleted: false,
  sellerCompleted: false,
  aiPreviewViewed: false,
  aiInterest: false,
  clubViewed: false,
  favoriteDemoIds: [],
};

type BrowserStorage = Pick<Storage, "getItem" | "setItem" | "removeItem">;

const ALLOWED_KEYS = [
  "buyerCompleted",
  "sellerCompleted",
  "aiPreviewViewed",
  "aiInterest",
  "clubViewed",
  "favoriteDemoIds",
] as const;
const DEMO_IDS = new Set<string>(
  MARKET_VALIDATION_DEMO_LISTINGS.map((listing) => listing.id),
);

function isProgress(value: unknown): value is MarketValidationProgress {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const candidate = value as Record<string, unknown>;
  const keys = Object.keys(candidate);
  if (
    keys.length !== ALLOWED_KEYS.length ||
    keys.some((key) => !ALLOWED_KEYS.includes(key as (typeof ALLOWED_KEYS)[number]))
  ) {
    return false;
  }

  const favorites = candidate.favoriteDemoIds;
  return (
    typeof candidate.buyerCompleted === "boolean" &&
    typeof candidate.sellerCompleted === "boolean" &&
    typeof candidate.aiPreviewViewed === "boolean" &&
    typeof candidate.aiInterest === "boolean" &&
    typeof candidate.clubViewed === "boolean" &&
    Array.isArray(favorites) &&
    favorites.length <= MARKET_VALIDATION_DEMO_LISTINGS.length &&
    new Set(favorites).size === favorites.length &&
    favorites.every(
      (id): id is MarketValidationDemoId =>
        typeof id === "string" && DEMO_IDS.has(id),
    )
  );
}

function copyProgress(progress: MarketValidationProgress): MarketValidationProgress {
  return { ...progress, favoriteDemoIds: [...progress.favoriteDemoIds] };
}

/** Il progresso locale è un aiuto UX e non una fonte autorevole per l'RPC. */
export function readMarketValidationProgress(
  storage: BrowserStorage | null | undefined,
): MarketValidationProgress | null {
  if (!storage) return null;
  try {
    const raw = storage.getItem(MARKET_VALIDATION_PROGRESS_STORAGE_KEY);
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (isProgress(parsed)) return copyProgress(parsed);
    storage.removeItem(MARKET_VALIDATION_PROGRESS_STORAGE_KEY);
  } catch {
    // Un JSON corrotto va eliminato; uno storage bloccato può rifiutare anche la pulizia.
    try {
      storage.removeItem(MARKET_VALIDATION_PROGRESS_STORAGE_KEY);
    } catch {
      // Nessun fallback: il test riparte comunque senza usare il payload.
    }
  }
  return null;
}

export function writeMarketValidationProgress(
  storage: BrowserStorage | null | undefined,
  progress: MarketValidationProgress,
): boolean {
  if (!storage || !isProgress(progress)) return false;
  try {
    storage.setItem(
      MARKET_VALIDATION_PROGRESS_STORAGE_KEY,
      JSON.stringify(copyProgress(progress)),
    );
    return true;
  } catch {
    return false;
  }
}

export function clearMarketValidationProgress(
  storage: BrowserStorage | null | undefined,
): void {
  if (!storage) return;
  try {
    storage.removeItem(MARKET_VALIDATION_PROGRESS_STORAGE_KEY);
  } catch {
    // Nessun fallback: la storage locale può restare indisponibile.
  }
}

export function restoreMarketValidationProgress(
  storage: BrowserStorage | null | undefined,
  resumed: boolean,
): MarketValidationProgress {
  if (!resumed) {
    clearMarketValidationProgress(storage);
    return copyProgress(INITIAL_MARKET_VALIDATION_PROGRESS);
  }
  return (
    readMarketValidationProgress(storage) ??
    copyProgress(INITIAL_MARKET_VALIDATION_PROGRESS)
  );
}
