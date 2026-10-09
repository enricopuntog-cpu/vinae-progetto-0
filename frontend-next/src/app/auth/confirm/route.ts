import { NextResponse, type NextRequest } from "next/server";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { ambienteCorrente, risolviOriginePubblica } from "@/lib/auth/origine-redirect";
import {
  classificaErroreConferma,
  leggiRichiestaConferma,
  percorsoErroreConferma,
} from "@/lib/auth/conferma-email";
import type { CodiceErroreAuth } from "@/lib/auth/errori-auth";

/**
 * Conferma della registrazione via email: `?token_hash=…&type=email`.
 *
 * Il perché, con le prove del 9 ottobre 2026, è in `lib/auth/conferma-email.ts`.
 * In breve: la verifica avviene qui, server-side, con `verifyOtp`, e non
 * dipende dal `code_verifier` PKCE rimasto nel browser che ha registrato;
 * la sessione viene scritta nei cookie del browser che apre il link.
 *
 * Regole condivise con `/auth/callback`, non duplicate:
 * - l'origine dei redirect la decide il server (`risolviOriginePubblica`);
 * - la destinazione è solo un percorso relativo (`percorsoRelativoSicuro`);
 * - in caso d'errore esce un codice del vocabolario, mai il testo del provider.
 *
 * Il `token_hash` non compare in nessun `Location` né in nessun log: ogni
 * risposta è un redirect verso un URL pulito.
 */
export async function GET(request: NextRequest) {
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
    risposta.headers.set("Referrer-Policy", "no-referrer");
    return risposta;
  };

  const lettura = leggiRichiestaConferma(request.nextUrl.searchParams);

  /** Solo codici e campi strutturati nel log: il token resta fuori. */
  const vaiAErrore = (codice: CodiceErroreAuth, dettaglio?: { code?: string; status?: number }) => {
    console.error("[auth/confirm]", codice, dettaglio?.code ?? "", dettaglio?.status ?? "");
    return vaiA(percorsoErroreConferma(codice, lettura.destinazione));
  };

  if (!lettura.ok) return vaiAErrore(lettura.codice);

  const supabase = await getSupabaseServerClient();
  if (!supabase) return vaiAErrore("configurazione-assente");

  const { error } = await supabase.auth.verifyOtp({
    token_hash: lettura.tokenHash,
    type: lettura.tipo,
  });
  if (error) {
    return vaiAErrore(classificaErroreConferma(error), {
      ...(error.code ? { code: error.code } : {}),
      ...(error.status ? { status: error.status } : {}),
    });
  }

  return vaiA(lettura.destinazione);
}

/**
 * Le anteprime dei client di posta e alcuni scanner provano i link con `HEAD`.
 * Senza questa funzione Next risponderebbe a `HEAD` eseguendo `GET`, cioè
 * consumando il token monouso prima che l'utente tocchi il link. Qui non si
 * verifica nulla e non si scrive alcun cookie.
 */
export function HEAD() {
  return new NextResponse(null, {
    status: 204,
    headers: { "Cache-Control": "private, no-store" },
  });
}
