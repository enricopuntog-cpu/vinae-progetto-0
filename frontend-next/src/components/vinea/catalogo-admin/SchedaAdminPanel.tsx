"use client";

// WI-012 — scheda di un vino canonico: identità, annate, formati, attributi (attuali e proposti), collegamenti,
// storico e le azioni ammesse. Fusioni e ritiri definitivi non sono comandi di questa pagina.

import { useState } from "react";
import { Button } from "@/components/ui/button";
import type { ServiziCatalogoAdmin, SchedaAdmin } from "@/lib/catalogo-admin/catalogo-admin";
import { Campo, Esito, Letto, Scelta, data, testoValore, useLettura } from "./comune";

const ATTRIBUTI: [string, string, "wine" | "vintage"][] = [
  ["grapes", "Vitigni (separati da virgola)", "wine"],
  ["food_pairings", "Abbinamenti (separati da virgola)", "wine"],
  ["service_temperature_c", "Temperatura di servizio (°C)", "wine"],
  ["alcohol_pct", "Gradazione (%)", "vintage"],
  ["tasting_notes", "Note degustative", "vintage"],
];

/** Il testo del modulo diventa il valore del tipo previsto dall'attributo; `null` se non è interpretabile. */
export function valoreAttributo(chiave: string, testo: string): unknown {
  const t = testo.trim();
  if (!t) return null;
  if (chiave === "grapes" || chiave === "food_pairings") {
    const voci = t.split(",").map((v) => v.trim()).filter(Boolean);
    return voci.length ? voci : null;
  }
  if (chiave === "service_temperature_c" || chiave === "alcohol_pct") {
    const n = Number(t.replace(",", "."));
    return Number.isFinite(n) ? n : null;
  }
  return t;
}

export function SchedaAdminPanel({ servizi, id, chiudi }: { servizi: ServiziCatalogoAdmin; id: string; chiudi: () => void }) {
  const { esito, ricarica } = useLettura(() => servizi.vino(id), id);
  return (
    <section className="space-y-3 rounded-2xl border border-border bg-card p-4" data-testid="catalogo-admin-scheda">
      <Button type="button" size="sm" variant="outline" onClick={chiudi}>
        Chiudi la scheda
      </Button>
      <Letto esito={esito} ricarica={ricarica}>
        {(scheda) => (scheda ? <Scheda servizi={servizi} scheda={scheda} ricarica={ricarica} /> : <p>Vino non trovato.</p>)}
      </Letto>
    </section>
  );
}

