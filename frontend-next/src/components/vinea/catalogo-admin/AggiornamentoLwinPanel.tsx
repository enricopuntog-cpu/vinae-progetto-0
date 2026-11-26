"use client";

// WI-015 — ciclo di aggiornamento LWIN dal pannello: che cosa è cambiato rispetto al catalogo canonico e che cosa
// aspetta il curatore. Sola lettura, salvo l'omonimia dichiarata con motivo. Caricamento della nuova versione e
// promozione restano del runner amministrativo con le sue guardie: nessuna credenziale passa dal browser.

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Campo, Esito, Letto, data, useLettura } from "@/components/vinea/catalogo-admin/comune";
import type { ServiziCatalogoAdmin } from "@/lib/catalogo-admin/catalogo-admin";

export function AggiornamentoLwinPanel({ servizi, apri }: { servizi: ServiziCatalogoAdmin; apri: (id: string) => void }) {
  const { esito, ricarica } = useLettura(() => servizi.aggiornamento(), "aggiornamento");
  const [nota, setNota] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const distingui = async (wineId: string, lwin7: string) => {
    setErrore(null);
    const r = await servizi.distingui(wineId, lwin7, nota.trim());
    if (r.ok) {
      setNota("");
      ricarica();
    } else setErrore(r.error);
  };
  return (
    <section className="space-y-2" data-testid="aggiornamento-lwin">
      <h2 className="font-semibold">Aggiornamento LWIN</h2>
      <Letto esito={esito} ricarica={ricarica}>
        {(a) => (
          <div className="space-y-2 text-xs">
            <p>
              {a.ultima_importazione
                ? `Ultima importazione n. ${a.ultima_importazione.seq}: ${a.ultima_importazione.stato}${a.ultima_importazione.conclusa ? ` il ${data(a.ultima_importazione.conclusa)}` : ""} · ${a.ultima_importazione.file} · SHA-256 ${a.ultima_importazione.sha256.slice(0, 12)}…`
                : "Nessuna importazione registrata."}
              {a.regola ? ` · regola di promozione: ${a.regola.stato}` : ""}
            </p>
            <div>
              <h3 className="font-semibold">Schede il cui record non è più attivo nella fonte ({a.canonici_non_piu_live.conteggio})</h3>
              <p className="text-muted-foreground">
                Nulla viene cancellato: il curatore accorpa o ritira con un motivo, oppure lascia la scheda.
              </p>
              <ul className="list-disc pl-5">
                {a.canonici_non_piu_live.esempi.map((c) => (
                  <li key={c.wine_id}>
                    {c.nome} · LWIN {c.lwin7} · {c.stato_fonte}
                    {c.rimosso_dalla_fonte ? " (tolto dal file)" : ""}
                    {c.destinazione_lwin ? ` → ${c.destinazione_lwin}` : ""}{" "}
                    <button type="button" className="underline" onClick={() => apri(c.wine_id)}>
                      apri
                    </button>
                  </li>
                ))}
              </ul>
            </div>
            <div>
              <h3 className="font-semibold">
                Attributi diversi nella nuova versione ({a.attributi_cambiati.conteggio}
                {a.attributi_cambiati.oltre ? " o più" : ""})
              </h3>
              <p className="text-muted-foreground">
                Sono proposte: si accettano con una rivendicazione dalla scheda, senza sovrascrivere i contributi Vinea.
              </p>
              <ul className="list-disc pl-5">
                {a.attributi_cambiati.esempi.map((c) => (
                  <li key={c.wine_id}>
                    {c.nome}:{" "}
                    {Object.entries(c.differenze)
                      .map(([k, v]) => `${k} «${v.catalogo ?? "—"}» → «${v.fonte ?? "—"}»`)
                      .join("; ")}{" "}
                    <button type="button" className="underline" onClick={() => apri(c.wine_id)}>
                      apri
                    </button>
                  </li>
                ))}
              </ul>
            </div>
            <div>
              <h3 className="font-semibold">Conflitti con vini nativi ({a.conflitti_nativi.length})</h3>
              <p className="text-muted-foreground">
                Fermano la promozione. Se è lo stesso vino, associa il codice dalla scheda; se è un omonimo, dichiaralo con il
                motivo. Omonimie già dichiarate: {a.omonimie_dichiarate}.
              </p>
              {a.conflitti_nativi.length > 0 ? (
                <Campo etichetta="Motivo dell'omonimia" valore={nota} onCambio={setNota} massimo={500} />
              ) : null}
              <Esito errore={errore} />
              <ul className="space-y-1">
                {a.conflitti_nativi.map((c) => (
                  <li key={`${c.wine_id}-${c.lwin7}`} className="flex flex-wrap items-center gap-2">
                    <span>
                      {c.produttore} — {c.nome} ↔ LWIN {c.lwin7}
                    </span>
                    <button type="button" className="underline" onClick={() => apri(c.wine_id)}>
                      apri
                    </button>
                    <Button
                      type="button"
                      size="sm"
                      variant="outline"
                      disabled={!nota.trim()}
                      onClick={() => void distingui(c.wine_id, c.lwin7)}
                    >
                      È un vino diverso
                    </Button>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        )}
      </Letto>
    </section>
  );
}
