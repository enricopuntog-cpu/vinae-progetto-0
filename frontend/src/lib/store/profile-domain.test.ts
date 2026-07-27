import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "bun:test";
import { useProfileDomain } from "./profile-domain";

vi.mock("sonner", () => ({
  toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
}));

function renderProfileDomain() {
  const pushNotifica = vi.fn();
  const hook = renderHook(() => useProfileDomain({ pushNotifica }));
  return { ...hook, pushNotifica };
}

describe("useProfileDomain", () => {
  it("registra un account aggiornando profilo ed email non verificata", () => {
    const { result } = renderProfileDomain();

    act(() =>
      result.current.registerAccount({
        username: "nuovo_utente",
        email: "nuovo@demo.it",
        dob: "1995-01-01",
        maggiorenne: true,
      }),
    );

    expect(result.current.registrato).toBe(true);
    expect(result.current.emailStatus).toBe("non_verificata");
    expect(result.current.profilo.username).toBe("nuovo_utente");
  });

  it("verifica l'email e promuove l'età dichiarata se era da verificare", () => {
    const { result } = renderProfileDomain();
    act(() =>
      result.current.registerAccount({
        username: "u",
        email: "e@demo.it",
        dob: "1995-01-01",
        maggiorenne: false,
      }),
    );
    expect(result.current.ageStatus).toBe("da_verificare");

    act(() => result.current.verifyEmail());

    expect(result.current.emailStatus).toBe("verificata");
    expect(result.current.ageStatus).toBe("dichiarata");
  });

  it("abilita il venditore quando la verifica identità ha successo", () => {
    const { result, pushNotifica } = renderProfileDomain();

    act(() => result.current.completeIdentityVerification("verificata"));

    expect(result.current.identityStatus).toBe("verificata");
    expect(result.current.sellerStatus).toBe("abilitato");
    expect(pushNotifica).toHaveBeenCalled();
  });

  it("non abilita il venditore quando la verifica identità è rifiutata", () => {
    const { result } = renderProfileDomain();

    act(() => result.current.completeIdentityVerification("rifiutata"));

    expect(result.current.identityStatus).toBe("rifiutata");
    expect(result.current.sellerStatus).toBe("non_abilitato");
  });

  it("resetOnboarding non tocca le preferenze di regione/tipologia/fascia prezzo", () => {
    const { result } = renderProfileDomain();

    act(() => result.current.resetOnboarding());

    expect(result.current.registrato).toBe(false);
    expect(result.current.regioniPreferite.size).toBeGreaterThan(0);
    expect(result.current.fasciaPrezzo).not.toBeNull();
  });

  it("resetForGuest azzera anche le preferenze di regione/tipologia/fascia prezzo", () => {
    const { result } = renderProfileDomain();

    act(() => result.current.resetForGuest());

    expect(result.current.registrato).toBe(false);
    expect(result.current.regioniPreferite.size).toBe(0);
    expect(result.current.tipologiePreferite.size).toBe(0);
    expect(result.current.fasciaPrezzo).toBeNull();
  });

  it("calcola il completamento profilo in base allo stato corrente", () => {
    const { result } = renderProfileDomain();

    expect(result.current.profileCompletion.perc).toBeGreaterThan(0);

    act(() => result.current.resetForGuest());

    expect(result.current.profileCompletion.perc).toBeLessThan(100);
  });
});
