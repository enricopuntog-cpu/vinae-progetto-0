// Prova REST e Storage della pubblicazione automatica degli annunci Accessori
// e della moderazione successiva (12zk, parte E2E).
//
// La griglia SQL 12zk simula i claim; questa prova passa invece dai servizi
// reali dello stack locale: GoTrue emette i token, PostgREST li inoltra alle
// porte `annunci_accessori_*`, Storage firma e serve le foto con le policy
// reali. Misura anche il limite di revoca documentato: una URL firmata gia
// emessa vale fino a scadenza anche dopo l'oscuramento.
//
// Solo loopback. Fixture e pulizia sono SQL separati, eseguiti da
// `12g_ci_run.sh`. L'ultima riga stampata e il riepilogo JSON
// `{"passed":n,"total":m}` letto dal runner.

import { randomUUID } from "node:crypto";

const URL_BASE = process.env.E2E_SUPABASE_URL ?? "";
const ANON = process.env.E2E_ANON_KEY ?? "";
const PASSWORD = process.env.E2E_PASSWORD ?? "";
const PRODUCTION_REF = "pijnmcllmfgjmgsvtcej";

if (!URL_BASE || !ANON || !PASSWORD) {
  console.error("Servono E2E_SUPABASE_URL, E2E_ANON_KEY, E2E_PASSWORD.");
  process.exit(2);
}
let target;
try {
  target = new URL(URL_BASE);
} catch {
  console.error("Rifiutato: E2E_SUPABASE_URL non e un URL valido.");
  process.exit(2);
}
if (URL_BASE.includes(PRODUCTION_REF) || !["127.0.0.1", "localhost", "[::1]"].includes(target.hostname)) {
  console.error("Rifiutato: la prova gira solo su uno stack locale.");
  process.exit(2);
}

const BUCKET = "cantina-accessori-foto";
// WebP minimo valido (1x1).
const WEBP = Buffer.from("UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA", "base64");

const results = [];
const record = (id, ok, detail) => {
  results.push({ id, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${id}${detail ? ` — ${detail}` : ""}`);
};

const accedi = async (email) => {
  const res = await fetch(`${URL_BASE}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: PASSWORD }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || !json.access_token) throw new Error(`accesso fallito per ${email}: HTTP ${res.status}`);
  return { token: json.access_token, id: json.user.id };
};

/** RPC PostgREST: restituisce { status, body } con body gia decodificato. */
const rpc = async (nome, args, token) => {
  const res = await fetch(`${URL_BASE}/rest/v1/rpc/${nome}`, {
    method: "POST",
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${token ?? ANON}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args ?? {}),
  });
  const testo = await res.text();
  let body = null;
  try {
    body = testo ? JSON.parse(testo) : null;
  } catch {
    body = testo;
  }
  return { status: res.status, body };
};
const hint = (r) => (r.body && typeof r.body === "object" ? (r.body.hint ?? "") : "");
const ok2xx = (r) => r.status >= 200 && r.status < 300;

