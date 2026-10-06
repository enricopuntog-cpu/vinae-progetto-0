import { describe, expect, it } from "bun:test";
import {
  MARKET_VALIDATION_CSV_HEADERS,
  buildMarketValidationParticipantsCsv,
  escapeMarketValidationCsvCell,
  formatPercentage,
  parseMarketValidationAdminParticipant,
  parseMarketValidationAdminSummary,
  parseMarketValidationParticipantFilter,
  percentage,
  type MarketValidationAdminParticipant,
} from "@/lib/market-validation/admin-analytics";

const participant: MarketValidationAdminParticipant = {
  participantCode: "V017",
  sessionsCount: 2,
  firstStartedAt: "2026-10-06T10:00:00.000Z",
  lastStartedAt: "2026-10-06T11:00:00.000Z",
  lastCompletedAt: "2026-10-06T12:00:00.000Z",
  completed: true,
  marketplaceViewed: 2,
  demoListingViewed: 1,
  favoriteAdded: 1,
  checkoutStarted: 1,
  shippingCostViewed: 1,
  checkoutBetaCompleted: 1,
  sellStarted: 2,
  sellPhotoSelected: 0,
  sellCompleted: 1,
  aiPreviewViewed: 1,
  aiInterestClicked: 1,
  clubViewed: 1,
  betaCompleted: 1,
};

describe("MV3 admin analytics", () => {
  it("normalizza KPI, funnel e tassi numerici", () => {
    expect(
      parseMarketValidationAdminSummary({
        testersStarted: 4,
        testersCompleted: 2,
        completionRate: 50,
        totalSessions: 5,
        uniqueCodes: 4,
        buyer: { started: 4, marketplaceViewed: 3, demoListingViewed: 2 },
        seller: { started: 4, sellStarted: 3, sellPhotoSelected: 1, sellCompleted: 2 },
        ai: { previewViewed: 2, interestClicked: 1, interestRate: 50 },
        club: { viewed: 1, viewedRate: 25 },
      }),
    ).toEqual({
      testersStarted: 4,
      testersCompleted: 2,
      completionRate: 50,
      totalSessions: 5,
      uniqueCodes: 4,
      buyer: {
        started: 4,
        marketplaceViewed: 3,
        demoListingViewed: 2,
        checkoutStarted: 0,
        shippingCostViewed: 0,
        checkoutBetaCompleted: 0,
      },
      seller: { started: 4, sellStarted: 3, sellPhotoSelected: 1, sellCompleted: 2 },
      ai: { previewViewed: 2, interestClicked: 1, interestRate: 50 },
      club: { viewed: 1, viewedRate: 25 },
    });
  });

  it("fallisce chiuso su valori malformati e rende zero i tassi senza denominatore", () => {
    expect(parseMarketValidationAdminSummary({ completionRate: 120, ai: { interestRate: -1 } })).toEqual(
      expect.objectContaining({ completionRate: 100, ai: expect.objectContaining({ interestRate: 0 }) }),
    );
    expect(percentage(3, 0)).toBe(0);
    expect(percentage(1, 2)).toBe(50);
    expect(formatPercentage(33.333)).toBe("33,3%");
  });

  it("riusa il contratto V001-V999 per il filtro", () => {
    expect(parseMarketValidationParticipantFilter(" v017 ")).toBe("V017");
    expect(parseMarketValidationParticipantFilter("  ")).toBeNull();
    for (const invalid of ["V000", "V1000", "V01", "V017' OR TRUE"] ) {
      expect(parseMarketValidationParticipantFilter(invalid)).toBeUndefined();
    }
  });

  it("mappa una sola riga pseudonima e scarta codici inattesi", () => {
    expect(
      parseMarketValidationAdminParticipant({
        participant_code: "V017",
        sessions_count: 2,
        first_started_at: participant.firstStartedAt,
        completed: true,
        sell_photo_selected: 1,
      }),
    ).toEqual(
      expect.objectContaining({
        participantCode: "V017",
        sessionsCount: 2,
        completed: true,
        sellPhotoSelected: 1,
      }),
    );
    expect(parseMarketValidationAdminParticipant({ participant_code: "V000" })).toBeNull();
  });

  it("mantiene l'ordine fisso delle 19 colonne CSV", () => {
    expect(MARKET_VALIDATION_CSV_HEADERS).toEqual([
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
    ]);
  });

  it("usa BOM, separatore punto e virgola e una riga per codice", () => {
    const csv = buildMarketValidationParticipantsCsv([participant, { ...participant, participantCode: "V018" }]);
    expect(csv.startsWith("﻿participant_code;sessions_count;")).toBeTrue();
    expect(csv.endsWith("\r\n")).toBeTrue();
    expect(csv.split("\r\n").filter(Boolean)).toHaveLength(3);
    expect(csv).not.toInclude("capability");
    expect(csv).not.toInclude("session_id");
    expect(csv).not.toInclude("metadata");
  });

  it("quota delimitatori e virgolette e neutralizza le formule", () => {
    expect(escapeMarketValidationCsvCell("a;b")).toBe('"a;b"');
    expect(escapeMarketValidationCsvCell('a"b')).toBe('"a""b"');
    expect(escapeMarketValidationCsvCell("a\nb")).toBe('"a\nb"');
    for (const unsafe of ["=1+1", "+SUM(A1)", "-2+3", "@cmd"]) {
      expect(escapeMarketValidationCsvCell(unsafe).startsWith("'")).toBeTrue();
    }
  });
});
