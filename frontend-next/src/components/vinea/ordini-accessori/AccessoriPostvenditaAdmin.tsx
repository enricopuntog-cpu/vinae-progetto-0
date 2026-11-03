"use client";

import { useRef, useState } from "react";
import { DisputePanel } from "@/components/vinea/orders/DisputePanel";
import { creaCaricatoreFascicolo, contestazioneComeFascicolo, type FascicoloAccessorio } from "@/lib/accessori-postvendita/fascicolo";
import { Button } from "@/components/ui/button";
import type {
  ElencoPostVenditaAdmin,
  IntentoOrfanoAdmin,
  RimborsoDovutoAdmin,
} from "@/lib/accessori-postvendita/postvendita";
import { euro } from "@/lib/prezzi/classe";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAccessoriPostvenditaService } from "@/services/accessori-postvendita-service";

const ora = (iso: string) =>
  new Intl.DateTimeFormat("it-IT", { dateStyle: "short", timeStyle: "short", timeZone: "Europe/Rome" }).format(
    new Date(iso),
  );

const ORIGINE = { dovuto_automatico: "Incasso non applicabile", contestazione: "Decisione su contestazione" } as const;

/**
 * Coda di lavoro del post-vendita Accessori per l'admin: contestazioni da
 * decidere, rimborsi non conclusi (compreso ogni `refund_due`), consegna
 * manuale e reso rientrato. Ogni porta ricontrolla il ruolo nel database.
 */
export type PagamentiDaVerificare = {
  orfani: { ok: true; data: IntentoOrfanoAdmin[] } | { ok: false; error: string };
  dovuti: { ok: true; data: RimborsoDovutoAdmin[] } | { ok: false; error: string };
};

