// WI-015 — l'analisi DETERMINISTICA dei primi tre worker del Company Brain. Nessun modello AI: regole sul contesto che
// il database consegna con il lease. Un worker produce evidenze e una PROPOSTA (o chiede la chiusura consentita, che il
// server concede solo se verifica che non resta nulla da decidere). Non decide, non fonde, non cancella, non esegue.
// Le chiavi rispettano `brain.payload_ammesso`: niente dati personali, evidenze sotto i 4 KB.

const MAX_RIFERIMENTI = 10;

const riferimenti = (candidati) =>
  candidati.slice(0, MAX_RIFERIMENTI).map((c) => ({
    ...(c.wine_id ? { wine_id: c.wine_id } : {}),
    ...(c.source_record_id ? { record_fonte: c.source_record_id } : {}),
    ...(c.lwin7 ? { lwin7: c.lwin7 } : {}),
    motivo: c.motivo ?? "non_indicato",
  }));

/** Catalog Manager: dal confronto con le identita esistenti alla proposta per il curatore. */
export function analizzaProposta(contesto) {
  if (contesto.stato === "gia_decisa") return { evidenze: [], chiusura: true };
  const candidati = Array.isArray(contesto.candidati) ? contesto.candidati : [];
  const canonici = candidati.filter((c) => c.wine_id);
  const dallaFonte = candidati.filter((c) => c.source_record_id);
  const corrispondenza = contesto.corrispondenza;
  const avvisi = [];
  if (Number(contesto.proposte_stesso_nome) > 0) avvisi.push("altre proposte aperte con lo stesso nome: valutarle insieme");
  if (contesto.affidabilita === "ocr_confermato_utente") avvisi.push("dati letti da etichetta e confermati dall'utente");
  const mancanti = Array.isArray(contesto.mancanti) ? contesto.mancanti : [];
  if (mancanti.includes("annata")) avvisi.push("annata non dichiarata: non va inventata");

  let proposta;
  if (corrispondenza === "autorevole" && canonici.length === 1) {
    proposta = { azione: "collega", wine_id: canonici[0].wine_id, certezza: "collegamento_gia_approvato" };
  } else if (corrispondenza === "ambiguo" || canonici.length > 1 && corrispondenza === "probabile") {
    proposta = { azione: "conflitto", motivo: "piu identita compatibili: serve il curatore, nessuna fusione" };
  } else if (corrispondenza === "probabile" && canonici.length === 1 && dallaFonte.length === 0) {
    proposta = { azione: "collega", wine_id: canonici[0].wine_id, certezza: "probabile_da_verificare" };
  } else if (dallaFonte.length > 0) {
    proposta = { azione: "verifica_fonte", motivo: "la fonte LWIN conosce questo nome: non creare un vino nativo prima di verificarlo" };
  } else if (canonici.length > 0) {
    proposta = { azione: "verifica_duplicato", motivo: "solo somiglianze: la somiglianza non basta a collegare" };
  } else if (corrispondenza === "sconosciuto") {
    proposta = { azione: "crea", motivo: "nessuna identita esistente trovata" };
  } else {
    proposta = { azione: "attendi_curatore", motivo: "corrispondenza non classificabile" };
  }

  return {
    evidenze: [
      {
        tipo: "corrispondenza",
        dettaglio: {
          contributo_id: contesto.contributo_id,
          corrispondenza,
          candidati: riferimenti(candidati),
          campi_mancanti: mancanti.slice(0, 12),
        },
      },
    ],
    proposta: { contributo_id: contesto.contributo_id, ...proposta, avvisi },
  };
}

const SUGGERIMENTI = {
  duplicati_aperti: "decidere le coppie dalla coda «possibili duplicati»",
  omonimi_attivi: "verificare che gli omonimi siano identita diverse",
  conflitti_nativi: "associare il LWIN, dichiarare l'omonimia o ritirare il nativo prima di promuovere",
  canonici_non_piu_live: "rivedere l'aggiornamento LWIN: accorpare o ritirare con motivo, mai in automatico",
  nativi_senza_annata: "aggiungere l'annata solo se dichiarata da una fonte",
  produttori_senza_paese: "completare il paese con una rivendicazione documentata",
  proposte_incoerenti: "controllare il contatore delle proposte indicate",
  importazioni_ferme: "riconciliare l'importazione secondo il runbook",
};

