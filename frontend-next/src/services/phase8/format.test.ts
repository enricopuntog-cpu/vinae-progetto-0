import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { destinationHref } from "@/lib/phase8/format";
import { listingLookupField } from "@/services/listing-service";

const LISTING_ID = "10000000-0000-4000-8000-000000000001";
const OWNER_ID = "cf000000-0000-4000-8000-000000000001";

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

  it("una destinazione Cantina apre la Cantina pubblica di quel profilo", () => {
    expect(destinationHref({ kind: "cellar", profileId: OWNER_ID })).toBe(
      `/profilo/${OWNER_ID}/cantina`,
    );
  });

  it("l identificativo del profilo e codificato, non interpolato alla cieca", () => {
    expect(destinationHref({ kind: "cellar", profileId: "a/../b" })).toBe(
      "/profilo/a%2F..%2Fb/cantina",
    );
  });

  it("le destinazioni precedenti non cambiano percorso", () => {
    expect(destinationHref({ kind: "none" })).toBeNull();
    expect(destinationHref({ kind: "conversation", conversationId: "c1" })).toBe(
      "/messaggi?conversation=c1",
    );
    expect(destinationHref({ kind: "order", orderId: "o1" })).toBe("/ordine/o1");
    expect(destinationHref({ kind: "club", clubSlug: "amici-del-nebbiolo" })).toBe(
      "/community/amici-del-nebbiolo",
    );
  });
});

// Nessun renderer DOM in questo repository: il comportamento del componente si
// verifica sul suo sorgente, come in `contract.test.ts`.
describe("contratto NotificationItem", () => {
  const item = readFileSync(
    join(import.meta.dir, "../../components/vinea/notifications/NotificationItem.tsx"),
    "utf8",
  );

  it("il percorso arriva da destinationHref e non da una stringa scritta a mano", () => {
    expect(item).toContain("const href = destinationHref(notification.destination);");
    expect(item).not.toMatch(/href=\{[`"']\//);
  });

  it("collegamento quando c e una destinazione, pulsante quando non c e", () => {
    expect(item).toContain("href ? (");
    expect(item).toMatch(/<Link href=\{href\}/);
    expect(item).toMatch(/<button onClick=\{\(\) => onRead\(notification\.id\)\}/);
  });

  it("segna letta in entrambi i rami", () => {
    expect(item.match(/onRead\(notification\.id\)/g)).toHaveLength(2);
  });
});
