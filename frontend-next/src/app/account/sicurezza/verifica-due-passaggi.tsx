"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { getSupabaseClient } from "@/lib/supabase/client";
import {
  PERCORSO_CONTINUITA,
  codiceTotpValido,
  messaggioErroreMfa,
  normalizzaCodiceTotp,
} from "@/lib/auth/mfa";

/**
 * Verifica in due passaggi con app authenticator (TOTP di Supabase Auth).
 *
 * Nessun sistema parallelo: enrollment, challenge e verify sono le API
 * `auth.mfa.*` ufficiali, e il livello della sessione (aal1/aal2) è quello che
 * GoTrue scrive nel JWT. Dopo la verifica il client aggiorna i cookie di
 * sessione, così la pagina server /continuita e il database vedono aal2.
 *
 * Tre stati utili:
 * - nessun fattore verificato → enrollment: QR, secret da digitare a mano,
 *   codice di conferma. I fattori lasciati a metà da un tentativo precedente
 *   vengono rimossi prima di crearne uno nuovo (non richiedono aal2);
 * - fattore verificato ma sessione aal1 → challenge con il codice attuale;
 * - sessione aal2 → nulla da fare, accesso alla continuità.
 *
 * Non c'è rimozione del fattore verificato da qui: toglierlo è un gesto di
 * offboarding del titolare, non del delegato.
 */

type Stato =
  | { fase: "caricamento" }
  | { fase: "non-configurato" }
  | { fase: "nessun-fattore" }
  | { fase: "enrollment"; factorId: string; qr: string; secret: string }
  | { fase: "da-confermare"; factorId: string }
  | { fase: "attiva" };

type ErroreAuth = { code?: string | null } | null | undefined;

/** Livello della sessione e fattori, letti dalle API MFA di Supabase Auth. */
async function leggiStato(): Promise<{ stato: Stato; errore: ErroreAuth }> {
  const client = getSupabaseClient();
  if (!client) return { stato: { fase: "non-configurato" }, errore: null };
  const [livello, fattori] = await Promise.all([
    client.auth.mfa.getAuthenticatorAssuranceLevel(),
    client.auth.mfa.listFactors(),
  ]);
  if (livello.error || fattori.error) {
    return { stato: { fase: "nessun-fattore" }, errore: livello.error ?? fattori.error };
  }
  if (livello.data.currentLevel === "aal2") return { stato: { fase: "attiva" }, errore: null };
  // `totp` contiene solo i fattori TOTP verificati.
  const verificato = fattori.data.totp[0];
  return {
    stato: verificato
      ? { fase: "da-confermare", factorId: verificato.id }
      : { fase: "nessun-fattore" },
    errore: null,
  };
}

