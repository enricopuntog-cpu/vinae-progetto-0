"use client";

// WI-006A — l'elenco dei vini trovati, con la scelta e il «nessuno di questi».
// Condiviso dal pannello fotografico (WI-002) e dalla ricerca manuale: una sola
// interfaccia, due punti d'ingresso. Non conferma nulla: chi lo usa decide
// quando i dati scelti entrano nel wizard.

import type {
  CandidatoValutato,
  EsitoCorrispondenza,
  SintesiRicerca,
} from "@/lib/vendi/foto-etichetta/candidati";

export const ETICHETTA_ESITO: Record<EsitoCorrispondenza, string> = {
  esatta: "Stesso vino e stessa annata",
  probabile: "Vino molto simile",
  annata_diversa: "Stesso vino, annata diversa",
  formato_diverso: "Stesso vino, formato diverso",
  possibile: "Possibile corrispondenza",
};

/** « · Regione, Denominazione» (per una scheda canonica anche territorio o paese); vuoto se non c'è nulla. */
const testoLuogo = (c: CandidatoValutato): string => {
  const luogo = [c.regione ?? c.canonico?.territorio ?? c.canonico?.paese, c.denominazione].filter(Boolean);
  return luogo.length > 0 ? ` · ${luogo.join(", ")}` : "";
};

type Props = {
  candidati: readonly CandidatoValutato[];
  sintesi: SintesiRicerca | null;
  selezionato: string | null;
  onSeleziona: (id: string | null) => void;
  /** Nome comune dei radio (deve essere unico nella pagina). */
  nomeGruppo: string;
  /** Prefisso degli `data-testid`: `<prefisso>-candidati`, `-candidato-<id>`, `-nessuno`. */
  prefissoTest: string;
  testoNessuno?: string;
};

export function ElencoCandidati({
  candidati,
  sintesi,
  selezionato,
  onSeleziona,
  nomeGruppo,
  prefissoTest,
  testoNessuno = "Nessuno di questi: continuo con i dati letti",
}: Props) {
  // Licenza della fonte (es. CC BY 4.0): l'attribuzione resta visibile finché c'è un vino che ne proviene.
  const attribuzioni = [
    ...new Set(
      candidati.flatMap((c) =>
        c.canonico ? [c.canonico.attribuzione ?? [c.canonico.fonteNome, c.canonico.licenza].filter(Boolean).join(" — ")] : [],
      ),
    ),
  ].filter((t) => t.length > 0);
  return (
    <fieldset className="mt-2 space-y-2" data-testid={`${prefissoTest}-candidati`}>
      <legend className="text-[11px] text-muted-foreground">
        {sintesi === "unica"
          ? "Un vino corrisponde. Sceglilo solo se è davvero il tuo."
          : "Più vini possibili: scegli quello giusto oppure nessuno."}
      </legend>
      {candidati.map((c) => (
        <label
          key={c.id + (c.formato ?? "") + (c.annata ?? "")}
          className="flex cursor-pointer items-start gap-2 rounded-xl border border-border p-2 text-xs has-[:checked]:border-bordeaux"
          data-testid={`${prefissoTest}-candidato-${c.id}`}
        >
          <input
            type="radio"
            name={nomeGruppo}
            className="mt-0.5"
            checked={selezionato === c.id}
            onChange={() => onSeleziona(c.id)}
          />
          <span>
            <b>{c.produttore}</b> — {c.nome}
            {c.annata ? ` ${c.annata}` : ""}
            {c.formato ? ` · ${c.formato}` : ""}
            {c.canonico ? <span className="text-muted-foreground"> · LWIN {c.canonico.lwin7}</span> : null}
            <br />
            <span className="text-muted-foreground">
              {ETICHETTA_ESITO[c.esito]}
              {testoLuogo(c)}
            </span>
            {c.omonimi ? (
              <span className="block text-muted-foreground" data-testid={`${prefissoTest}-omonimo-${c.id}`}>
                Altre schede hanno lo stesso nome: controlla codice LWIN, territorio e denominazione prima di sceglierla.
              </span>
            ) : null}
          </span>
        </label>
      ))}
      {attribuzioni.length > 0 && (
        <p className="text-[11px] text-muted-foreground" data-testid={`${prefissoTest}-attribuzione`}>
          {attribuzioni.join(" · ")}
        </p>
      )}
      <label className="flex cursor-pointer items-start gap-2 rounded-xl border border-border p-2 text-xs has-[:checked]:border-bordeaux">
        <input
          type="radio"
          name={nomeGruppo}
          className="mt-0.5"
          checked={selezionato === null}
          onChange={() => onSeleziona(null)}
          data-testid={`${prefissoTest}-nessuno`}
        />
        <span>{testoNessuno}</span>
      </label>
    </fieldset>
  );
}
