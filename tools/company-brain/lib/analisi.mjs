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
  // WI-016: una proposta in quarantena arriva senza testi; il worker non la analizza e non propone nulla sul catalogo.
  if (contesto.quarantena) {
    return {
      evidenze: [{ tipo: "quarantena", dettaglio: { contributo_id: contesto.contributo_id, motivo: contesto.quarantena } }],
      proposta: { contributo_id: contesto.contributo_id, azione: "quarantena", motivo: contesto.quarantena, avvisi: [] },
    };
  }
  const candidati = Array.isArray(contesto.candidati) ? contesto.candidati : [];
  const canonici = candidati.filter((c) => c.wine_id);
  const dallaFonte = candidati.filter((c) => c.source_record_id);
  const corrispondenza = contesto.corrispondenza;
  const avvisi = [];
  if (Number(contesto.proposte_stesso_nome) > 0) avvisi.push("altre proposte aperte con lo stesso nome: valutarle insieme");
  if (contesto.affidabilita === "ocr_confermato_utente") avvisi.push("dati letti da etichetta e confermati dall'utente");
  const mancanti = Array.isArray(contesto.mancanti) ? contesto.mancanti : [];
  if (mancanti.includes("annata")) avvisi.push("annata non dichiarata: non va inventata");
  const precedenti = Array.isArray(contesto.memoria?.precedenti) ? contesto.memoria.precedenti : [];
  if (precedenti.some((p) => p.stato === "rifiutata")) avvisi.push("una proposta con lo stesso nome è già stata respinta: leggerne il motivo");

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
  proposte_in_quarantena: "rilasciare o respingere dalla quarantena del catalogo",
  annate_future: "correggere l'annata con la fonte: un'annata futura non esiste",
  fonti_in_conflitto: "confrontare le fonti sullo stesso attributo e accettarne una sola",
  dati_con_fonte_revocata: "ritirare o sostituire i dati della fonte non piu autorizzata",
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

// ---------------------------------------------------------------------------------------------
// WI-016 — Wine Research: la verifica di un'informazione entrata da una fonte autorizzata
// ---------------------------------------------------------------------------------------------
const GIORNI_DATO_DATATO = 730;
const ATTENDIBILITA_MINIMA = 3;

/** Confronto strutturale: l'ordine delle chiavi non conta, quello degli elenchi si (e un dato diverso). */
const canonico = (v) =>
  Array.isArray(v)
    ? `[${v.map(canonico).join(",")}]`
    : v && typeof v === "object"
      ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonico(v[k])}`).join(",")}}`
      : JSON.stringify(v);

const CONFLITTI = new Set(["conflitto_con_dato_accettato", "conflitto_fra_fonti"]);

/**
 * Dopo un conflitto, la qualita del catalogo si ricontrolla: il task parte SOLO quando la verifica e stata approvata ed
 * eseguita da una persona (dipendenza dal genitore). E facoltativo: se l'agente non ha quel tipo fra i derivabili, o un
 * limite lo rifiuta, la verifica si consegna comunque e il rifiuto resta nelle evidenze. Non decide e non modifica nulla.
 */
const ricontrolloDopoConflitto = (rivendicazione) => ({
  tipo: "qualita.scansione",
  titolo: `Ricontrollo qualità dopo il conflitto sulla rivendicazione n. ${rivendicazione}`,
  payload: { origine: "ricerca", rivendicazione_id: rivendicazione },
  chiave: `dopo-conflitto-${rivendicazione}`,
  dopo_esecuzione: true,
  facoltativo: true,
});