export default function VerificaDuePassaggi({
  mostraContinuita,
}: {
  readonly mostraContinuita: boolean;
}) {
  const router = useRouter();
  const [stato, setStato] = useState<Stato>({ fase: "caricamento" });
  const [codice, setCodice] = useState("");
  const [inCorso, setInCorso] = useState(false);
  const [errore, setErrore] = useState<string | null>(null);

  const fallisci = (e: ErroreAuth) => setErrore(messaggioErroreMfa(e?.code ?? null));

  const carica = useCallback(async () => {
    const letto = await leggiStato();
    setStato(letto.stato);
    if (letto.errore) fallisci(letto.errore);
  }, []);

  useEffect(() => {
    let attivo = true;
    void leggiStato().then((letto) => {
      if (!attivo) return;
      setStato(letto.stato);
      if (letto.errore) setErrore(messaggioErroreMfa(letto.errore.code ?? null));
    });
    return () => {
      attivo = false;
    };
  }, []);

  const avviaEnrollment = async () => {
    const client = getSupabaseClient();
    if (!client || inCorso) return;
    setErrore(null);
    setInCorso(true);
    try {
      const fattori = await client.auth.mfa.listFactors();
      if (fattori.error) return fallisci(fattori.error);
      for (const f of fattori.data.all) {
        if (f.factor_type === "totp" && f.status === "unverified") {
          const rimosso = await client.auth.mfa.unenroll({ factorId: f.id });
          if (rimosso.error) return fallisci(rimosso.error);
        }
      }
      const { data, error } = await client.auth.mfa.enroll({
        factorType: "totp",
        friendlyName: "Vinea authenticator",
      });
      if (error || !data) return fallisci(error);
      setCodice("");
      setStato({
        fase: "enrollment",
        factorId: data.id,
        qr: data.totp.qr_code,
        secret: data.totp.secret,
      });
    } finally {
      setInCorso(false);
    }
  };

  const conferma = async (factorId: string) => {
    const client = getSupabaseClient();
    if (!client || inCorso || !codiceTotpValido(codice)) return;
    setErrore(null);
    setInCorso(true);
    try {
      const { error } = await client.auth.mfa.challengeAndVerify({
        factorId,
        code: normalizzaCodiceTotp(codice),
      });
      if (error) return fallisci(error);
      setCodice("");
      await carica();
      // I componenti server (e /continuita) rileggono la sessione aal2 dai cookie.
      router.refresh();
    } finally {
      setInCorso(false);
    }
  };

  const campoCodice = (factorId: string, etichetta: string) => (
    <form
      className="mt-4 space-y-3"
      onSubmit={(event) => {
        event.preventDefault();
        void conferma(factorId);
      }}
    >
      <div>
        <Label htmlFor="codice-totp">Codice a 6 cifre dell&apos;app</Label>
        <Input
          id="codice-totp"
          inputMode="numeric"
          autoComplete="one-time-code"
          maxLength={7}
          value={codice}
          onChange={(event) => setCodice(event.target.value)}
          data-testid="mfa-codice"
          className="mt-1 max-w-40 tracking-widest"
        />
      </div>
      <Button
        type="submit"
        disabled={inCorso || !codiceTotpValido(codice)}
        aria-busy={inCorso}
        data-testid="mfa-conferma"
      >
        {inCorso ? "Verifica…" : etichetta}
      </Button>
    </form>
  );

  return (
    <section
      className="rounded-3xl border border-border bg-card p-5 md:p-6"
      data-testid="verifica-due-passaggi"
    >
      <div className="flex items-start gap-3">
        <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
        <div className="min-w-0">
          <h2 className="font-serif text-xl">Verifica in due passaggi</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Serve per le funzioni operative protette. Usa un&apos;app authenticator (per esempio
            quella del tuo password manager) che genera un codice a 6 cifre ogni 30 secondi.
          </p>
        </div>
      </div>

      {errore ? (
        <p
          role="alert"
          data-testid="mfa-errore"
          className="mt-4 rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux"
        >
          {errore}
        </p>
      ) : null}

      {stato.fase === "caricamento" ? (
        <p className="mt-4 text-sm text-muted-foreground" role="status">
          Controllo della sessione…
        </p>
      ) : null}

      {stato.fase === "non-configurato" ? (
        <p className="mt-4 text-sm text-muted-foreground">
          Connessione al servizio di autenticazione non configurata.
        </p>
      ) : null}

      {stato.fase === "nessun-fattore" ? (
        <div className="mt-4 space-y-3">
          <p className="text-sm">
            Non hai ancora collegato un&apos;app authenticator a questo account.
          </p>
          <Button onClick={() => void avviaEnrollment()} disabled={inCorso} data-testid="mfa-avvia">
            {inCorso ? "Preparazione…" : "Collega un'app authenticator"}
          </Button>
        </div>
      ) : null}

      {stato.fase === "enrollment" ? (
        <div className="mt-4 space-y-3" data-testid="mfa-enrollment">
          <p className="text-sm">
            Inquadra il codice QR con l&apos;app, oppure inserisci a mano la chiave qui sotto. Poi
            scrivi il codice che l&apos;app mostra.
          </p>
          {/* eslint-disable-next-line @next/next/no-img-element -- data URL SVG generato da Supabase Auth, niente da ottimizzare */}
          <img
            src={stato.qr}
            alt="Codice QR da inquadrare con l'app authenticator"
            width={192}
            height={192}
            className="rounded-xl border border-border bg-white p-2"
          />
          <p className="text-sm">
            Chiave:{" "}
            <code className="break-all rounded bg-crema px-1.5 py-0.5" data-testid="mfa-secret">
              {stato.secret}
            </code>
          </p>
          {campoCodice(stato.factorId, "Conferma e attiva")}
        </div>
      ) : null}

      {stato.fase === "da-confermare" ? (
        <div className="mt-4" data-testid="mfa-challenge">
          <p className="text-sm">
            L&apos;app authenticator è collegata. Per questa sessione inserisci il codice attuale.
          </p>
          {campoCodice(stato.factorId, "Verifica")}
        </div>
      ) : null}

      {stato.fase === "attiva" ? (
        <div className="mt-4 space-y-3" data-testid="mfa-attiva">
          <p className="text-sm" role="status">
            Verifica in due passaggi completata per questa sessione.
          </p>
          {mostraContinuita ? (
            <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
              <Link href={PERCORSO_CONTINUITA}>Vai a Continuità operativa</Link>
            </Button>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}
