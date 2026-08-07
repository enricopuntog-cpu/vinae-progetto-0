import { describe, expect, it } from "bun:test";
import { destinationHref } from "@/lib/phase8/format";
import { listingLookupField } from "@/services/listing-service";

const LISTING_ID = "10000000-0000-4000-8000-000000000001";

describe("destinazioni tipizzate Fase 8", () => {
  it("una destinazione listing apre il dettaglio senza URL salvato nel database", () => {
    expect(destinationHref({ kind: "listing", listingId: LISTING_ID })).toBe(
      `/annuncio/${LISTING_ID}`,
    );
  });

  it("il dettaglio annuncio distingue UUID interno e slug pubblico", () => {
    expect(listingLookupField(LISTING_ID)).toBe("id");
    expect(listingLookupField("monfortino-2015")).toBe("slug");
  });
});
