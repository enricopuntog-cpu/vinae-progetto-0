"use client";

// WI-016 — quarantena delle proposte sospette (rilascio o messa in quarantena con motivo) e ingresso del Wine Research:
// informazioni da una fonte AUTORIZZATA, con riferimento, data e attendibilità, che entrano come rivendicazioni
// PROPOSTE e si decidono dalla scheda del vino. Nessuna ricerca automatica o scraping.

import { useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { Button } from "@/components/ui/button";
import { leggiRicercaIncollata } from "@/lib/azienda-admin/controllo";
import { chiamaCatalogoAdmin } from "@/lib/catalogo-admin/catalogo-admin";
import { Campo, Esito, Letto, data, testoValore, useLettura } from "./comune";

type InQuarantena = { id: number; dati: Record<string, unknown>; motivo: string; dal: string; origine: string; invii: number };

const MOTIVI: Record<string, string> = {
  possibile_recapito: "Sembra contenere un recapito",
  contenuto_promozionale: "Contenuto promozionale",
  istruzioni_sospette: "Contiene istruzioni sospette",
  caratteri_ripetuti: "Caratteri ripetuti",
  testo_non_plausibile: "Testo non plausibile per un vino",
  ritmo_anomalo: "Molte proposte dallo stesso account in un'ora",
  proposte_respinte: "Account con molte proposte respinte",
  decisione_curatore: "Messa in quarantena dal curatore",
};

export function QuarantenaPanel({ client }: { client: SupabaseClient }) {
  const [nota, setNota] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const { esito, ricarica } = useLettura(() => chiamaCatalogoAdmin<InQuarantena[]>(client, "catalogo_admin_quarantena"), "quarantena");
  const rilascia = async (id: number) => {
    setErrore(null);
    const r = await chiamaCatalogoAdmin(client, "catalogo_admin_quarantena_decidi", { p_id: id, p_azione: "rilascia", p_nota: nota });
    if (!r.ok) setErrore(r.error);
    else {
      setNota("");
      ricarica();
    }
  };
  return (
    <section className="space-y-2 text-sm" data-testid="quarantena">
      <p className="text-xs text-muted-foreground">
        Una proposta in quarantena non entra nella coda automatica e non può diventare un vino finché non la rilasci. Per
        scartarla usa «Rifiuta» nella scheda delle proposte.
      </p>
      <Campo etichetta="Motivo del rilascio" valore={nota} onCambio={setNota} massimo={500} />
      <Esito errore={errore} />
      <Letto esito={esito} ricarica={ricarica}>
        {(righe) => (
          <ul className="space-y-2">
            {righe.length === 0 ? <li className="text-xs text-muted-foreground">Nessuna proposta in quarantena.</li> : null}
            {righe.map((q) => (
              <li key={q.id} className="rounded-xl border border-border bg-card p-3 text-xs">
                <p className="font-semibold">
                  Proposta {q.id} · {MOTIVI[q.motivo] ?? q.motivo}
                </p>
                <p className="break-words">{testoValore(q.dati)}</p>
                <p className="text-muted-foreground">
                  {q.origine} · {q.invii} invii · dal {data(q.dal)}
                </p>
                <Button type="button" size="sm" variant="outline" disabled={!nota.trim()} onClick={() => void rilascia(q.id)}>
                  Rilascia
                </Button>
              </li>
            ))}
          </ul>
        )}
      </Letto>
    </section>
  );
}

const ESEMPIO = `{"fonte":"CODICE-FONTE","soggetto":"wine","soggetto_id":"uuid del vino","attributo":"grapes","valore":["Nebbiolo"],"riferimento":"https://…","acquisita":"2026-11-27","attendibilita":4}`;

export function RicercaPanel({ client }: { client: SupabaseClient }) {
  const [testo, setTesto] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const [messaggio, setMessaggio] = useState<string | null>(null);
  const letto = useMemo(() => (testo.trim() ? leggiRicercaIncollata(testo) : null), [testo]);
  const registra = async () => {
    if (!letto?.ok) return;
    setErrore(null);
    setMessaggio(null);
    let registrate = 0;
    for (const elemento of letto.data) {
      const r = await chiamaCatalogoAdmin(client, "catalogo_admin_ricerca_registra", { p_dati: elemento });
      if (!r.ok) {
        setErrore(`${r.error} Registrate ${registrate} su ${letto.data.length}; le altre non sono state inviate.`);
        return;
      }
      registrate += 1;
    }
    setTesto("");
    setMessaggio(`Registrate ${registrate} proposte: si decidono dalla scheda del vino.`);
  };
  return (
    <section className="space-y-2 text-sm" data-testid="ricerca">
      <p className="text-xs text-muted-foreground">
        Solo fonti con autorizzazione verificata e diritti dichiarati. Ogni informazione entra come proposta con la sua
        provenienza: non modifica il catalogo.
      </p>
      <label className="block text-xs">
        Informazioni (un oggetto JSON o un elenco, al massimo 20). Esempio: <code className="break-all">{ESEMPIO}</code>
        <textarea
          className="mt-1 h-32 w-full rounded-md border border-input bg-background p-2 font-mono text-xs"
          value={testo}
          maxLength={20000}
          onChange={(e) => setTesto(e.target.value)}
        />
      </label>
      {letto && !letto.ok ? <p className="text-xs text-destructive">{letto.error}</p> : null}
      <Button type="button" size="sm" disabled={!letto?.ok} onClick={() => void registra()}>
        Registra come proposte
      </Button>
      <Esito errore={errore} messaggio={messaggio} />
    </section>
  );
}