/** Data Quality: dai rilievi del database a un task per il curatore, ordinato per gravita. */
export function analizzaQualita(contesto) {
  const rilievi = Array.isArray(contesto.rilievi) ? contesto.rilievi : [];
  if (rilievi.length === 0) return { evidenze: [], chiusura: true };
  const ordinati = [...rilievi].sort((a, b) => a.severita.localeCompare(b.severita) || a.codice.localeCompare(b.codice));
  return {
    evidenze: ordinati.slice(0, 20).map((r) => ({
      tipo: "rilievo",
      dettaglio: { codice: r.codice, severita: r.severita, conteggio: r.conteggio, esempi: (r.esempi ?? []).slice(0, MAX_RIFERIMENTI) },
    })),
    proposta: {
      azione: "rivedi_qualita",
      priorita: ordinati[0].severita,
      rilievi: ordinati.slice(0, 12).map((r) => ({
        codice: r.codice,
        conteggio: r.conteggio,
        suggerimento: SUGGERIMENTI[r.codice] ?? "verificare i riferimenti indicati",
      })),
    },
  };
}

const GUASTO = new Set(["guasto", "degradato"]);

/**
 * Technical Monitor: distingue stato attuale, storia e freschezza. Non propone deploy, rollback o modifiche: propone
 * che cosa una persona deve verificare e quale prova serve per chiudere. Un verde successivo non e la prova.
 */
export function classificaSegnali(contesto) {
  const segnali = Array.isArray(contesto.segnali) ? contesto.segnali : [];
  if (segnali.length === 0) {
    return { classe: "non_verificato", consecutivi: 0, ritardo_mittente: false };
  }
  const ultimo = segnali[0];
  let consecutivi = 0;
  for (const s of segnali) {
    if (!GUASTO.has(s.stato)) break;
    consecutivi += 1;
  }
  const precedenti = segnali.slice(1).some((s) => GUASTO.has(s.stato));
  const attesa = Number(contesto.intervallo_atteso_minuti) || 0;
  let massimoVuoto = 0;
  for (let i = 0; i + 1 < segnali.length; i++) {
    const vuoto = (Date.parse(segnali[i].osservato) - Date.parse(segnali[i + 1].osservato)) / 60000;
    if (Number.isFinite(vuoto)) massimoVuoto = Math.max(massimoVuoto, vuoto);
  }
  const classe = GUASTO.has(ultimo.stato)
    ? consecutivi >= 2 ? "guasto_persistente" : "guasto_isolato"
    : ultimo.stato === "ok"
      ? precedenti ? "ripristino_da_verificare" : "regolare"
      : "non_verificato";
  return { classe, consecutivi, ritardo_mittente: attesa > 0 && massimoVuoto > attesa * 1.5, massimo_vuoto_minuti: Math.round(massimoVuoto) };
}

const PASSI = {
  guasto_persistente: "verificare la causa subito: due o piu segnali consecutivi non verdi",
  guasto_isolato: "leggere la prova del segnale e controllare il successivo prima di intervenire",
  ripristino_da_verificare: "il segnale e tornato verde: per chiudere serve la prova della causa risolta",
  regolare: "nessun guasto nella storia disponibile: verificare perche il task e stato aperto",
  non_verificato: "stato non determinabile: controllare il mittente",
};

export function analizzaTecnico(contesto) {
  const analisi = classificaSegnali(contesto);
  const segnali = (contesto.segnali ?? []).slice(0, 5).map((s) => ({
    stato: s.stato,
    osservato: s.osservato,
    ...(s.riferimento ? { riferimento: s.riferimento } : {}),
  }));
  return {
    evidenze: [{ tipo: "storia_segnali", dettaglio: { fonte: contesto.fonte, ...analisi, ultimi: segnali } }],
    proposta: {
      azione: "verifica_tecnica",
      fonte: contesto.fonte,
      classe: analisi.classe,
      passo: PASSI[analisi.classe],
      ...(analisi.ritardo_mittente
        ? { nota_freschezza: "il mittente non rispetta la cadenza: un allarme di freschezza puo dipendere dal suo scheduler" }
        : {}),
    },
  };
}

export const ANALISI = {
  "catalogo.proposta": analizzaProposta,
  "qualita.scansione": analizzaQualita,
  "tecnico.segnale": analizzaTecnico,
};
