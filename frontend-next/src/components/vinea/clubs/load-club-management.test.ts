import { describe, expect, it } from "bun:test";
import { loadClubManagement, type ClubManagementReader } from "./load-club-management";
import type { ManagedClub } from "@/services/phase12/club-governance-service";

const club: ManagedClub = {
  slug: "circolo",
  nome: "Circolo",
  descrizione: "Club di prova",
  categoria: null,
  territorio: null,
  accessType: "chiuso",
  requirements: null,
  postingMode: "OPEN",
  approvalStatus: "approvato",
  ownerId: "owner",
};

const fakeReader = (managed: ManagedClub[]) => {
  const calls: string[] = [];
  const reader: ClubManagementReader = {
    managedClubs: async () => { calls.push("managedClubs"); return managed; },
    members: async () => { calls.push("members"); return []; },
    joinRequests: async () => { calls.push("joinRequests"); return []; },
    rules: async () => { calls.push("rules"); return []; },
    links: async () => { calls.push("links"); return []; },
  };
  return { reader, calls };
};

describe("caricamento del pannello di gestione Club", () => {
  it("non interroga le viste di gestione per un visitatore senza sessione", async () => {
    const { reader, calls } = fakeReader([club]);
    expect(await loadClubManagement("circolo", async () => null, reader)).toBeNull();
    expect(calls).toEqual([]);
  });

  it("non legge i dettagli di un Club che l'utente non gestisce", async () => {
    const { reader, calls } = fakeReader([]);
    expect(await loadClubManagement("circolo", async () => "membro", reader)).toBeNull();
    expect(calls).toEqual(["managedClubs"]);
  });

  it("carica membri, richieste, regolamento e link per owner o moderatore", async () => {
    const { reader, calls } = fakeReader([club]);
    const snapshot = await loadClubManagement("circolo", async () => "moderatore", reader);
    expect(snapshot?.club.slug).toBe("circolo");
    expect(snapshot?.currentUserId).toBe("moderatore");
    expect(calls.sort()).toEqual(["joinRequests", "links", "managedClubs", "members", "rules"]);
  });
});
