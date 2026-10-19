import { NextResponse, type NextRequest } from "next/server";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { ambienteCorrente, risolviOriginePubblica } from "@/lib/auth/origine-redirect";
import {
  classificaErroreLinkEmail,
  leggiLinkEmail,
  type FlussoLinkEmail,
} from "@/lib/auth/link-email-auth";
import type { CodiceErroreAuth } from "@/lib/auth/errori-auth";

/**
 * Gestore `GET` delle route `/auth/recupero` e `/auth/accesso`. Il perché è in
 * `link-email-auth.ts`; qui c'è solo l'esecuzione, con le stesse protezioni di
 * `/auth/confirm` (PR #202):
 *
 * - l'origine dei redirect la decide il server (`risolviOriginePubblica`);
 * - ogni risposta è un 303 verso un URL pulito, `private, no-store`: il
 *   `token_hash` non compare in nessun `Location`;
 * - nel log solo il codice applicativo e i campi strutturati dell'errore, mai
 *   il token né il testo del provider;
 * - un link malformato o di un altro tipo non arriva a `verifyOtp`.
 *
 * Nessun gestore `HEAD`: come misurato per `/auth/confirm`, su Netlify una
 * `HEAD` raggiunge comunque il gestore `GET`, e uno scanner di posta che apre
 * il link consuma il token come farebbe con il link standard di Supabase.
 */
export const gestoreLinkEmail =
  (flusso: FlussoLinkEmail) =>
  async (request: NextRequest): Promise<NextResponse> => {
    const hostAnnunciato =
      request.headers.get("x-forwarded-host") ?? request.headers.get("host") ?? undefined;
    const { origine, sorgente } = risolviOriginePubblica(
      request.nextUrl,
      ambienteCorrente(),
      hostAnnunciato,
    );

    const vaiA = (percorso: string) => {
      const risposta = NextResponse.redirect(`${origine}${percorso}`, 303);
      risposta.headers.set("X-Vinea-Origine-Sorgente", sorgente);
      risposta.headers.set("Cache-Control", "private, no-store");
      return risposta;
    };

    const lettura = leggiLinkEmail(flusso, request.nextUrl.searchParams);

    const vaiAErrore = (codice: CodiceErroreAuth, dettaglio?: { code?: string; status?: number }) => {
      console.error(flusso.etichettaLog, codice, dettaglio?.code ?? "", dettaglio?.status ?? "");
      return vaiA(flusso.percorsoErrore(codice, lettura.destinazione));
    };

    if (!lettura.ok) return vaiAErrore(lettura.codice);

    const supabase = await getSupabaseServerClient();
    if (!supabase) return vaiAErrore("configurazione-assente");

    const { error } = await supabase.auth.verifyOtp({
      token_hash: lettura.tokenHash,
      type: flusso.tipo,
    });
    if (error) {
      return vaiAErrore(classificaErroreLinkEmail(flusso, error), {
        ...(error.code ? { code: error.code } : {}),
        ...(error.status ? { status: error.status } : {}),
      });
    }

    return vaiA(lettura.destinazione);
  };