function Scheda({ servizi, scheda, ricarica }: { servizi: ServiziCatalogoAdmin; scheda: SchedaAdmin; ricarica: () => void }) {
  const [errore, setErrore] = useState<string | null>(null);
  const [fatto, setFatto] = useState<string | null>(null);
  const [inCorso, setInCorso] = useState(false);
  const [nota, setNota] = useState("");
  const [anno, setAnno] = useState("");
  const [annataFormato, setAnnataFormato] = useState("");
  const [ml, setMl] = useState("");
  const [lwin, setLwin] = useState("");
  const [attributo, setAttributo] = useState("grapes");
  const [annataAttributo, setAnnataAttributo] = useState("");
  const [valore, setValore] = useState("");

  const esegui = async (azione: string, dati: Record<string, unknown>, messaggio: string) => {
    setInCorso(true);
    setErrore(null);
    setFatto(null);
    const r = await servizi.azione(azione, dati, nota);
    setInCorso(false);
    if (!r.ok) {
      setErrore(r.error);
      return;
    }
    setFatto(messaggio);
    setNota("");
    ricarica();
  };

  const definizione = ATTRIBUTI.find((a) => a[0] === attributo) ?? ATTRIBUTI[0]!;
  const opzioniAnnate: [string, string][] = [
    ["", "Scegli l'annata"],
    ...scheda.annate.map((a): [string, string] => [a.id, a.non_millesimato ? "Non millesimato" : String(a.anno)]),
  ];

  return (
    <div className="space-y-3 text-sm">
      <header>
        <h2 className="font-serif text-xl">
          {scheda.produttore.nome} — {scheda.nome}
        </h2>
        <p className="text-xs text-muted-foreground">
          {scheda.lwin7 ? `LWIN ${scheda.lwin7}` : "Senza codice LWIN"} ·{" "}
          {scheda.origine === "manual" ? "identità nativa Vinea" : "promosso dalla fonte"} · stato {scheda.stato}
          {scheda.origine === "manual" ? ` · ${scheda.pubblicato_il ? `pubblicato il ${data(scheda.pubblicato_il)}` : "non pubblicato"}` : ""}
        </p>
        <p className="text-xs text-muted-foreground">ID stabile: {scheda.id}</p>
        <p className="text-xs text-muted-foreground">
          Fonte: {scheda.fonte ? `${scheda.fonte.nome} (${scheda.fonte.autorizzazione})` : "inserimento curato"}
          {scheda.nota_provenienza ? ` — ${scheda.nota_provenienza}` : ""}
        </p>
        <p className="text-xs">
          {[scheda.denominazione, scheda.tipo, scheda.colore, scheda.territorio?.nome].filter(Boolean).join(" · ") || "Nessun dettaglio registrato"}
        </p>
      </header>

      <div>
        <h3 className="font-semibold">Annate e formati</h3>
        {scheda.annate.length === 0 ? <p className="text-xs text-muted-foreground">Nessuna annata registrata.</p> : null}
        <ul className="list-disc pl-5 text-xs">
          {scheda.annate.map((a) => (
            <li key={a.id}>
              {a.non_millesimato ? "Non millesimato" : a.anno}
              {a.formati.length ? ` — ${a.formati.map((f) => `${f.ml} ml${f.pezzi > 1 ? ` × ${f.pezzi}` : ""}`).join(", ")}` : ""}
            </li>
          ))}
        </ul>
      </div>

      <div>
        <h3 className="font-semibold">Attributi e prove</h3>
        {scheda.attributi.length === 0 ? <p className="text-xs text-muted-foreground">Nessun attributo documentato.</p> : null}
        <ul className="list-disc pl-5 text-xs">
          {scheda.attributi.map((a) => (
            <li key={a.id}>
              {a.attributo}: {testoValore(a.valore)} — <strong>{a.stato}</strong> · {a.fonte}
              {a.evidenza ? ` (${a.evidenza})` : ""}
            </li>
          ))}
        </ul>
      </div>

      {scheda.collegamenti.length ? (
        <p className="text-xs">
          Collegamenti applicativi: {scheda.collegamenti.map((l) => `${l.vino_app} (${l.stato})`).join(", ")}
        </p>
      ) : null}

      {scheda.stato === "active" ? (
        <fieldset className="space-y-2 rounded-xl border border-border p-3" disabled={inCorso}>
          <legend className="px-1 text-xs font-semibold">Modifiche (ognuna resta nello storico)</legend>
          <Campo etichetta="Nota di provenienza o motivo (obbligatoria)" valore={nota} onCambio={setNota} massimo={500} />

          {scheda.origine === "manual" ? (
            <div className="flex flex-wrap items-end gap-2">
              <Button
                type="button"
                size="sm"
                onClick={() =>
                  void esegui(scheda.pubblicato_il ? "ritira_pubblicazione" : "pubblica", { wine_id: scheda.id },
                    scheda.pubblicato_il ? "Pubblicazione ritirata." : "Scheda pubblicata (visibile solo con la proiezione accesa).")
                }
              >
                {scheda.pubblicato_il ? "Ritira la pubblicazione" : "Pubblica la scheda"}
              </Button>
              {!scheda.lwin7 ? (
                <>
                  <Campo etichetta="LWIN ufficiale" valore={lwin} onCambio={setLwin} massimo={7} numerico />
                  <Button type="button" size="sm" variant="outline" onClick={() => void esegui("assegna_lwin", { wine_id: scheda.id, lwin7: lwin.trim() }, "LWIN associato alla stessa identità.")}>
                    Associa il LWIN
                  </Button>
                </>
              ) : null}
            </div>
          ) : null}

          <div className="flex flex-wrap items-end gap-2">
            <Campo etichetta="Nuova annata (vuota = non millesimato)" valore={anno} onCambio={setAnno} massimo={4} numerico />
            <Button
              type="button"
              size="sm"
              variant="outline"
              onClick={() =>
                void esegui("annata", anno.trim() ? { wine_id: scheda.id, anno: Number(anno) } : { wine_id: scheda.id, non_millesimato: true }, "Annata registrata.")
              }
            >
              Aggiungi annata
            </Button>
          </div>

          {scheda.annate.length ? (
            <div className="flex flex-wrap items-end gap-2">
              <Scelta etichetta="Annata del formato" valore={annataFormato} onCambio={setAnnataFormato} opzioni={opzioniAnnate} />
              <Campo etichetta="Volume in ml" valore={ml} onCambio={setMl} massimo={5} numerico />
              <Button type="button" size="sm" variant="outline" disabled={!annataFormato} onClick={() => void esegui("formato", { vintage_id: annataFormato, ml: Number(ml) }, "Formato registrato.")}>
                Aggiungi formato
              </Button>
            </div>
          ) : null}

          <div className="flex flex-wrap items-end gap-2">
            <Scelta etichetta="Attributo" valore={attributo} onCambio={setAttributo} opzioni={ATTRIBUTI.map((a): [string, string] => [a[0], a[1]])} />
            {definizione[2] === "vintage" ? (
              <Scelta etichetta="Annata dell'attributo" valore={annataAttributo} onCambio={setAnnataAttributo} opzioni={opzioniAnnate} />
            ) : null}
            <Campo etichetta="Valore" valore={valore} onCambio={setValore} massimo={500} />
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={valoreAttributo(attributo, valore) === null || (definizione[2] === "vintage" && !annataAttributo)}
              onClick={() =>
                void esegui(
                  "attributo_proponi",
                  {
                    attributo,
                    soggetto: definizione[2],
                    soggetto_id: definizione[2] === "wine" ? scheda.id : annataAttributo,
                    valore: valoreAttributo(attributo, valore),
                  },
                  "Attributo proposto: si accetta dalla coda «Da decidere».",
                )
              }
            >
              Proponi attributo
            </Button>
          </div>
        </fieldset>
      ) : null}
      <Esito errore={errore} messaggio={fatto} />

      <details className="text-xs">
        <summary className="cursor-pointer font-semibold">Storico ({scheda.storico.length})</summary>
        <ul className="mt-1 space-y-0.5">
          {scheda.storico.map((e) => (
            <li key={e.id}>
              {data(e.quando)} · {e.azione} · {e.esecutore}
            </li>
          ))}
        </ul>
      </details>
    </div>
  );
}