const storageFirma = async (percorso, token) => {
  const res = await fetch(`${URL_BASE}/storage/v1/object/sign/${BUCKET}/${percorso}`, {
    method: "POST",
    headers: { apikey: ANON, Authorization: `Bearer ${token ?? ANON}`, "Content-Type": "application/json" },
    body: JSON.stringify({ expiresIn: 900 }),
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, url: json.signedURL ? `${URL_BASE}/storage/v1${json.signedURL}` : null };
};
const scarica = async (url) => {
  const res = await fetch(url);
  const buf = Buffer.from(await res.arrayBuffer());
  return { status: res.status, tipo: res.headers.get("content-type"), byte: buf.length };
};

const main = async () => {
  const [fnd, ua, ub, ur, adm] = await Promise.all(
    [1, 2, 3, 4, 5].map((n) => accedi(`u0${n}@e2e-12zk.test`)),
  );

  // ---- interruttori e categorie: tutto parte spento -------------------------------------
  const elencoChiuso = await rpc("annunci_accessori_pubblici_elenca", {}, null);
  record("E1 vetrina anonima vuota a pubblicazione spenta", ok2xx(elencoChiuso) && elencoChiuso.body.length === 0,
    `HTTP ${elencoChiuso.status}`);

  const statoAdmin = await rpc("annunci_accessori_admin_stato", {}, adm.token);
  record("E2 pubblicazione spenta, 0 categorie approvate, admin senza rilascio non puo rilasciare",
    ok2xx(statoAdmin) && statoAdmin.body.pubblicazione_attiva === false &&
      statoAdmin.body.categorie_pubblicabili === 0 && statoAdmin.body.puo_rilasciare === false,
    JSON.stringify(statoAdmin.body));

  const rifiuto = await rpc("annunci_accessori_admin_pubblicazione_imposta", { p_attiva: true, p_motivo: "prova" }, adm.token);
  record("E3 un admin senza rilascio non accende la pubblicazione",
    rifiuto.status === 403 && hint(rifiuto) === "rilascio_non_autorizzato", `HTTP ${rifiuto.status} ${hint(rifiuto)}`);
  const rifiutoUtente = await rpc("annunci_accessori_admin_pubblicazione_imposta", { p_attiva: true, p_motivo: "prova" }, ua.token);
  record("E4 un utente ordinario non accende nulla", rifiutoUtente.status === 403, `HTTP ${rifiutoUtente.status}`);

  // Il rilascio accende la Cantina Accessori, la preparazione e la pubblicazione, e approva le categorie.
  const accesi = [
    await rpc("cantina_accessori_admin_imposta", { p_interruttore: "funzione", p_attiva: true, p_motivo: "prova 12zk" }, fnd.token),
    await rpc("annunci_accessori_admin_imposta", { p_attiva: true, p_motivo: "prova 12zk" }, fnd.token),
    await rpc("annunci_accessori_admin_pubblicazione_imposta", { p_attiva: true, p_motivo: "prova 12zk" }, fnd.token),
  ];
  record("E5 il ruolo di rilascio accende i tre interruttori con le porte reali", accesi.every(ok2xx),
    accesi.map((r) => r.status).join(","));

  const categorie = await rpc("annunci_accessori_admin_categorie_pubblicazione", {}, fnd.token);
  const idCat = (slug) => categorie.body.find((c) => c.slug === slug)?.id;
  record("E6 nessuna categoria e approvata per default; quelle chiuse non sono vendibili",
    ok2xx(categorie) && categorie.body.every((c) => c.approvata === false && c.pubblicabile === false) &&
      categorie.body.find((c) => c.slug === "pulizia")?.vendibile === false &&
      categorie.body.find((c) => c.slug === "calici-da-rosso")?.vendibile === true,
    `${categorie.body.length} categorie`);

  const pulizia = await rpc("annunci_accessori_admin_categoria_pubblicabile_imposta",
    { p_categoria: idCat("pulizia"), p_pubblicabile: true, p_motivo: "prova" }, fnd.token);
  record("E7 una categoria chiusa non si approva mai", pulizia.status === 400 && hint(pulizia) === "categoria_non_approvabile",
    `HTTP ${pulizia.status} ${hint(pulizia)}`);
  const figlia = await rpc("annunci_accessori_admin_categoria_pubblicabile_imposta",
    { p_categoria: idCat("calici-da-rosso"), p_pubblicabile: true, p_motivo: "prova" }, fnd.token);
  record("E8 la categoria figlia non si approva prima del genitore", figlia.status === 400 && hint(figlia) === "categoria_genitore_non_approvata",
    `HTTP ${figlia.status} ${hint(figlia)}`);
  const approva = [
    await rpc("annunci_accessori_admin_categoria_pubblicabile_imposta", { p_categoria: idCat("calici"), p_pubblicabile: true, p_motivo: "prova 12zk" }, fnd.token),
    await rpc("annunci_accessori_admin_categoria_pubblicabile_imposta", { p_categoria: idCat("calici-da-rosso"), p_pubblicabile: true, p_motivo: "prova 12zk" }, fnd.token),
  ];
  record("E9 il rilascio approva genitore e figlia", approva.every(ok2xx), approva.map((r) => r.status).join(","));

  // ---- il venditore prepara e pubblica con token reali -------------------------------------
  const itemId = randomUUID();
  const item = await rpc("cantina_accessori_salva", {
    p_id: itemId,
    p_dati: { categoria_id: idCat("calici-da-rosso"), nome: "Calice E2E 12zk", quantita: 4, note: "NOTA-PRIVATA-12zk", condizione: "usato" },
  }, ua.token);
  record("E10 il venditore crea l'accessorio in Cantina", ok2xx(item), `HTTP ${item.status}`);

  const foto = `${ua.id}/${itemId}/${randomUUID()}.webp`;
  const carica = await fetch(`${URL_BASE}/storage/v1/object/${BUCKET}/${foto}`, {
    method: "POST",
    headers: { apikey: ANON, Authorization: `Bearer ${ua.token}`, "Content-Type": "image/webp" },
    body: WEBP,
  });
  const collega = await rpc("cantina_accessori_immagini_imposta", { p_id: itemId, p_percorsi: [foto] }, ua.token);
  record("E11 il venditore carica la foto nel bucket privato e la collega", carica.ok && ok2xx(collega),
    `upload ${carica.status}, collega ${collega.status}`);

  const annId = randomUUID();
  const bozza = await rpc("annunci_accessori_salva", {
    p_id: annId,
    p_dati: { cantina_id: itemId, quantita: 2, prezzo_unitario_cents: 2000, condizione: "come_nuovo", descrizione: "Due calici.", conforme: true },
  }, ua.token);
  record("E12 la bozza nasce bozza e non e pubblica", ok2xx(bozza) && bozza.body.stato === "bozza" && bozza.body.pubblico === false,
    `HTTP ${bozza.status}`);
  const bozzaInVetrina = await rpc("annunci_accessori_pubblico_dettaglio", { p_id: annId }, null);
  record("E13 una bozza non e leggibile dal pubblico", ok2xx(bozzaInVetrina) && bozzaInVetrina.body === null, `HTTP ${bozzaInVetrina.status}`);

  const altro = await rpc("annunci_accessori_pubblica", { p_id: annId }, ub.token);
  record("E14 un altro utente non pubblica l'annuncio di un altro", altro.status === 400 && hint(altro) === "non_trovato",
    `HTTP ${altro.status} ${hint(altro)}`);

  const pubblica = await rpc("annunci_accessori_pubblica", { p_id: annId }, ua.token);
  record("E15 la pubblicazione e automatica: pubblicato e visibile subito, senza approvazione",
    ok2xx(pubblica) && pubblica.body.stato === "pubblicato" && pubblica.body.pubblico === true,
    `HTTP ${pubblica.status} ${pubblica.body?.stato}`);

  // ---- il pubblico vede solo la forma chiusa -------------------------------------
  const vetrina = await rpc("annunci_accessori_pubblici_elenca", {}, null);
  const scheda = Array.isArray(vetrina.body) ? vetrina.body.find((a) => a.id === annId) : null;
  const chiavi = scheda ? Object.keys(scheda).sort().join(",") : "";
  record("E16 la vetrina anonima mostra l'annuncio con le sole chiavi pubbliche, non acquistabile",
    Boolean(scheda) && scheda.acquistabile === false &&
      chiavi === "acquistabile,aggiornato_at,categoria,condizione,descrizione,foto,id,marchio,nome,prezzo_acquirente_cents,pubblicato_at,quantita,venditore",
    chiavi);
  const json = JSON.stringify(vetrina.body);
  record("E17 nessuna nota privata ne prezzo del venditore nella risposta pubblica",
    !json.includes("NOTA-PRIVATA-12zk") && !json.includes('"prezzo_unitario_cents"') && scheda?.prezzo_acquirente_cents === 2273,
    `prezzo acquirente ${scheda?.prezzo_acquirente_cents}`);

  const tabelle = await fetch(`${URL_BASE}/rest/v1/annunci_accessori?select=*`, {
    headers: { apikey: ANON, Authorization: `Bearer ${ua.token}`, "Accept-Profile": "private" },
  });
  const tabellePubbliche = await fetch(`${URL_BASE}/rest/v1/annunci_accessori?select=*`, {
    headers: { apikey: ANON, Authorization: `Bearer ${ua.token}` },
  });
  record("E18 le tabelle degli annunci non sono raggiungibili da PostgREST (schema private non esposto)",
    !tabelle.ok && !tabellePubbliche.ok, `private ${tabelle.status}, public ${tabellePubbliche.status}`);

  // ---- Storage ----------------------------------------------------------------------------
  const firmaAnonima = await storageFirma(foto, null);
  const scaricata = firmaAnonima.url ? await scarica(firmaAnonima.url) : null;
  record("E19 l'anonimo firma e scarica la foto di un annuncio visibile",
    firmaAnonima.status === 200 && scaricata?.status === 200 && scaricata.tipo === "image/webp" && scaricata.byte === WEBP.length,
    `firma ${firmaAnonima.status}, file ${scaricata?.status} ${scaricata?.tipo}`);

  const pubblicoDiretto = await fetch(`${URL_BASE}/storage/v1/object/public/${BUCKET}/${foto}`);
  record("E20 il bucket resta privato: l'URL pubblico diretto non serve nulla", !pubblicoDiretto.ok, `HTTP ${pubblicoDiretto.status}`);

  // Una seconda foto dell'accessorio, NON nello snapshot: non e firmabile dal pubblico.
  const foto2 = `${ua.id}/${itemId}/${randomUUID()}.webp`;
  await fetch(`${URL_BASE}/storage/v1/object/${BUCKET}/${foto2}`, {
    method: "POST",
    headers: { apikey: ANON, Authorization: `Bearer ${ua.token}`, "Content-Type": "image/webp" },
    body: WEBP,
  });
  const firmaNonSnapshot = await storageFirma(foto2, null);
  const firmaProprietario = await storageFirma(foto2, ua.token);
  record("E21 una foto fuori dallo snapshot non e firmabile dal pubblico, lo e dal proprietario",
    firmaNonSnapshot.status >= 400 && firmaProprietario.status === 200,
    `anonimo ${firmaNonSnapshot.status}, proprietario ${firmaProprietario.status}`);

  const cancellaFoto = await fetch(`${URL_BASE}/storage/v1/object/${BUCKET}/${foto}`, {
    method: "DELETE",
    headers: { apikey: ANON, Authorization: `Bearer ${ua.token}` },
  });
  const ancora = await storageFirma(foto, null);
  record("E22 il venditore non cancella un file citato dallo snapshot di un annuncio pubblicato",
    ancora.status === 200, `DELETE ${cancellaFoto.status}, firma dopo ${ancora.status}`);

  // ---- segnalazione ----------------------------------------------------------------------
  const anonSegnala = await rpc("segnalazione_annuncio_accessorio_invia", { p_id: annId, p_motivo: "Prezzo anomalo" }, null);
  record("E23 nessuna segnalazione anonima: la porta e chiusa ad anon", anonSegnala.status === 401 || anonSegnala.status === 403,
    `HTTP ${anonSegnala.status}`);
  const propria = await rpc("segnalazione_annuncio_accessorio_invia", { p_id: annId, p_motivo: "Prezzo anomalo" }, ua.token);
  record("E24 il venditore non segnala il proprio annuncio", propria.status === 400, `HTTP ${propria.status}`);
  const segnala = await rpc("segnalazione_annuncio_accessorio_invia",
    { p_id: annId, p_motivo: "Articolo alcolico o regolamentato", p_descrizione: "Sembra una sciabola." }, ur.token);
  const reportId = segnala.body;
  record("E25 un utente autenticato segnala l'annuncio visibile", ok2xx(segnala) && typeof reportId === "string",
    `HTTP ${segnala.status}`);
  const doppia = await rpc("segnalazione_annuncio_accessorio_invia", { p_id: annId, p_motivo: "Prezzo anomalo" }, ur.token);
  record("E26 una sola segnalazione aperta per utente e annuncio", doppia.status === 400, `HTTP ${doppia.status}`);

  const mie = await fetch(`${URL_BASE}/rest/v1/my_reports?select=codice,target_tipo,stato,priorita`, {
    headers: { apikey: ANON, Authorization: `Bearer ${ur.token}` },
  });
  const mieJson = await mie.json().catch(() => []);
  record("E27 il segnalante rilegge la propria pratica (my_reports) con priorita alta",
    mie.ok && mieJson.length === 1 && mieJson[0].target_tipo === "annuncio_accessorio" && mieJson[0].priorita === "alta",
    JSON.stringify(mieJson[0] ?? null));
  const coda = await fetch(`${URL_BASE}/rest/v1/moderation_report_queue?select=id,target_id`, {
    headers: { apikey: ANON, Authorization: `Bearer ${ur.token}` },
  });
  const codaJson = await coda.json().catch(() => []);
  const codaAdmin = await fetch(`${URL_BASE}/rest/v1/moderation_report_queue?select=id,target_id&id=eq.${reportId}`, {
    headers: { apikey: ANON, Authorization: `Bearer ${adm.token}` },
  });
  const codaAdminJson = await codaAdmin.json().catch(() => []);
  record("E28 la coda di moderazione e solo dell'admin e porta il bersaglio",
    Array.isArray(codaJson) && codaJson.length === 0 && codaAdminJson.length === 1 && codaAdminJson[0].target_id === annId,
    `utente ${codaJson.length ?? "?"}, admin ${codaAdminJson.length ?? "?"}`);

  // ---- moderazione: oscuramento immediato sulle nuove letture --------------------------------
  const firmataPrima = await storageFirma(foto, null);
  const nonAdmin = await rpc("moderazione_sospensione", { p_report_id: reportId, p_motivazione: "prova" }, ur.token);
  record("E29 un utente ordinario non puo sospendere", nonAdmin.status === 403, `HTTP ${nonAdmin.status}`);
  const sospendi = await rpc("moderazione_sospensione",
    { p_report_id: reportId, p_motivazione: "Foto da verificare: sospetto articolo vietato" }, adm.token);
  record("E30 l'admin sospende l'annuncio dalla pratica esistente", ok2xx(sospendi), `HTTP ${sospendi.status}`);

  const dopo = await rpc("annunci_accessori_pubblici_elenca", {}, null);
  const dettaglioDopo = await rpc("annunci_accessori_pubblico_dettaglio", { p_id: annId }, null);
  const firmaDopo = await storageFirma(foto, null);
  record("E31 effetto immediato sulle nuove letture: fuori vetrina, dettaglio nullo, nessuna nuova firma",
    ok2xx(dopo) && !dopo.body.some((a) => a.id === annId) && dettaglioDopo.body === null && firmaDopo.status >= 400,
    `firma dopo ${firmaDopo.status}`);

  // Limite di revoca documentato: una URL gia firmata vale fino a scadenza (900 s).
  const vecchia = firmataPrima.url ? await scarica(firmataPrima.url) : null;
  record("E32 limite documentato: una URL firmata prima dell'oscuramento resta valida fino a scadenza",
    vecchia?.status === 200, `HTTP ${vecchia?.status} (documentato in VPM_015B3 §9, 900 s)`);

  const adminFoto = await storageFirma(foto, adm.token);
  record("E33 l'admin reale firma ancora la foto dell'annuncio in moderazione", adminFoto.status === 200, `HTTP ${adminFoto.status}`);

  const miaVista = await rpc("annunci_accessori_elenca", { p_ritirati: false }, ua.token);
  const mio = miaVista.body.find((a) => a.id === annId);
  record("E34 il venditore vede stato, provvedimento e motivo (mai chi ha deciso)",
    mio?.stato === "oscurato" && mio.pubblico === false && mio.moderazione?.provvedimento === "sospensione" &&
      /Foto da verificare/.test(mio.moderazione.motivo) && !JSON.stringify(mio).includes("stato_aggiornato_da"),
    JSON.stringify(mio?.moderazione ?? null));

  // ---- l'oscurato non torna pubblico da solo -------------------------------------------------
  const ripubblica = await rpc("annunci_accessori_pubblica", { p_id: annId }, ua.token);
  const modifica = await rpc("annunci_accessori_salva",
    { p_id: annId, p_dati: { descrizione: "Descrizione ritoccata dopo la sospensione" } }, ua.token);
  const bozzaAgain = await rpc("annunci_accessori_transizione", { p_id: annId, p_a: "bozza" }, ua.token);
  const stessa = await rpc("annunci_accessori_pubblica", { p_id: annId }, ua.token);
  const finaleVetrina = await rpc("annunci_accessori_pubblici_elenca", {}, null);
  record("E35 ripetere la RPC, modificare o tornare in bozza non riapre un annuncio oscurato",
    ripubblica.status === 400 && hint(ripubblica) === "transizione_non_ammessa" &&
      modifica.status === 400 && hint(modifica) === "annuncio_non_modificabile" &&
      bozzaAgain.status === 400 && stessa.status === 400 && !finaleVetrina.body.some((a) => a.id === annId),
    `${ripubblica.status}/${modifica.status}/${bozzaAgain.status}/${stessa.status}`);

  // ---- ripristino dell'amministrazione ------------------------------------------------------
  const nonRiapre = await rpc("annunci_accessori_admin_modera", { p_id: annId, p_azione: "ripristina", p_motivazione: "prova" }, ua.token);
  const ripristina = await rpc("annunci_accessori_admin_modera",
    { p_id: annId, p_azione: "ripristina", p_motivazione: "Verificato: conforme" }, adm.token);
  const tornata = await rpc("annunci_accessori_pubblici_elenca", {}, null);
  const firmaTornata = await storageFirma(foto, null);
  record("E36 solo l'admin riapre; l'annuncio torna in vetrina e la foto si firma di nuovo",
    nonRiapre.status === 403 && ok2xx(ripristina) && tornata.body.some((a) => a.id === annId) && firmaTornata.status === 200,
    `${nonRiapre.status}/${ripristina.status}/${firmaTornata.status}`);

  const dettaglio = await rpc("annunci_accessori_admin_dettaglio", { p_id: annId }, adm.token);
  const dettaglioUtente = await rpc("annunci_accessori_admin_dettaglio", { p_id: annId }, ua.token);
  record("E37 il dettaglio admin ha segnalazioni e storico; per l'utente e negato",
    ok2xx(dettaglio) && dettaglio.body.segnalazioni.length === 1 && dettaglio.body.storico.length >= 2 &&
      !JSON.stringify(dettaglio.body).includes("NOTA-PRIVATA-12zk") && dettaglioUtente.status === 403,
    `storico ${dettaglio.body?.storico?.length}`);

  // ---- spegnere nasconde subito ----------------------------------------------------------------
  const spegni = await rpc("annunci_accessori_admin_pubblicazione_imposta", { p_attiva: false, p_motivo: "spegnimento di prova" }, adm.token);
  const spenta = await rpc("annunci_accessori_pubblici_elenca", {}, null);
  const firmaSpenta = await storageFirma(foto, null);
  record("E38 un admin spegne la pubblicazione: vetrina vuota e foto non firmabili subito",
    ok2xx(spegni) && spenta.body.length === 0 && firmaSpenta.status >= 400, `firma ${firmaSpenta.status}`);

  // Pulizia delle approvazioni dalle porte reali (la pulizia SQL resta il paracadute).
  await rpc("annunci_accessori_admin_categoria_pubblicabile_imposta", { p_categoria: idCat("calici-da-rosso"), p_pubblicabile: false, p_motivo: "chiusura prova" }, adm.token);
  await rpc("annunci_accessori_admin_categoria_pubblicabile_imposta", { p_categoria: idCat("calici"), p_pubblicabile: false, p_motivo: "chiusura prova" }, adm.token);
};

try {
  await main();
} catch (errore) {
  record("ERR esecuzione interrotta", false, errore instanceof Error ? errore.message : String(errore));
}
const passed = results.filter((r) => r.ok).length;
console.log(JSON.stringify({ passed, total: results.length }));
process.exit(passed === results.length && results.length > 0 ? 0 : 1);
