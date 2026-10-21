"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { StatoInterruttoreAnnunci } from "@/lib/accessori-vendita/annunci-accessori";
import type { CategoriaPubblicazione } from "@/lib/accessori-vendita/annunci-moderazione";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAnnunciAccessoriAdminService } from "@/services/annunci-accessori-service";

/**
 * Interruttori degli annunci Accessori e categorie pubblicabili (VPM-015B2,
 * VPM-015B3), nell'area admin.
 *
 * Due interruttori nel database, entrambi spenti di default: la PREPARAZIONE
 * (bozze) e la PUBBLICAZIONE (annunci visibili al pubblico). Accendere richiede il
 * ruolo di rilascio (decisione del titolare, registrata con motivo e conferma
 * scritta); spegnere basta un admin e nasconde subito gli annunci. Le categorie
 * ammesse alla pubblicazione sono un elenco SEPARATO da «vendibile»: nessuna è
 * approvata per default e si approva una per una. Nessun interruttore apre un
 * percorso d'acquisto: non esiste.
 */

const PAROLA_DI_RILASCIO = "ATTIVA";

type Interruttore = "preparazione" | "pubblicazione";

const TESTI: Readonly<Record<Interruttore, { titolo: string; descrizione: string; esito: string }>> = {
  preparazione: {
    titolo: "Preparazione degli annunci",
    descrizione: "Bozze degli annunci di accessori posseduti. Richiede anche la funzione Cantina Accessori.",
    esito: "Preparazione degli annunci",
  },
  pubblicazione: {
    titolo: "Pubblicazione degli annunci",
    descrizione:
      "Rende pubblici gli annunci conformi senza approvazione preventiva (moderazione successiva). Spegnere nasconde subito tutti gli annunci. Serve anche almeno una categoria approvata.",
    esito: "Pubblicazione degli annunci",
  },
};

