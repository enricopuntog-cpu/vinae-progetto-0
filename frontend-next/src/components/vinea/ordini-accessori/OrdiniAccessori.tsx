"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import {
  testoStatoOrdine,
  MESSAGGI_CHIUSURA,
  TESTI_ORDINI_ACCESSORI,
  type OrdineAccessorio,
} from "@/lib/accessori-ordini/ordine";
import { euro } from "@/lib/prezzi/classe";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAccessoriOrdiniService } from "@/services/accessori-ordini-service";
import { PagamentoAccessorio } from "./PagamentoAccessorio";

const ora = (iso: string) =>
  new Intl.DateTimeFormat("it-IT", { dateStyle: "short", timeStyle: "short", timeZone: "Europe/Rome" }).format(
    new Date(iso),
  );

/** Vista pura: ciò che l'utente legge di un ordine, senza I/O. */
export function RiepilogoOrdineAccessorio({ ordine }: { ordine: OrdineAccessorio }) {
  const venditore = ordine.ruolo === "venditore";
  const logistica = ordine.logistica;
  return (
    <div data-testid="ordine-accessorio" className="space-y-2 text-sm">
      <p className="font-medium" data-testid="ordine-stato">
        {testoStatoOrdine(ordine)}
      </p>
      <dl className="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1">
        <dt>
          {ordine.articolo.nome}
          {ordine.articolo.marchio ? ` · ${ordine.articolo.marchio}` : ""} — {ordine.quantita}{" "}
          {ordine.quantita === 1 ? "pezzo" : "pezzi"} × {euro(ordine.prezzo.unitarioCents)}
        </dt>
        <dd>{euro(ordine.prezzo.subtotaleCents)}</dd>
        {venditore ? (
          <>
            <dt className="font-medium">Incassi</dt>
            <dd className="font-medium" data-testid="ordine-ricevi">
              {euro(ordine.ricevoCents ?? 0)}
            </dd>
          </>
        ) : logistica &&
          ordine.commissioneCents !== null &&
          ordine.coperturaPagamentoCents !== null &&
          ordine.totaleAcquirenteCents !== null ? (
          <>
            <dt>Commissione Vinea</dt>
            <dd>{euro(ordine.commissioneCents)}</dd>
            <dt>
              Spedizione al punto di ritiro ({logistica.colli} {logistica.colli === 1 ? "collo" : "colli"})
            </dt>
            <dd>{euro(logistica.trasportoCents)}</dd>
            {logistica.assicurazioneCents > 0 ? (
              <>
                <dt>Assicurazione</dt>
                <dd>{euro(logistica.assicurazioneCents)}</dd>
              </>
            ) : null}
            <dt>Costo di pagamento sulla spedizione</dt>
            <dd>{euro(ordine.coperturaPagamentoCents)}</dd>
            <dt className="font-medium">Totale</dt>
            <dd className="font-medium" data-testid="ordine-totale">
              {euro(ordine.totaleAcquirenteCents)}
            </dd>
          </>
        ) : null}
      </dl>
      {ordine.controparte ? (
        <p className="text-muted-foreground">
          {venditore ? "Acquirente" : "Venditore"}: {ordine.controparte}
        </p>
      ) : null}
      {ordine.stato === "in_attesa_pagamento" ? (
        <p className="text-muted-foreground" data-testid="ordine-scadenza">
          I pezzi sono tenuti da parte fino alle {ora(ordine.scadeAt)}. {TESTI_ORDINI_ACCESSORI.nessunAddebito}
        </p>
      ) : null}
      {ordine.motivoChiusura ? (
        <p className="text-muted-foreground" data-testid="ordine-chiusura">
          {MESSAGGI_CHIUSURA[ordine.motivoChiusura]}
        </p>
      ) : null}
      {ordine.stato === "scaduto" && !ordine.motivoChiusura ? (
        <p className="text-muted-foreground" data-testid="ordine-chiusura">
          {MESSAGGI_CHIUSURA.scadenza}
        </p>
      ) : null}
    </div>
  );
}