export function AccessoriPostvenditaAdmin({
  iniziale,
  pagamenti: pagamentiIniziali,
}: {
  iniziale: ElencoPostVenditaAdmin;
  pagamenti: PagamentiDaVerificare;
}) {
  const [elenco, setElenco] = useState(iniziale);
  const [pagamenti, setPagamenti] = useState(pagamentiIniziali);
  const [messaggio, setMessaggio] = useState<string | null>(null);
  const [ordine, setOrdine] = useState("");
  const [quantita, setQuantita] = useState("1");
  const [nota, setNota] = useState("");
  const [importo, setImporto] = useState("");
  const [fascicolo, setFascicolo] = useState<FascicoloAccessorio | null>(null);
  const [caricamento, setCaricamento] = useState(false);
  const [erroreFascicolo, setErroreFascicolo] = useState<string | null>(null);
  const [inCorso, setInCorso] = useState(false);
  const caricatore = useRef(creaCaricatoreFascicolo());
  const servizio = () => creaAccessoriPostvenditaService(getSupabaseClient());
  const cambiaOrdine = (id: string) => {
    caricatore.current.invalida();
    setOrdine(id);
    setFascicolo(null);
    setCaricamento(false);
    setErroreFascicolo(null);
    setMessaggio(null);
    setNota("");
    setImporto("");
  };
  const carica = async (id: string) => {
    cambiaOrdine(id);
    setCaricamento(true);
    await caricatore.current.carica(servizio(), id, (esito) => {
      setCaricamento(false);
      if (esito.ok) setFascicolo(esito.data);
      else setErroreFascicolo(esito.error);
    });
  };
  const c = fascicolo?.postvendita.contestazione;
  const puoDecidere = !caricamento && !inCorso && fascicolo?.postvendita.ordineId === ordine
    && !!c && !c.chiusaAt && (c.stato === "aperta" || c.stato === "in_valutazione")
    && (!!c.risposta || Date.now() > Date.parse(c.venditoreScadenzaAt));
  const disputa = fascicolo ? contestazioneComeFascicolo(fascicolo.postvendita, fascicolo.foto) : null;

  const ricarica = async () => {
    const [esito, orfani, dovuti] = await Promise.all([
      servizio().adminElenco(),
      servizio().adminIntentiOrfani(),
      servizio().adminRimborsiDovuti(),
    ]);
    if (esito.ok) setElenco(esito.data);
    // Una lettura fallita resta un errore visibile: mai un elenco vecchio spacciato per aggiornato.
    setPagamenti({ orfani, dovuti });
  };
  const esegui = async (azione: () => Promise<{ ok: boolean; error?: string }>) => {
    if (inCorso) return;
    setInCorso(true);
    setMessaggio(null);
    try {
      const esito = await azione();
      setMessaggio(esito.ok ? "Operazione registrata." : (esito.error ?? "Operazione non riuscita."));
      if (esito.ok) {
        caricatore.current.invalida();
        setFascicolo(null);
        await ricarica();
      }
    } catch {
      setMessaggio("Operazione non riuscita. Riprova.");
    } finally {
      setInCorso(false);
    }
  };
  const centesimi = () => Math.round(Number(importo.replace(",", ".")) * 100);

  return (
    <div className="space-y-8 text-sm" data-testid="postvendita-admin">
      <section>
        <h2 className="font-display text-lg">Contestazioni aperte</h2>
        {elenco.contestazioni.length === 0 ? <p className="mt-2 text-muted-foreground">Nessuna.</p> : null}
        <ul className="mt-2 space-y-2">
          {elenco.contestazioni.map((c) => (
            <li key={c.ordineId} className="rounded-xl border p-3">
              <p className="font-medium">{c.motivo} · ordine {c.ordineId}</p>
              <p className="text-xs text-muted-foreground">
                Aperta {ora(c.apertaAt)} · risposta del venditore entro {ora(c.venditoreScadenzaAt)}
                {c.rispostaAt ? ` · risposto ${ora(c.rispostaAt)}` : ""}
                {c.pronta ? " · pronta per la decisione" : " · in attesa del venditore"}
              </p>
              <Button size="sm" variant="outline" className="mt-2" disabled={inCorso} onClick={() => void carica(c.ordineId)}>
                Seleziona
              </Button>
            </li>
          ))}
        </ul>
      </section>

      <section>
        <h2 className="font-display text-lg">Rimborsi non conclusi</h2>
        {elenco.rimborsi.length === 0 ? <p className="mt-2 text-muted-foreground">Nessuno.</p> : null}
        <ul className="mt-2 space-y-2">
          {elenco.rimborsi.map((r) => (
            <li key={r.rimborsoId} className="rounded-xl border p-3">
              <p className="font-medium">
                {ORIGINE[r.origine]} · {euro(r.importoCents)} · {r.stato.replaceAll("_", " ")}
              </p>
              <p className="text-xs text-muted-foreground">
                Ordine {r.ordineId} · richiesto {ora(r.richiestoAt)} · tentativi {r.tentativi}
                {r.ultimoErrore ? ` · ultimo errore: ${r.ultimoErrore}` : ""}
              </p>
            </li>
          ))}
        </ul>
      </section>

      <section data-testid="rimborsi-dovuti-admin">
        <h2 className="font-display text-lg">Rimborsi dovuti (incasso non applicabile)</h2>
        <p className="mt-1 text-xs text-muted-foreground">
          Pagamenti incassati dal fornitore che l&apos;ordine non ha potuto usare. Si chiudono solo con l&apos;evento firmato
          del fornitore: non esiste un&apos;azione manuale da qui.
        </p>
        {!pagamenti.dovuti.ok ? (
          <p role="alert" className="mt-2">Elenco non disponibile: {pagamenti.dovuti.error} Non significa che non ci siano rimborsi dovuti.</p>
        ) : pagamenti.dovuti.data.length === 0 ? (
          <p className="mt-2 text-muted-foreground">Nessuno.</p>
        ) : (
          <ul className="mt-2 space-y-2">
            {pagamenti.dovuti.data.map((d) => (
              <li key={d.ordineId} className="rounded-xl border p-3">
                <p className="font-medium">
                  {euro(d.importoCents)} {d.valuta.toUpperCase()} · già rimborsato {euro(d.rimborsatoCents)}
                </p>
                <p className="text-xs text-muted-foreground">
                  Ordine {d.ordineId} · aggiornato {ora(d.aggiornatoAt)}
                  {d.motivo ? ` · motivo: ${d.motivo}` : ""}
                </p>
                <Button size="sm" variant="outline" className="mt-2" disabled={inCorso} onClick={() => void carica(d.ordineId)}>
                  Apri nel fascicolo
                </Button>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section data-testid="intenti-orfani-admin">
        <h2 className="font-display text-lg">Intenti di pagamento orfani</h2>
        <p className="mt-1 text-xs text-muted-foreground">
          Controllo manuale: cerca l&apos;identificativo del PaymentIntent nel pannello del fornitore. «Da annullare»: l&apos;annullo
          è ancora da confermare. «Incerto»: lo stato presso il fornitore non è noto. Se risulta incassato deve comparire fra i
          rimborsi dovuti. Questa pagina non annulla né rimborsa e non riconcilia in automatico.
        </p>
        {!pagamenti.orfani.ok ? (
          <p role="alert" className="mt-2">Elenco non disponibile: {pagamenti.orfani.error} Non significa che non ci siano intenti orfani.</p>
        ) : pagamenti.orfani.data.length === 0 ? (
          <p className="mt-2 text-muted-foreground">Nessuno.</p>
        ) : (
          <ul className="mt-2 space-y-2">
            {pagamenti.orfani.data.map((o) => (
              <li key={`${o.ordineId}-${o.intento}`} className="rounded-xl border p-3">
                <p className="font-medium">
                  {o.statoIntento === "incerto" ? "Incerto" : "Da annullare"} · {euro(o.importoCents)} {o.valuta.toUpperCase()}
                </p>
                <p className="break-all text-xs text-muted-foreground">
                  Ordine {o.ordineId} · {o.provider} {o.intento} · pagamento {o.statoPagamento.replaceAll("_", " ")} · dal {ora(o.aggiornatoAt)}
                  {o.motivo ? ` · motivo: ${o.motivo}` : ""}
                </p>
                <Button size="sm" variant="outline" className="mt-2" disabled={inCorso} onClick={() => void carica(o.ordineId)}>
                  Apri nel fascicolo
                </Button>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="space-y-3 rounded-2xl border p-4">
        <h2 className="font-display text-lg">Operazioni sull&apos;ordine</h2>
        <label className="block">
          <span className="mb-1 block text-xs font-medium">Identificativo dell&apos;ordine</span>
          <input
            value={ordine}
            disabled={inCorso}
            onChange={(e) => cambiaOrdine(e.target.value.trim())}
            className="w-full rounded-md border border-input bg-background px-3 py-2"
          />
        </label>
        <Button size="sm" variant="outline" disabled={!ordine || inCorso || caricamento} onClick={() => void carica(ordine)}>
          {caricamento ? "Caricamento fascicolo…" : "Carica / riprova fascicolo"}
        </Button>
        {erroreFascicolo ? <p role="alert">{erroreFascicolo}</p> : null}
        {fascicolo ? (
          <div className="space-y-3" data-testid="fascicolo-accessorio-admin">
            <p>Ordine {fascicolo.postvendita.ordineId} · {fascicolo.postvendita.incassato ? "Incassato" : "Non incassato"}</p>
            <p>Rimborsato: {euro(fascicolo.postvendita.rimborso?.rimborsatoCents ?? 0)} · in elaborazione: {euro(fascicolo.postvendita.rimborso?.inCorsoCents ?? 0)}</p>
            <p className="text-xs text-muted-foreground">La lettura del fascicolo non espone il ricavo del venditore. Gli importi delle liste «Rimborsi dovuti» e «Intenti di pagamento orfani» sono quelli del pagamento dell'acquirente, solo per l'admin.</p>
            {c?.importoRimborsoCents != null ? <p>Rimborso deciso: {euro(c.importoRimborsoCents)}</p> : null}
            {disputa ? <DisputePanel contestazione={disputa} eventi={[]} ruolo="compratore" inCorso={inCorso} onRispondi={async () => "Operazione non disponibile."} /> : <p>Nessuna contestazione.</p>}
          </div>
        ) : null}
        <label className="block">
          <span className="mb-1 block text-xs font-medium">Nota o riferimento</span>
          <input
            value={nota}
            onChange={(e) => setNota(e.target.value)}
            maxLength={1000}
            className="w-full rounded-md border border-input bg-background px-3 py-2"
          />
        </label>
        <label className="block">
          <span className="mb-1 block text-xs font-medium">Importo da rimborsare (euro, solo per «rimborsata»)</span>
          <input
            value={importo}
            onChange={(e) => setImporto(e.target.value)}
            inputMode="decimal"
            className="w-full rounded-md border border-input bg-background px-3 py-2"
          />
        </label>
        <div className="flex flex-wrap gap-2">
          {(["rimborsata", "risolta", "respinta"] as const).map((esito) => (
            <Button
              key={esito}
              disabled={!puoDecidere}
              size="sm"
              variant="outline"
              onClick={() =>
                puoDecidere && esegui(() =>
                  servizio().adminDecidi({
                    ordineId: ordine,
                    esito,
                    importoCents: esito === "rimborsata" ? centesimi() : null,
                    nota,
                  }),
                )
              }
            >
              Decidi: {esito}
            </Button>
          ))}
          <Button
            size="sm"
            variant="outline"
            onClick={() => esegui(() => servizio().adminConsegna({ ordineId: ordine, riferimento: nota }))}
          >
            Registra consegna (manuale)
          </Button>
        </div>
        <div className="flex items-end gap-2">
          <label className="block">
            <span className="mb-1 block text-xs font-medium">Pezzi rientrati e riutilizzabili</span>
            <input
              value={quantita}
              onChange={(e) => setQuantita(e.target.value)}
              inputMode="numeric"
              className="w-24 rounded-md border border-input bg-background px-3 py-2"
            />
          </label>
          <Button
            size="sm"
            variant="outline"
            onClick={() => esegui(() => servizio().adminReso({ ordineId: ordine, quantita: Number(quantita), nota }))}
          >
            Registra reso rientrato
          </Button>
        </div>
        {messaggio ? <p role="status" className="text-xs">{messaggio}</p> : null}
      </section>
    </div>
  );
}
