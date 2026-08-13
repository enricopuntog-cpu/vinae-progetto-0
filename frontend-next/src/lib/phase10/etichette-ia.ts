// Etichette di trasparenza IA sulle tre superfici della Fase 10.
//
// Le tre superfici IA in produzione dalla Fase 10 — pannello Sommelier nel
// Layout, pannello Assistente del passo Identificazione, pannello di
// abbinamento in `/esplora` — portano già la parola «AI», ma nel titolo del
// pannello: «Sommelier AI» è un'insegna, non una dichiarazione. Chi interagisce
// con un sistema di IA deve saperlo (AI Act, art. 50, in vigore dal 2 agosto
// 2026), e deve saperlo *mentre* lo fa, non per averlo dedotto da un nome.
//
// Queste tre righe sono la prima azione concreta indirizzata a quell'obbligo.
// Non lo esauriscono e non spostano il blocco della revisione legale: l'obbligo
// del DSA sulla dichiarazione dei motivi (art. 17) riguarda la singola
// decisione di moderazione che un utente subisce, e non si assolve né con
// un'etichetta né con un'accettazione generica data prima. Il ragionamento per
// esteso è nella §9 di `docs/PHASE_11_AI_EXTENSIONS_SPEC.md`.
//
// Perché il testo sta qui e non scritto dentro i tre file: è testo con una
// ragione normativa dietro, quindi va cambiato in un punto solo quando la
// revisione legale risponderà, e un test può verificare che nessuna delle tre
// superfici resti scoperta — che è il modo in cui una superficie aggiunta in
// futuro senza etichetta si fa notare invece di passare.
//
// Perché dicono «IA» e non «AI»: i pannelli tengono «AI» come parte del proprio
// nome, e un'etichetta scritta nello stesso modo si leggerebbe come un'altra
// insegna. «IA» è il termine italiano corrente, e qui serve una frase che si
// legga come un'affermazione.

/** Le superfici IA della Fase 10 che espongono un'etichetta. */
export type SuperficieIA = "sommelier" | "catalogazione" | "abbinamento";

/**
 * Il testo mostrato su ciascuna superficie, al minimo indispensabile.
 *
 * Ogni riga descrive quello che la superficie fa davvero: la catalogazione
 * *suggerisce* e non compila — applicare il suggerimento ai campi resta un
 * secondo gesto esplicito del venditore — e l'abbinamento *chiede* al modello
 * una scelta dentro il catalogo, non altrove.
 */
export const ETICHETTA_IA: Readonly<Record<SuperficieIA, string>> = Object.freeze({
  sommelier: "Parla con il tuo sommelier IA",
  catalogazione: "Fatti suggerire i campi dall'assistente IA",
  abbinamento: "Chiedi gli abbinamenti al sommelier IA",
});

/**
 * Il vincolo che rende un'etichetta un'etichetta: deve nominare l'IA.
 *
 * Non è una formalità. Una riformulazione che togliesse la parola — «parla con
 * il tuo sommelier virtuale» — resterebbe gradevole e smetterebbe di fare il
 * lavoro per cui queste righe esistono. Il test lo verifica su tutte e tre.
 */
export const NOMINA_IA = /\bIA\b/;
