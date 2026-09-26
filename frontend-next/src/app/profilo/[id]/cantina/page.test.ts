import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const pagina = readFileSync(new URL("./page.tsx", import.meta.url), "utf8");
const caricamento = readFileSync(new URL("./loading.tsx", import.meta.url), "utf8");
const nonTrovato = readFileSync(new URL("../not-found.tsx", import.meta.url), "utf8");
const progetto = join(import.meta.dir, "../../../../..");
const contratti = readFileSync(join(progetto, "src/services/types.ts"), "utf8");
const codice = pagina.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

describe("/profilo/[id]/cantina", () => {
  it("valida il profilo con la stessa porta pubblica prima di leggere la Cantina", () => {
    const profilo = pagina.indexOf("await service.profilo(id)");
    const controllo = pagina.indexOf("if (!esitoProfilo.data) notFound()");
    const cantina = pagina.indexOf("await service.cantinaPubblica(id, finestraCollezione(pagina))");

    expect(profilo).toBeGreaterThan(-1);
    expect(controllo).toBeGreaterThan(profilo);
    expect(cantina).toBeGreaterThan(controllo);
    expect(pagina).toInclude("creaPublicProfileService(client)");
    expect(pagina.match(/creaPublicProfileService\(/g)).toHaveLength(1);
  });

  it("resta fail-closed per un profilo assente o non raggiungibile", () => {
    expect(pagina).toInclude("if (!esitoProfilo.ok) return <ProfiloNonDisponibile />");
    expect(pagina).toInclude("if (!esitoProfilo.data) notFound()");
    expect(pagina).toInclude("Profilo non disponibile");
    expect(nonTrovato).toInclude("Profilo non disponibile");
    expect(codice).not.toMatch(/sospes|modera|inesistente|esitoProfilo\.error/i);
  });

  it("pagina la sola porta Cantina pubblica senza un conteggio separato", () => {
    expect(pagina).toInclude("finestraCollezione(pagina)");
    expect(pagina).toInclude("paginaDiBottiglie(esitoCantina.data)");
    expect(pagina).toInclude("altraPagina={collezione.altraPagina}");
    expect(codice).not.toMatch(/count\(|conteggio\w*\(|\.from\(/i);
  });

  it("compone una testata minima con identità pubblica e ritorno al profilo", () => {
    expect(pagina).toInclude("<AvatarPersona");
    expect(pagina).toInclude("profilo.avatarUrl");
    expect(pagina).toInclude("profilo.username");
    expect(pagina).toInclude("profilo.citta");
    expect(pagina).toInclude("profilo.provincia");
    expect(pagina).toInclude("La cantina di {username}");
    expect(pagina).toInclude("Torna al profilo");
    expect(pagina).toInclude("indirizzoProfiloPubblico(userId)");
  });

  it("il proprietario attraversa la stessa route pubblica e riceve solo un link di gestione", () => {
    expect(pagina).toInclude("utente?.id === profilo.userId");
    expect(pagina).toInclude("profiloProprio={profiloProprio}");
    expect(pagina).toInclude("{profiloProprio && (");
    expect(pagina).toInclude("Gestisci la mia cantina");
    expect(pagina).toInclude("href={routes.cantina}");
    expect(pagina.match(/service\.cantinaPubblica\(/g)).toHaveLength(1);
  });

  it("non legge dati o strutture della Cantina privata", () => {
    expect(codice).not.toMatch(
      /CellarService|createCellarService|useCellar|bottle_units|cellar_environments|cellar_modules|cellar_slots|Cellar3D/,
    );
    expect(codice).not.toMatch(
      /note_personali|apertura_pianificata|degustazione_nota|degustazione_at|acquisition|prezzo_visibilita|signedUrl|cantina bucket/i,
    );
    for (const campo of ["notePersonali", "costoAcquisto", "posizione", "ambiente", "modulo", "slot"]) {
      expect(contratti).not.toMatch(new RegExp(`BottigliaCantinaPubblica[\\s\\S]{0,500}${campo}`, "i"));
    }
  });

  it("ha una superficie di caricamento responsiva senza dipendenze client", () => {
    expect(caricamento).toInclude('aria-busy="true"');
    expect(caricamento).toInclude('aria-label="Caricamento Cantina pubblica"');
    expect(caricamento).toInclude("grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3");
    expect(caricamento).not.toInclude('"use client"');
    expect(caricamento).not.toMatch(/min-w-\[|w-\[\d|overflow-x/);
  });
});

// ===========================================================================
// Il valore di riferimento nella Cantina pubblica
//
// Una lettura in più sulla stessa route, e volutamente la più fragile delle
// tre: può mancare, può fallire, può essere stata disattivata, e in nessuno di
// quei casi deve portarsi via la collezione. Le prove qui sotto guardano
// l'ordine delle letture, la porta chiusa quando manca il consenso, e il
// confine con la contabilità privata del proprietario.
// ===========================================================================

describe("/profilo/[id]/cantina — valore di riferimento", () => {
  const componente = readFileSync(
    join(progetto, "src/components/vinea/profilo/ValoreCantinaPubblica.tsx"),
    "utf8",
  );
  const codiceComponente = componente
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");
  const adattatore = readFileSync(join(progetto, "src/lib/cantina/valore-pubblico.ts"), "utf8");
  // Senza commenti: la prosa dell'adattatore nomina apposta il `?? 0` che non
  // usa, e un divieto non va cercato nella spiegazione del divieto.
  const codiceAdattatore = adattatore
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

  it("[1] il profilo è validato prima che il valore venga atteso", () => {
    // La porta che decide se quella persona è raggiungibile resta la prima:
    // il valore non deduce l'esistenza di un profilo, e non parte prima del
    // `notFound()`.
    const controllo = codice.indexOf("if (!esitoProfilo.data) notFound()");
    const partenza = codice.indexOf("service.valoreCantinaPubblica(id)");
    const attesa = codice.indexOf("await promessaValore");

    expect(controllo).toBeGreaterThan(-1);
    expect(partenza).toBeGreaterThan(controllo);
    expect(attesa).toBeGreaterThan(partenza);
  });

  it("[2] preferenza spenta: il blocco non esiste, nemmeno come segnaposto", () => {
    // `visibile` in forma positiva è tutta la condizione. Non c'è un ramo che
    // disegni «valore nascosto»: sarebbe un oracolo su una scelta privata.
    expect(codice).toInclude("esitoValore.ok && esitoValore.data.visibile ? esitoValore.data : null");
    expect(codice).toInclude("{valore && <ValoreCantinaPubblica valore={valore} />}");
    expect(codice).not.toMatch(/valore nascosto|ha scelto di non|non ha attivato|disattivat/i);
  });

  it("[3] preferenza accesa: il blocco compare fra la testata e la collezione", () => {
    const testata = codice.indexOf("<IntestazioneCantina", codice.indexOf("return ("));
    const valore = codice.indexOf("<ValoreCantinaPubblica valore={valore} />");
    const collezione = codice.indexOf("<CollezionePubblica");

    expect(testata).toBeGreaterThan(-1);
    expect(valore).toBeGreaterThan(testata);
    expect(collezione).toBeGreaterThan(valore);
  });

  it("[4] un guasto del valore lascia in piedi la collezione", () => {
    // Due prove in una: l'esito si legge con `.ok` e non si propaga, e la
    // lettura non è dentro un `Promise.all`, dove un rifiuto porterebbe via
    // anche le bottiglie.
    expect(codice).toInclude("esitoValore.ok &&");
    expect(codice).not.toMatch(/Promise\.all\(\[[\s\S]{0,200}valoreCantinaPubblica/);
    expect(codice).not.toMatch(/if \(!esitoValore\.ok\)[\s\S]{0,120}(notFound|ProfiloNonDisponibile|Cantina non disponibile)/);
    // Il ramo «Cantina non disponibile» dipende solo dalla collezione.
    expect(codice).toInclude("if (!esitoCantina.ok) {");
    expect(codice).toMatch(/const collezione = paginaDiBottiglie\(esitoCantina\.data\);[\s\S]{0,200}await promessaValore/);
  });

  it("[5] valore non misurato: nessun € 0,00 disegnato al suo posto", () => {
    expect(codiceComponente).toInclude("v.valore === null ?");
    expect(codiceComponente).toInclude("Valore di riferimento non ancora disponibile");
    // L'adattatore non colma il buco con uno zero, né nel totale né nella serie.
    expect(codiceAdattatore).not.toMatch(/\?\?\s*0\b/);
    expect(codiceAdattatore).not.toMatch(/valoreCents\s*\|\|\s*0/);
    expect(codiceAdattatore).toInclude("p.valoreCents === null");
  });

  it("[6] un valore noto passa dal formattatore monetario esistente", () => {
    expect(adattatore).toInclude('import { euro } from "@/lib/cantina/presentazione"');
    expect(adattatore).toInclude("euro(v.valoreRiferimentoCents)");
    // Nessuna divisione per cento scritta a mano nel componente.
    expect(codiceComponente).not.toMatch(/\/\s*100/);
  });

  it("[7] la copertura parziale è dichiarata, e dice che le altre non sono zero", () => {
    expect(codiceComponente).toInclude("{v.parziale && (");
    expect(codiceComponente).toInclude("non sono contate come");
    expect(adattatore).toInclude('v.copertura === "parziale"');
    expect(adattatore).toInclude("non contano come zero");
  });

  it("[8] serie vuota: il grafico lo dice da sé, con copia neutra", () => {
    const grafico = readFileSync(join(progetto, "src/components/vinea/ValoreNelTempo.tsx"), "utf8");
    expect(grafico).toInclude("le bottiglie di questa Cantina");
    // «le tue bottiglie» in una Cantina di qualcun altro sarebbe falso.
    expect(grafico).not.toInclude("per le tue bottiglie");
    expect(grafico).toInclude('stato === "vuota"');
  });

  it("[9] una sola osservazione non diventa una linea", () => {
    const grafico = readFileSync(join(progetto, "src/components/vinea/ValoreNelTempo.tsx"), "utf8");
    expect(grafico).toInclude('stato === "osservazione_unica"');
    // Il componente pubblico non reimplementa niente di tutto questo.
    expect(codiceComponente).toInclude("<ValoreNelTempo serie={v.serie}");
    expect(codiceComponente).not.toInclude("svg");
    expect(codiceComponente).not.toInclude("path");
  });

  it("[10] più osservazioni passano dallo stesso grafico della Cantina privata", () => {
    expect(codiceComponente).toInclude('from "@/components/vinea/ValoreNelTempo"');
    expect(codiceComponente).toInclude("incorniciato={false}");
    // Un solo blocco, non una copia del grafico dentro il componente pubblico.
    expect(codiceComponente.split("<ValoreNelTempo").length - 1).toBe(1);
  });

  it("[11] nessun campo della contabilità del proprietario arriva qui", () => {
    for (const vietato of [
      "capitaleNotoCents",
      "incassiTrasferitiCents",
      "performanceCents",
      "performancePercentuale",
      "posizioniConCosto",
      "acquisition",
      "costoAcquisto",
      "prezzoAcquisto",
      "AnaliticaPortafoglio",
      "cellar_portfolio_analitica",
    ]) {
      expect(codiceComponente).not.toInclude(vietato);
      expect(codice).not.toInclude(vietato);
    }

    // Parole intere per i termini che vivono anche dentro altre: `order` sta in
    // `border`, e cercarlo come sottostringa vieterebbe una classe CSS.
    for (const vietato of [
      /\bcapitale\b/i,
      /\border(s|_id|Id)?\b/i,
      /\bpayments?\b/i,
      /\bpayouts?\b/i,
      /\bcosto d['’]acquisto\b/i,
      /\bprezzo d['’]acquisto\b/i,
    ]) {
      expect(codiceComponente).not.toMatch(vietato);
      expect(codice).not.toMatch(vietato);
    }
    // E il contratto pubblico non è derivato da quello privato: nessun
    // `Omit`/`Pick` che erediterebbe un campo aggiunto domani.
    expect(contratti).toMatch(/export type ValoreCantinaPubblica = \{/);
    expect(contratti).not.toMatch(/ValoreCantinaPubblica[^\n]*(Omit|Pick)</);
  });

  it("[12] la griglia e l'elenco della collezione non cambiano", () => {
    expect(codice).toInclude("<CollezionePubblica");
    expect(codice).toInclude("bottiglie={collezione.bottiglie}");
    expect(codice).toInclude("vista={vista}");
    expect(codice).toInclude("vistaCollezione(query.vista)");
    // Un solo punto di resa della collezione: il valore è stato aggiunto
    // accanto, non intorno.
    expect(codice.split("<CollezionePubblica").length - 1).toBe(1);
  });

  it("[13] la paginazione resta quella di prima", () => {
    expect(codice).toInclude("paginaCollezione(query.pagina)");
    expect(codice).toInclude("finestraCollezione(pagina)");
    expect(codice).toInclude("altraPagina={collezione.altraPagina}");
    expect(codice).toInclude("pagina={pagina}");
    // Il valore non è paginato e non prende la pagina: è un aggregato della
    // collezione esposta, non della sua finestra corrente.
    expect(codice).not.toMatch(/valoreCantinaPubblica\(id,/);
  });

  it("[14] nessuna sorgente economica diversa dalla porta pubblica", () => {
    for (const vietato of [
      "bottle_units",
      "wine_reference_snapshots",
      "cellar_public_settings",
      ".from(",
      ".rpc(",
    ]) {
      expect(codice).not.toInclude(vietato);
      expect(codiceComponente).not.toInclude(vietato);
    }
    expect(codice).toInclude("service.valoreCantinaPubblica(id)");
    expect(codice.match(/service\.valoreCantinaPubblica\(/g)).toHaveLength(1);
  });

  it("[15] niente marketplace e niente 3D nel blocco valore", () => {
    for (const vietato of [
      "Cellar3D",
      "canvas",
      "Canvas",
      "three",
      "carrello",
      "Carrello",
      "aggiungiAlCarrello",
      "checkout",
      "Acquista",
      "segui",
      "Segui",
      "notifica",
    ]) {
      expect(codiceComponente).not.toInclude(vietato);
    }
    // Il componente è reso dal server: nessuna idratazione per un blocco di
    // sola lettura.
    expect(componente).not.toInclude('"use client"');
  });
});

// ===========================================================================
// Il comando «Segui» nella testata
//
// Il repository non monta componenti React nei test: le transizioni di stato
// sono verificate come funzioni pure in
// `src/lib/cantina/segui-cantina-stato.test.ts`, e le quattro porte in
// `src/services/cellar-follow-service.test.ts`. Qui si verifica ciò che resta e
// che nessuno dei due copre: quali dati la pagina consegna al comando, che il
// proprietario non lo riceva, che l'anonimo non chiami il database, e che il
// componente usi davvero quelle funzioni invece di riscriverne la logica.
// ===========================================================================

describe("/profilo/[id]/cantina — segui la Cantina", () => {
  const bottone = readFileSync(
    join(progetto, "src/components/vinea/profilo/SeguiCantinaButton.tsx"),
    "utf8",
  );
  const codiceBottone = bottone
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");
  const statoFollow = readFileSync(join(progetto, "src/lib/cantina/segui-cantina-stato.ts"), "utf8");
  // Senza commenti: la prosa nomina apposta ciò che il modulo non fa — «il
  // follower non compare mai qui» — e un divieto non va cercato nella frase che
  // lo dichiara.
  const codiceStatoFollow = statoFollow
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

  it("[1] la testata riceve il comando con l'identificativo pubblico e nient'altro", () => {
    expect(codice).toInclude("<SeguiCantinaButton ownerId={userId} profiloProprio={profiloProprio} />");
    // Un solo punto di resa, dentro la testata, e non uno per ramo di errore.
    expect(codice.split("<SeguiCantinaButton").length - 1).toBe(1);
    expect(codice).toInclude('from "@/components/vinea/profilo/SeguiCantinaButton"');
  });

  it("[2] nessun dato privato attraversa il confine verso il comando", () => {
    // `profiloProprio` è un booleano già calcolato dal server; l'identificativo
    // è nell'URL. Tutto il resto resterebbe dalla parte del server per niente.
    const resa = codice.slice(codice.indexOf("<SeguiCantinaButton"));
    const attributi = resa.slice(0, resa.indexOf("/>"));
    expect(attributi).not.toMatch(/email|utente|token|session|ruolo|valore|moderazione/i);
    expect(codiceBottone).not.toMatch(/email|moderazione|valore_cents|costoAcquisto/i);
  });

  it("[3] il proprietario non vede alcun comando di follow", () => {
    // La decisione sta in un posto solo — dentro il componente — e non in un
    // secondo `profiloProprio &&` nella pagina che potrebbe divergere.
    expect(codiceBottone).toInclude("if (profiloProprio) return null;");
    // E non è un comando disabilitato con una spiegazione: quella frase
    // racconterebbe il rifiuto `P0001` a chi non ha premuto niente.
    expect(codiceBottone).not.toMatch(/non puoi seguire la tua/i);
    // Il proprietario non produce un'identità destinataria; senza identità
    // l'effetto invalida il ref e termina prima di costruire il servizio.
    expect(codiceBottone).toInclude("!profiloProprio && authUser");
    const senzaIdentita = codiceBottone.slice(codiceBottone.indexOf("if (!identitaCorrente) {"));
    const primaDellaRpc = senzaIdentita.slice(0, senzaIdentita.indexOf("const token"));
    expect(primaDellaRpc).toInclude("lettoreRef.current = null;");
    expect(primaDellaRpc).not.toInclude("creaCellarFollowService");
  });

  it("[4] l'anonimo vede l'invito ma non chiama il database", () => {
    const anonimo = codiceBottone.slice(codiceBottone.indexOf("if (!authUser) {"));
    const finoAlRitorno = anonimo.slice(0, anonimo.indexOf("</Link>"));
    expect(finoAlRitorno).toInclude("<Link");
    expect(finoAlRitorno).not.toMatch(/creaCellarFollowService|\.stato\(|\.segui\(|onClick/);
    // Le tre porte richiedono `authenticated`: una chiamata da anonimo
    // produrrebbe `42501`, cioè un errore mostrato a chi non ha sbagliato nulla.
    expect(codiceBottone).toInclude("PARAMETRO_NEXT");
    expect(codiceBottone).toInclude('from "@/lib/auth/ritorno-auth"');
    expect(codiceBottone).toInclude("encodeURIComponent(routes.cantinaPubblica(ownerId))");
    // Nessun sistema di ritorno inventato accanto a quello esistente.
    expect(codiceBottone).not.toMatch(/\?returnTo=|\?redirect=|localStorage|sessionStorage/);
  });

  it("[5] finché la sessione non è nota non mostra né l'invito né il comando", () => {
    const attesa = codiceBottone.indexOf("if (authLoading) {");
    const anonimo = codiceBottone.indexOf("if (!authUser) {");
    expect(attesa).toBeGreaterThan(-1);
    expect(anonimo).toBeGreaterThan(attesa);
    expect(codiceBottone).toInclude('aria-busy="true"');
  });

  it("[6] usa davvero le transizioni pure, invece di riscriverle", () => {
    for (const funzione of [
      "statoDaEsitoIniziale(esito)",
      "statoInMutazione(stato)",
      "statoDaEsitoMutazione(precedente.stato, esito)",
      "azioneFollow(stato)",
      "etichettaFollow(stato)",
      "descrizioneFollow(stato)",
      "followAbilitato(stato)",
      "followOccupato(stato)",
    ]) {
      expect(codiceBottone).toInclude(funzione);
    }
    expect(codiceBottone).toInclude('from "@/lib/cantina/segui-cantina-stato"');
  });

  it("[7] nessun successo anticipato: lo stato si muove dopo la risposta", () => {
    // Il difetto che questa prova impedisce: uno stato «seguita» scritto accanto
    // alla chiamata, prima del `then`.
    const primaDellaRisposta = codiceBottone.slice(
      codiceBottone.indexOf('void (azione === "segui"'),
      codiceBottone.indexOf(".then((esito) =>"),
    );
    expect(primaDellaRisposta).not.toMatch(/fase:\s*"(?:seguita|non_seguita)"/);
    // Il feedback racconta quello che ha detto il database, non il click.
    expect(codiceBottone).toInclude("esito.data");
    expect(codiceBottone).toInclude("? TOAST_SEGUITA");
    expect(codiceBottone).toInclude(": TOAST_NON_SEGUITA");
    // La lettura iniziale che fallisce non diventa `false`: vive nella funzione
    // pura, ed è là che si verifica.
    expect(statoFollow).toInclude('if (!esito.ok) return { fase: "non_disponibile" };');
  });

  it("[8] un cambio di sessione non lascia stato o feedback del visitatore precedente", () => {
    // La risposta in volo appartiene a chi l'ha chiesta: al ritorno si confronta
    // il token, come in `real-auth-domain.ts`.
    expect(codiceBottone).toInclude("lettoreRef");
    expect(codiceBottone).toInclude("if (annullato || lettoreRef.current !== token) return;");
    expect(codiceBottone).toInclude("if (lettoreRef.current !== token) return;");
    // Il cleanup invalida anche una mutazione, non soltanto la lettura iniziale.
    expect(codiceBottone).toInclude(
      "if (lettoreRef.current === token) lettoreRef.current = null;",
    );
    // Lo stato visibile è derivato dall'identità già durante il render: non deve
    // aspettare il cleanup passivo dopo un cambio sessione/Cantina.
    expect(codiceBottone).toInclude("stessaIdentitaFollow(statoLetto?.identita ?? null, identitaCorrente)");
    expect(codiceBottone).toInclude("? statoLetto!.stato");
    expect(codiceBottone).toInclude(": STATO_INIZIALE");
    expect(codiceBottone).toInclude("sessione: authUser");
    // Anche il toast è mediato da stato identitario e ricontrollato nell'effetto;
    // il callback tardivo non lo emette direttamente.
    expect(codiceBottone).toInclude("stessaIdentitaFollow(feedback.identita, identitaCorrente)");
    const callback = codiceBottone.slice(codiceBottone.indexOf(".then((esito) =>"));
    expect(callback.slice(0, callback.indexOf("}, [identitaCorrente"))).not.toMatch(/toast\./);
  });

  it("[9] è un vero `button`, con nome accessibile e stato non affidato al colore", () => {
    expect(codiceBottone).toInclude('<button');
    expect(codiceBottone).toInclude('type="button"');
    expect(codiceBottone).toInclude("aria-label={descrizioneFollow(stato)}");
    expect(codiceBottone).toInclude("disabled={!followAbilitato(stato)}");
    expect(codiceBottone).toInclude("aria-busy={followOccupato(stato)}");
    // L'etichetta è una parola in ogni fase: chi non distingue il bordo legge.
    expect(codiceBottone).toInclude("{etichettaFollow(stato)}");
    // Le icone accompagnano il testo e non lo sostituiscono.
    expect(codiceBottone).toMatch(/<Check className="h-4 w-4" aria-hidden \/>/);
  });

  it("[10] l'errore di scrittura arriva mediato, senza dettaglio tecnico", () => {
    expect(codiceBottone).toInclude(": esito.error");
    expect(codiceBottone).toInclude('tipo: esito.ok ? "successo" : "errore"');
    expect(codiceBottone).toInclude("toast.error(feedback.messaggio)");
    expect(codiceBottone).not.toMatch(/error\.(code|message|details|hint)/);
    expect(codiceBottone).not.toMatch(/42501|P0001|22023|22004/);
  });

  it("[11] non tocca il database se non attraverso il servizio dedicato", () => {
    expect(codiceBottone).toInclude("creaCellarFollowService(getSupabaseClient())");
    expect(codiceBottone).not.toMatch(/\.from\(|\.rpc\(|cellar_follows|follower/i);
    // E non passa da un altro dominio: il follow non sta in PublicProfileService.
    expect(codiceBottone).not.toMatch(/creaPublicProfileService|creaProfileService|CellarService/);
  });

  it("[12] non aggiunge il dominio allo store globale", () => {
    const store = readFileSync(join(progetto, "src/lib/vinea-store.tsx"), "utf8");
    expect(store).not.toMatch(/follow|segui/i);
    // Lo stato è locale al comando: una Cantina seguita non è un fatto dell'app.
    expect(codiceBottone).toInclude("useState<StatoPerIdentita | null>(null)");
  });

  it("[13] nessun conteggio di follower, in nessuna direzione", () => {
    for (const vietato of [
      /follower/i,
      /\bseguaci\b/i,
      /quante?\s+persone/i,
      /\bconteggio\b/i,
      /count\(/i,
    ]) {
      expect(codiceBottone).not.toMatch(vietato);
      expect(codiceStatoFollow).not.toMatch(vietato);
    }
  });

  it("[14] il comando non porta con sé marketplace, 3D o notifiche nuove", () => {
    for (const vietato of [
      "Cellar3D",
      "carrello",
      "checkout",
      "Acquista",
      "Realtime",
      "channel(",
      "push",
      "email",
    ]) {
      expect(codiceBottone).not.toInclude(vietato);
    }
  });
});
