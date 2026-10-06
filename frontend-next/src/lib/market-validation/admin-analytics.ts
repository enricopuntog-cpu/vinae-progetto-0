import { parseMarketValidationParticipantCode } from "@/lib/market-validation/contract";
import type { MarketValidationParticipantCode } from "@/services/types";

export const MARKET_VALIDATION_ADMIN_PAGE_SIZE = 100;
export const MARKET_VALIDATION_EXPORT_PAGE_SIZE = 200;
export const MARKET_VALIDATION_MAX_PARTICIPANTS = 999;

export type MarketValidationAdminSummary = {
  testersStarted: number;
  testersCompleted: number;
  completionRate: number;
  totalSessions: number;
  uniqueCodes: number;
  buyer: {
    started: number;
    marketplaceViewed: number;
    demoListingViewed: number;
    checkoutStarted: number;
    shippingCostViewed: number;
    checkoutBetaCompleted: number;
  };
  seller: {
    started: number;
    sellStarted: number;
    sellPhotoSelected: number;
    sellCompleted: number;
  };
  ai: {
    previewViewed: number;
    interestClicked: number;
    interestRate: number;
  };
  club: {
    viewed: number;
    viewedRate: number;
  };
};

export type MarketValidationAdminParticipant = {
  participantCode: MarketValidationParticipantCode;
  sessionsCount: number;
  firstStartedAt: string | null;
  lastStartedAt: string | null;
  lastCompletedAt: string | null;
  completed: boolean;
  marketplaceViewed: number;
  demoListingViewed: number;
  favoriteAdded: number;
  checkoutStarted: number;
  shippingCostViewed: number;
  checkoutBetaCompleted: number;
  sellStarted: number;
  sellPhotoSelected: number;
  sellCompleted: number;
  aiPreviewViewed: number;
  aiInterestClicked: number;
  clubViewed: number;
  betaCompleted: number;
};

export type MarketValidationParticipantFilter = MarketValidationParticipantCode | null;

export const EMPTY_MARKET_VALIDATION_ADMIN_SUMMARY: MarketValidationAdminSummary = {
  testersStarted: 0,
  testersCompleted: 0,
  completionRate: 0,
  totalSessions: 0,
  uniqueCodes: 0,
  buyer: {
    started: 0,
    marketplaceViewed: 0,
    demoListingViewed: 0,
    checkoutStarted: 0,
    shippingCostViewed: 0,
    checkoutBetaCompleted: 0,
  },
  seller: {
    started: 0,
    sellStarted: 0,
    sellPhotoSelected: 0,
    sellCompleted: 0,
  },
  ai: { previewViewed: 0, interestClicked: 0, interestRate: 0 },
  club: { viewed: 0, viewedRate: 0 },
};

const asNumber = (value: unknown): number =>
  typeof value === "number" && Number.isFinite(value) ? value : 0;

const asCount = (value: unknown): number => Math.max(0, Math.trunc(asNumber(value)));

const asRate = (value: unknown): number => Math.min(100, Math.max(0, asNumber(value)));

const asObject = (value: unknown): Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};

const asNullableIso = (value: unknown): string | null =>
  typeof value === "string" && !Number.isNaN(Date.parse(value)) ? value : null;

export function parseMarketValidationAdminSummary(value: unknown): MarketValidationAdminSummary {
  const source = asObject(value);
  const buyer = asObject(source.buyer);
  const seller = asObject(source.seller);
  const ai = asObject(source.ai);
  const club = asObject(source.club);

  return {
    testersStarted: asCount(source.testersStarted),
    testersCompleted: asCount(source.testersCompleted),
    completionRate: asRate(source.completionRate),
    totalSessions: asCount(source.totalSessions),
    uniqueCodes: asCount(source.uniqueCodes),
    buyer: {
      started: asCount(buyer.started),
      marketplaceViewed: asCount(buyer.marketplaceViewed),
      demoListingViewed: asCount(buyer.demoListingViewed),
      checkoutStarted: asCount(buyer.checkoutStarted),
      shippingCostViewed: asCount(buyer.shippingCostViewed),
      checkoutBetaCompleted: asCount(buyer.checkoutBetaCompleted),
    },
    seller: {
      started: asCount(seller.started),
      sellStarted: asCount(seller.sellStarted),
      sellPhotoSelected: asCount(seller.sellPhotoSelected),
      sellCompleted: asCount(seller.sellCompleted),
    },
    ai: {
      previewViewed: asCount(ai.previewViewed),
      interestClicked: asCount(ai.interestClicked),
      interestRate: asRate(ai.interestRate),
    },
    club: {
      viewed: asCount(club.viewed),
      viewedRate: asRate(club.viewedRate),
    },
  };
}