/** Annulla la propria prenotazione non pagata: i pezzi tornano disponibili. */
export function AnnullaPrenotazione({
  ordine,
  onAnnullato,
}: {
  ordine: OrdineAccessorio;
  onAnnullato: (o: OrdineAccessorio) => void;
}) {
  const servizio = useMemo(() => creaAccessoriOrdiniService(getSupabaseClient()), []);
  const [invio, setInvio] = useState(false);
  const [errore, setErrore] = useState<string | null>(null);
  if (ordine.ruolo !== "acquirente" || ordine.stato !== "in_attesa_pagamento") return null;
  return (
    <div>
      <button
        type="button"
        data-testid="prenotazione-annulla"
        disabled={invio}
        onClick={async () => {
          if (invio) return;
          setInvio(true);
          setErrore(null);
          const r = await servizio.annulla(ordine.id);
          setInvio(false);
          if (r.ok) onAnnullato(r.data);
          else setErrore(r.error);
        }}
        className="rounded-md border px-3 py-1.5 text-sm"
      >
        {invio ? "Annullo…" : "Annulla la prenotazione"}
      </button>
      {errore ? (
        <p role="alert" data-testid="prenotazione-errore" className="mt-2 text-sm text-destructive">
          {errore}
        </p>
      ) : null}
    </div>
  );
}

export type ImpostazioniPagamento = { azioniAbilitate: boolean; chiavePublishable: string | null; inRitorno: boolean };

export function DettaglioOrdineAccessorio({
  iniziale,
  pagamento,
}: {
  iniziale: OrdineAccessorio;
  pagamento?: ImpostazioniPagamento;
}) {
  const [ordine, setOrdine] = useState(iniziale);
  const [pagamentoImpegnato, setPagamentoImpegnato] = useState(false);
  return (
    <section aria-labelledby="titolo-ordine" className="space-y-4">
      <h1 id="titolo-ordine" className="font-serif text-2xl">
        Ordine Accessori
      </h1>
      <RiepilogoOrdineAccessorio ordine={ordine} />
      <PagamentoAccessorio
        ordine={ordine}
        azioniAbilitate={pagamento?.azioniAbilitate === true}
        chiavePublishable={pagamento?.chiavePublishable ?? null}
        inRitorno={pagamento?.inRitorno === true}
        onOrdine={setOrdine}
        onImpegnato={setPagamentoImpegnato}
      />
      {pagamentoImpegnato ? null : <AnnullaPrenotazione ordine={ordine} onAnnullato={setOrdine} />}
      <Link href="/ordini-accessori" className="text-sm underline">
        {TESTI_ORDINI_ACCESSORI.tuttiGliOrdini}
      </Link>
    </section>
  );
}

export function ElencoOrdiniAccessori({
  titolo,
  ordini,
  vuoto,
}: {
  titolo: string;
  ordini: OrdineAccessorio[];
  vuoto: string;
}) {
  return (
    <section aria-label={titolo} className="space-y-3">
      <h2 className="text-lg font-semibold">{titolo}</h2>
      {ordini.length === 0 ? (
        <p className="text-sm text-muted-foreground">{vuoto}</p>
      ) : (
        <ul className="space-y-3">
          {ordini.map((o) => (
            <li key={o.id} data-testid="ordine-riga" className="rounded-lg border p-3">
              <Link href={`/ordini-accessori/${o.id}`} className="block space-y-1">
                <span className="font-medium">
                  {o.articolo.nome} · {o.quantita} {o.quantita === 1 ? "pezzo" : "pezzi"}
                </span>
                <span className="block text-sm text-muted-foreground">
                  {testoStatoOrdine(o)} ·{" "}
                  {o.ruolo === "venditore" ? `incassi ${euro(o.ricevoCents ?? 0)}` : euro(o.totaleAcquirenteCents ?? 0)}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