export function analizzaRicerca(contesto, adesso = new Date()) {
  if (contesto.stato && contesto.stato !== "proposed") return { evidenze: [], chiusura: true };
  const provenienza = contesto.provenienza ?? null;
  const accettata = contesto.accettata ?? null;
  const altre = Array.isArray(contesto.altre_proposte) ? contesto.altre_proposte : [];
  const valore = canonico(contesto.valore ?? null);
  const diverse = altre.filter((a) => canonico(a.valore ?? null) !== valore).length;
  const eta = provenienza ? (adesso.getTime() - Date.parse(provenienza.acquisita)) / 86_400_000 : Number.NaN;

  let azione;
  let passo;
  if (contesto.fonte?.autorizzata !== true) {
    azione = "fonte_non_autorizzata";
    passo = "la fonte non e piu autorizzata: non accettare l'informazione";
  } else if (!provenienza) {
    azione = "provenienza_mancante";
    passo = "manca la provenienza registrata: richiedere riferimento, data e attendibilita";
  } else if (accettata && canonico(accettata.valore ?? null) !== valore) {
    azione = "conflitto_con_dato_accettato";
    passo = "esiste un dato accettato diverso: confrontare le due fonti prima di decidere";
  } else if (accettata) {
    azione = "gia_confermato";
    passo = "il dato e gia accettato con lo stesso valore: la rivendicazione non aggiunge informazione";
  } else if (diverse > 0) {
    azione = "conflitto_fra_fonti";
    passo = "altre proposte dicono cose diverse: non scegliere senza una fonte primaria";
  } else if (!Number.isFinite(eta) || eta > GIORNI_DATO_DATATO) {
    azione = "verifica_aggiornamento";
    passo = "informazione acquisita da oltre due anni: verificare che la fonte la confermi ancora";
  } else if (Number(provenienza.attendibilita) < ATTENDIBILITA_MINIMA) {
    azione = "verifica_attendibilita";
    passo = "attendibilita dichiarata bassa: serve una seconda fonte";
  } else {
    azione = "verifica_e_decidi";
    passo = "nessun conflitto rilevato: leggere il riferimento e decidere dalla scheda del catalogo";
  }

  return {
    evidenze: [
      {
        tipo: "confronto_fonti",
        dettaglio: {
          rivendicazione_id: contesto.rivendicazione_id,
          attributo: contesto.attributo,
          fonte: contesto.fonte?.codice,
          affidabilita_fonte: contesto.fonte?.affidabilita,
          attendibilita: provenienza?.attendibilita ?? null,
          accettata_presente: Boolean(accettata),
          altre_proposte_diverse: diverse,
          giorni_dall_acquisizione: Number.isFinite(eta) ? Math.max(0, Math.round(eta)) : null,
        },
      },
    ],
    // il valore non viene copiato: chi decide lo legge dalla scheda, con la sua fonte
    proposta: { rivendicazione_id: contesto.rivendicazione_id, azione, passo },
    ...(CONFLITTI.has(azione) ? { derivati: [ricontrolloDopoConflitto(contesto.rivendicazione_id)] } : {}),
  };
}

// ---------------------------------------------------------------------------------------------
// WI-016 — Authenticity Assistant: trasforma i segnali dichiarati in passi di verifica. Non giudica la bottiglia.
// ---------------------------------------------------------------------------------------------
const PASSI_VERIFICA = {
  etichetta_non_coerente: { ambito: "identificazione", passo: "confrontare l'etichetta con una scheda di fonte autorizzata, senza concludere dalla sola foto" },
  annata_non_coerente: { ambito: "identificazione", passo: "controllare annata dichiarata, capsula e documenti di acquisto" },
  produttore_non_coerente: { ambito: "identificazione", passo: "verificare il nome del produttore con una fonte primaria" },
  qualita_foto_insufficiente: { ambito: "qualita_foto", passo: "richiedere nuove fotografie nitide e complete, con il consenso del proprietario" },
  provenienza_non_documentata: { ambito: "provenienza", passo: "richiedere documenti di acquisto e di conservazione" },
  condizioni_da_verificare: { ambito: "condizioni", passo: "far controllare livello, capsula ed etichetta da una persona competente" },
};

export function analizzaAutenticita(contesto) {
  if (contesto.stato === "gia_decisa") return { evidenze: [], chiusura: true };
  const anomalie = (Array.isArray(contesto.anomalie) ? contesto.anomalie : []).slice(0, 6);
  const passi = anomalie.map((segnale) => ({
    segnale,
    ...(PASSI_VERIFICA[segnale] ?? { ambito: "da_classificare", passo: "segnale non riconosciuto: valutarlo a mano" }),
  }));
  return {
    evidenze: [{ tipo: "segnali_dichiarati", dettaglio: { segnali: anomalie, ambiti: [...new Set(passi.map((p) => p.ambito))] } }],
    proposta: {
      azione: "richiedi_verifica_umana",
      // l'unico valore possibile: ne un modello ne una regola possono stabilirlo
      autenticita: "non_determinabile",
      passi,
    },
  };
}

export const ANALISI = {
  "catalogo.proposta": analizzaProposta,
  "qualita.scansione": analizzaQualita,
  "tecnico.segnale": analizzaTecnico,
  "ricerca.verifica": analizzaRicerca,
  "autenticita.verifica": analizzaAutenticita,
};