export function AnnunciAccessoriAdmin() {
  const client = useMemo(() => getSupabaseClient(), []);
  const servizio = useMemo(() => creaAnnunciAccessoriAdminService(client), [client]);
  const [stato, setStato] = useState<StatoInterruttoreAnnunci | null>(null);
  const [categorie, setCategorie] = useState<CategoriaPubblicazione[]>([]);
  const [errore, setErrore] = useState<string | null>(null);
  const [esito, setEsito] = useState<string | null>(null);
  const [motivo, setMotivo] = useState("");
  const [conferma, setConferma] = useState("");
  const [invio, setInvio] = useState(false);

  const ricarica = useCallback(async () => {
    const [s, c] = await Promise.all([servizio.stato(), servizio.categoriePubblicazione()]);
    if (s.ok) {
      setStato(s.data);
      setErrore(null);
    } else {
      setErrore(s.error);
    }
    if (c.ok) setCategorie(c.data);
  }, [servizio]);

  useEffect(() => {
    void ricarica();
  }, [ricarica]);

  const motivoOk = motivo.trim().length > 0;

  const imposta = async (quale: Interruttore, nuovo: boolean) => {
    setInvio(true);
    setErrore(null);
    const r =
      quale === "preparazione"
        ? await servizio.imposta(nuovo, motivo.trim())
        : await servizio.impostaPubblicazione(nuovo, motivo.trim());
    setInvio(false);
    if (!r.ok) return setErrore(r.error);
    setMotivo("");
    setConferma("");
    setEsito(`${TESTI[quale].esito}: ${nuovo ? "accesa" : "spenta"}.`);
    await ricarica();
  };

  const impostaCategoria = async (c: CategoriaPubblicazione, pubblicabile: boolean) => {
    setInvio(true);
    setErrore(null);
    const r = await servizio.impostaCategoriaPubblicabile(c.id, pubblicabile, motivo.trim());
    setInvio(false);
    if (!r.ok) return setErrore(r.error);
    setMotivo("");
    setEsito(`${c.nome}: ${pubblicabile ? "approvata alla pubblicazione" : "revocata"}.`);
    await ricarica();
  };

  const interruttore = (quale: Interruttore, acceso: boolean) => (
    <div className="space-y-2 rounded-lg border border-border p-3" data-testid={`annunci-acc-${quale}`}>
      <h3 className="text-sm font-semibold text-antracite">{TESTI[quale].titolo}</h3>
      <p className="text-xs text-antracite/70">{TESTI[quale].descrizione}</p>
      <p className="text-sm">
        Stato: <strong>{acceso ? "ACCESA" : "SPENTA"}</strong>
        {quale === "preparazione" && stato && !stato.cantinaFunzioneAttiva
          ? " (la funzione Cantina Accessori è spenta)"
          : ""}
      </p>
      {acceso ? (
        <Button
          type="button"
          variant="outline"
          disabled={invio || !motivoOk}
          onClick={() => void imposta(quale, false)}
        >
          Spegni
        </Button>
      ) : stato?.puoRilasciare ? (
        <>
          <Label htmlFor={`annunci-acc-conferma-${quale}`}>
            Per accendere scrivi <strong>{PAROLA_DI_RILASCIO}</strong>
          </Label>
          <Input
            id={`annunci-acc-conferma-${quale}`}
            value={conferma}
            autoComplete="off"
            onChange={(e) => setConferma(e.target.value)}
          />
          <Button
            type="button"
            disabled={invio || !motivoOk || conferma !== PAROLA_DI_RILASCIO}
            onClick={() => void imposta(quale, true)}
          >
            Accendi
          </Button>
        </>
      ) : (
        <p className="text-xs text-antracite/80">
          Accendere richiede l&apos;approvazione esplicita del titolare: il tuo account non ha il permesso di
          rilascio.
        </p>
      )}
    </div>
  );

  return (
    <section
      aria-labelledby="annunci-acc-admin"
      data-testid="annunci-accessori-admin"
      className="space-y-4 rounded-xl border border-border bg-card p-4"
    >
      <h2 id="annunci-acc-admin" className="font-serif text-lg font-semibold text-antracite">
        Annunci Accessori
      </h2>
      <p className="text-sm text-antracite/75">
        Gli annunci conformi si pubblicano da soli, senza approvazione preventiva: la moderazione agisce dopo,
        da segnalazioni e controlli. Pubblicato non vuol dire acquistabile: non esiste alcun acquisto, ordine o
        pagamento di accessori. Tutto è spento di default.
      </p>
      {errore ? (
        <p role="alert" className="rounded-lg border border-bordeaux/40 bg-bordeaux/5 px-3 py-2 text-sm text-bordeaux">
          {errore}
        </p>
      ) : null}
      {esito ? (
        <p role="status" className="rounded-lg border border-salvia/40 bg-salvia/10 px-3 py-2 text-sm text-antracite">
          {esito}
        </p>
      ) : null}

      {stato ? (
        <>
          <div className="space-y-1">
            <Label htmlFor="annunci-acc-motivo">
              Motivo (obbligatorio, registrato; per accendere indica il riferimento dell&apos;approvazione del titolare)
            </Label>
            <Input id="annunci-acc-motivo" value={motivo} maxLength={500} onChange={(e) => setMotivo(e.target.value)} />
          </div>
          <div className="grid gap-3 md:grid-cols-2">
            {interruttore("preparazione", stato.preparazioneAttiva)}
            {interruttore("pubblicazione", stato.pubblicazioneAttiva)}
          </div>

          <div className="space-y-2" data-testid="annunci-acc-categorie">
            <h3 className="text-sm font-semibold text-antracite">
              Categorie ammesse alla pubblicazione ({stato.categoriePubblicabili})
            </h3>
            <p className="text-xs text-antracite/70">
              «Vendibile» significa solo che la categoria può avere una bozza: NON è un consenso alla
              pubblicazione. Una categoria si approva una per una (prima la principale), non per default; quelle
              chiuse (Set regalo, Pulizia, Altri accessori) non si possono approvare. Revocare nasconde subito gli
              annunci della categoria.
            </p>
            <ul className="divide-y divide-border rounded-lg border border-border text-sm">
              {categorie.map((c) => (
                <li
                  key={c.id}
                  className={`flex flex-wrap items-center justify-between gap-2 px-3 py-2 ${c.genitoreSlug ? "pl-8" : ""}`}
                >
                  <span>
                    {c.nome}{" "}
                    <span className="text-xs text-antracite/60">
                      {c.vendibile ? "(vendibile alla preparazione)" : "(chiusa)"}
                      {c.approvata ? " · approvata" : ""}
                      {c.approvata && !c.pubblicabile ? " · ma il genitore non lo è" : ""}
                    </span>
                  </span>
                  {c.approvata ? (
                    <Button
                      type="button"
                      size="sm"
                      variant="outline"
                      disabled={invio || !motivoOk}
                      onClick={() => void impostaCategoria(c, false)}
                    >
                      Revoca
                    </Button>
                  ) : c.vendibile && stato.puoRilasciare ? (
                    <Button
                      type="button"
                      size="sm"
                      disabled={invio || !motivoOk}
                      onClick={() => void impostaCategoria(c, true)}
                    >
                      Approva
                    </Button>
                  ) : null}
                </li>
              ))}
            </ul>
          </div>
        </>
      ) : null}
    </section>
  );
}