export function parseMarketValidationAdminParticipant(
  value: unknown,
): MarketValidationAdminParticipant | null {
  const source = asObject(value);
  const participantCode =
    typeof source.participant_code === "string"
      ? parseMarketValidationParticipantCode(source.participant_code)
      : null;
  if (!participantCode) return null;

  return {
    participantCode,
    sessionsCount: asCount(source.sessions_count),
    firstStartedAt: asNullableIso(source.first_started_at),
    lastStartedAt: asNullableIso(source.last_started_at),
    lastCompletedAt: asNullableIso(source.last_completed_at),
    completed: source.completed === true,
    marketplaceViewed: asCount(source.marketplace_viewed),
    demoListingViewed: asCount(source.demo_listing_viewed),
    favoriteAdded: asCount(source.favorite_added),
    checkoutStarted: asCount(source.checkout_started),
    shippingCostViewed: asCount(source.shipping_cost_viewed),
    checkoutBetaCompleted: asCount(source.checkout_beta_completed),
    sellStarted: asCount(source.sell_started),
    sellPhotoSelected: asCount(source.sell_photo_selected),
    sellCompleted: asCount(source.sell_completed),
    aiPreviewViewed: asCount(source.ai_preview_viewed),
    aiInterestClicked: asCount(source.ai_interest_clicked),
    clubViewed: asCount(source.club_viewed),
    betaCompleted: asCount(source.beta_completed),
  };
}

export function parseMarketValidationParticipantFilter(
  value: string,
): MarketValidationParticipantFilter | undefined {
  if (value.trim() === "") return null;
  return parseMarketValidationParticipantCode(value) ?? undefined;
}

export function percentage(numerator: number, denominator: number): number {
  if (denominator <= 0) return 0;
  return Math.min(100, Math.max(0, (numerator * 100) / denominator));
}

export function formatPercentage(value: number): string {
  return `${new Intl.NumberFormat("it-IT", { maximumFractionDigits: 1 }).format(value)}%`;
}

export const MARKET_VALIDATION_CSV_HEADERS = [
  "participant_code",
  "sessions_count",
  "first_started_at",
  "last_started_at",
  "last_completed_at",
  "completed",
  "marketplace_viewed",
  "demo_listing_viewed",
  "favorite_added",
  "checkout_started",
  "shipping_cost_viewed",
  "checkout_beta_completed",
  "sell_started",
  "sell_photo_selected",
  "sell_completed",
  "ai_preview_viewed",
  "ai_interest_clicked",
  "club_viewed",
  "beta_completed",
] as const;

const csvFormulaPrefix = /^[=+\-@]/;

export function escapeMarketValidationCsvCell(value: string | number | boolean | null): string {
  let cell = value === null ? "" : String(value);
  if (csvFormulaPrefix.test(cell)) cell = `'${cell}`;
  if (/[;"\r\n]/.test(cell)) cell = `"${cell.replaceAll('"', '""')}"`;
  return cell;
}

const participantCsvValues = (
  participant: MarketValidationAdminParticipant,
): Array<string | number | boolean | null> => [
  participant.participantCode,
  participant.sessionsCount,
  participant.firstStartedAt,
  participant.lastStartedAt,
  participant.lastCompletedAt,
  participant.completed,
  participant.marketplaceViewed,
  participant.demoListingViewed,
  participant.favoriteAdded,
  participant.checkoutStarted,
  participant.shippingCostViewed,
  participant.checkoutBetaCompleted,
  participant.sellStarted,
  participant.sellPhotoSelected,
  participant.sellCompleted,
  participant.aiPreviewViewed,
  participant.aiInterestClicked,
  participant.clubViewed,
  participant.betaCompleted,
];

export function buildMarketValidationParticipantsCsv(
  participants: readonly MarketValidationAdminParticipant[],
): string {
  const rows = [
    MARKET_VALIDATION_CSV_HEADERS.join(";"),
    ...participants.map((participant) =>
      participantCsvValues(participant).map(escapeMarketValidationCsvCell).join(";"),
    ),
  ];
  return `﻿${rows.join("\r\n")}\r\n`;
}
