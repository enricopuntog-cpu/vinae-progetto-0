/** Testi originali per la beta Next.js.
 * Non trasformare la bozza in informativa definitiva senza completare il titolare
 * e la verifica di conservazione e contratti dei fornitori. Nessuna società inventata.
 */
export const versioneLegale = "18 settembre 2026";
export const identitaLegale = { nome: "", indirizzo: "", email: "" };
export const statoLegale = "bozza" as const;

export type CapitoloLegale = { titolo: string; paragrafi: readonly string[] };

export const privacy: readonly CapitoloLegale[] = [
  {
    titolo: "1. A chi si rivolge questa informativa",
    paragrafi: [
      "Questa informativa descrive il trattamento dei dati personali nella beta Vinea Wine Club: navigazione, account, cantina personale, annunci e community. Riguarda anche le persone i cui dati vengono inseriti in contenuti, richieste o segnalazioni da altri utenti. Il titolare e i recapiti per esercitare i diritti sono indicati nella scheda Contatti del Centro legale.",
      "Vinea è riservato a persone di almeno 18 anni. La data di nascita è dichiarata dall’utente; il controllo di maggiore età non costituisce verifica documentale dell’identità. Non inserire dati di minori o dati personali di terzi non necessari al servizio.",
    ],
  },
  {
    titolo: "2. Dati raccolti e loro provenienza",
    paragrafi: [
      "Navigazione e sicurezza: indirizzo IP, data e ora, risorsa richiesta, informazioni sul browser e sul dispositivo, esito delle richieste e informazioni di sessione possono essere trattati dall’infrastruttura che eroga e protegge il sito. I cookie e le altre memorie del dispositivo sono descritti nell’informativa cookie.",
      "Account: email, identificativo utente, nome utente, data di nascita, credenziali gestite dal servizio di autenticazione, conferma dell’email e informazioni sugli accessi. Se scegli Google, il servizio di autenticazione riceve i dati autorizzati nel flusso Google, come identificativo dell’account, email, nome e immagine del profilo. Vinea non riceve la password del tuo account Google.",
      "Profilo: biografia, città, provincia, esperienza dichiarata, avatar e stati di qualifica o abilitazione pertinenti. I dati facoltativi possono essere omessi; i campi richiesti sono indicati nei moduli. L’email e la data di nascita non fanno parte del profilo pubblico.",
      "Cantina: bottiglie possedute, immagini, stato, note personali e di degustazione, date di acquisizione, apertura o consumo, fonte e costo di acquisto, preferenze, finestre di consumo personalizzate, visibilità e organizzazione degli ambienti, moduli e posizioni della cantina.",
      "Annunci e interazioni: bottiglia, prezzo, fotografie, condizione, conservazione, storia, tag, stato dell’annuncio, proposte e controproposte; contenuto dei messaggi, partecipanti, date e stato di lettura; notifiche e stato di consultazione. Nei club: iscrizioni e ruoli, post, risposte, apprezzamenti, riferimenti a bottiglie o annunci e immagini di copertina.",
      "Percorso checkout beta: i moduli possono chiedere email, telefono, destinatario, via, CAP, città e provincia, oltre alle preferenze di consegna, imballaggio e pagamento. Nella versione descritta questi campi sono elaborati nello stato temporaneo della pagina per provare il flusso: telefono e indirizzo non vengono inviati al servizio di checkout né al corriere. Per le prove usa dati fittizi. I moduli non chiedono il numero della carta o il suo codice di sicurezza.",
      "Qualifiche professionali: titolo, ente emittente, Paese, riferimento della credenziale, date di rilascio e scadenza, documenti caricati, stato e date della richiesta e della verifica. Non inviare documenti d’identità al posto del titolo professionale; oscura informazioni non necessarie. L’informativa specifica Documenti di qualifica descrive anche cosa diventa pubblico.",
      "Assistenza e moderazione: motivo e descrizione della richiesta o segnalazione, contenuti e fotografie allegati, riferimenti a utenti o contenuti segnalati, risposte, provvedimenti e registrazioni delle azioni di moderazione. I dati possono provenire dall’interessato, da altri utenti, da moderatori e dai servizi tecnici utilizzati.",
    ],
  },
  {
    titolo: "3. Finalità e basi giuridiche",
    paragrafi: [
      "Creare e gestire l’account, autenticarti, rendere disponibile la cantina, pubblicare ciò che richiedi, permettere messaggi e partecipazione ai club e gestire le relative richieste: esecuzione del servizio richiesto e delle misure precontrattuali, articolo 6, paragrafo 1, lettera b), GDPR. Senza i dati indispensabili non possiamo eseguire la funzione interessata; puoi comunque consultare le pagine pubbliche che non richiedono un account.",
      "Esaminare una qualifica professionale su tua richiesta e mostrarne l’esito consentito: esecuzione del servizio richiesto, articolo 6, paragrafo 1, lettera b). Il caricamento è facoltativo e necessario soltanto per richiedere quel riconoscimento.",
      "Proteggere account e infrastruttura, prevenire frodi e abusi, moderare contenuti e gestire contestazioni: legittimo interesse alla sicurezza del servizio, alla tutela degli utenti e alla difesa dei diritti, articolo 6, paragrafo 1, lettera f), nei limiti della necessità e del bilanciamento con i tuoi diritti. Puoi opporti per motivi connessi alla tua situazione particolare.",
      "Adempiere obblighi di legge o richieste vincolanti di autorità competenti: articolo 6, paragrafo 1, lettera c), limitatamente all’obbligo concretamente applicabile. Non tutti i dati dell’account sono per questo conservati come documenti fiscali.",
      "L’accettazione dei termini è distinta dalla presa visione di questa informativa: non costituisce un consenso generale al trattamento, al marketing o alla profilazione. La beta non offre un’iscrizione a newsletter promozionali né un consenso pubblicitario. Eventuali future finalità facoltative che richiedano consenso avranno una scelta separata e revocabile.",
    ],
  },
  {
    titolo: "4. Cosa vedono gli altri utenti",
    paragrafi: [
      "Nome utente, avatar e informazioni rese pubbliche nel profilo, annunci e relative immagini, contenuti della community e qualifiche approvate e non scadute possono essere consultabili da altri utenti e visitatori secondo la visibilità della funzione. Un contenuto pubblico può essere copiato o conservato da chi lo consulta: valuta cosa inserire prima di pubblicare.",
      "Le note personali e i costi privati della cantina non diventano pubblici per il solo fatto di pubblicare una bottiglia. I documenti e il riferimento privato della qualifica non sono pubblicati. Le immagini degli annunci, gli avatar e le copertine dei club sono ospitati in archivi pubblici; immagini della cantina e documenti professionali sono in archivi privati con accesso controllato.",
      "I messaggi sono destinati ai partecipanti. Il contenuto segnalato e il contesto necessario possono essere esaminati dai soggetti autorizzati alla moderazione per gestire abusi e segnalazioni. Non descriviamo la messaggistica come un servizio con cifratura end-to-end.",
    ],
  },
  {
    titolo: "5. Fornitori, destinatari e trasferimenti",
    paragrafi: [
      "Netlify eroga l’hosting e la distribuzione delle pagine. Supabase fornisce database, autenticazione, archiviazione dei file e funzioni del servizio. Il database della beta è collocato nella regione europea eu-west-1, in Irlanda. L’accesso operativo ai dati è riservato alle persone autorizzate nei limiti del ruolo e della necessità.",
      "Resend è il servizio SMTP usato da Supabase per inviare le email di autenticazione, conferma e recupero dell’account. Riceve l’indirizzo del destinatario e il contenuto necessario alla consegna del messaggio. Non è usato nella beta per newsletter promozionali.",
      "Google interviene quando scegli l’accesso con Google. Inoltre le pagine caricano Google Fonts per la tipografia: il browser contatta i domini Google dei caratteri e comunica i dati tecnici necessari alla richiesta. Eventuali immagini ospitate su domini esterni, inclusi avatar forniti dal provider di accesso o immagini dimostrative, comportano richieste al relativo gestore quando visualizzate.",
      "Le informazioni strettamente necessarie possono essere comunicate a consulenti che assistono il titolare, soggetti autorizzati alla manutenzione e autorità quando richiesto dalla legge. I fornitori che operano per conto del titolare devono essere disciplinati da accordi sul trattamento; per le proprie finalità i servizi esterni operano secondo le rispettive informative.",
      "La regione europea del database non implica che ogni operazione di supporto, rete o subfornitura avvenga soltanto nello Spazio economico europeo. Gli eventuali trasferimenti richiedono una base del capo V GDPR, come una decisione di adeguatezza applicabile al destinatario o clausole contrattuali standard e le misure necessarie. Il titolare deve completare la verifica dei contratti, dei destinatari e delle garanzie effettivamente applicate prima della versione definitiva di questo testo; non viene attestata qui una verifica già conclusa.",
    ],
  },
  {
    titolo: "6. Conservazione e cancellazione",
    paragrafi: [
      "I criteri di conservazione dipendono dalla finalità: dati dell’account e della cantina per il periodo necessario a fornire il servizio richiesto; contenuti pubblicati per la durata della pubblicazione; richieste di assistenza e segnalazioni per la loro gestione e per il tempo necessario a eventuali contestazioni; prove soggette a obblighi di legge per il periodo previsto dall’obbligo applicabile. Al venir meno della necessità, i dati devono essere cancellati o resi anonimi, salvo conservazioni specifiche giustificate.",
      "La rimozione dalla schermata non coincide sempre con la cancellazione fisica: alcuni contenuti vengono nascosti o marcati come rimossi per gestire lo stato del servizio e le contestazioni. Il ritiro di una qualifica inviata non cancella automaticamente i documenti; l’eliminazione di una bozza di qualifica include invece la rimozione dei suoi allegati dall’archivio privato.",
      "Nella beta non sono ancora definiti e verificati tutti i termini operativi per log, backup, messaggi, documenti di qualifica e registri di moderazione. Non è quindi promessa una cancellazione automatica entro un numero di giorni non implementato. Il completamento di questo calendario e della procedura di cancellazione è un requisito aperto per la versione definitiva dell’informativa.",
      "Puoi chiedere la cancellazione o la limitazione al contatto privacy indicato nella scheda del titolare, senza dover motivare una richiesta di accesso ai tuoi dati. Per i dati necessari a una controversia o a un obbligo applicabile deve essere indicato il motivo dell’eventuale conservazione ulteriore. La cancellazione dei dati del browser non cancella l’account o gli archivi del servizio.",
    ],
  },
  {
    titolo: "7. Funzioni non ancora attive",
    paragrafi: [
      "Pagamenti, accrediti e prenotazione delle spedizioni non sono attivi nella beta descritta. Il sistema contiene strutture per ordini, importi, identificativi del prestatore di pagamento, movimenti, tracking, recensioni e contestazioni: la loro presenza tecnica non significa che stiamo già raccogliendo numeri di carta, IBAN o indirizzi di spedizione attraverso un acquisto operativo. Prima dell’attivazione saranno indicati i dati richiesti e i partner effettivi.",
      "Le chiamate ai provider di intelligenza artificiale sono disattivate. La memoria locale del Sommelier è descritta nell’informativa cookie. Eventi regionali, promozioni a pagamento, ispezioni fisiche delle bottiglie e accessori da collezione sono sviluppi previsti: questo testo non li presenta come trattamenti già avviati. Un aggiornamento specifico precederà l’eventuale nuova raccolta.",
      "Nella beta descritta non vengono adottate decisioni basate unicamente su trattamenti automatizzati che producano effetti giuridici o analogamente significativi sulla persona. Il controllo della data di nascita verifica il requisito dichiarato di età; non determina una valutazione economica o un punteggio personale.",
    ],
  },
  {
    titolo: "8. I tuoi diritti e gli aggiornamenti",
    paragrafi: [
      "Nei casi previsti dagli articoli 15–22 GDPR puoi chiedere accesso e copia, rettifica, cancellazione, limitazione e portabilità dei dati, e opporti al trattamento fondato sul legittimo interesse. Se un trattamento si basa sul consenso, puoi revocarlo senza pregiudicare la liceità del trattamento precedente. I diritti hanno condizioni e limiti previsti dalla normativa.",
      "Invia la richiesta al contatto privacy del titolare, specificando quanto serve a identificarla. Per proteggere i dati possono essere richieste informazioni proporzionate per verificare l’identità, senza pretendere automaticamente un documento. Il termine ordinario di risposta previsto dal GDPR è un mese; l’eventuale proroga nei casi consentiti deve essere motivata e comunicata entro quel termine.",
      "Puoi proporre reclamo al Garante per la protezione dei dati personali, www.garanteprivacy.it, o all’autorità competente del luogo in cui risiedi o lavori abitualmente o in cui ritieni si sia verificata la violazione. Resta possibile la tutela giudiziaria.",
      "La data della versione è indicata all’inizio della pagina. Le modifiche sostanziali devono essere rese conoscibili prima dei nuovi trattamenti; un eventuale cambio di titolare o di finalità non è autorizzato dalla sola presenza di questa clausola.",
    ],
  },
];

export const termini: readonly CapitoloLegale[] = [
  {
    titolo: "1. Servizio e fase beta",
    paragrafi: [
      "Vinea Wine Club permette a maggiorenni di organizzare la propria cantina, consultare e pubblicare annunci di vino e partecipare alla community. Questi termini regolano l’uso della beta e dei suoi contenuti. Il gestore del servizio coincide con il soggetto indicato nella scheda Contatti del Centro legale.",
      "La beta è in sviluppo e può presentare funzioni non disponibili o contenuti dimostrativi esplicitamente identificati. Pagamenti, accrediti e prenotazione delle spedizioni non sono attivi: non inviare denaro o bottiglie per provare un percorso dimostrativo. Questi termini non attivano un servizio di acquisto, deposito di fondi o trasporto.",
    ],
  },
  {
    titolo: "2. Account e maggiore età",
    paragrafi: [
      "Per creare un account devi avere almeno 18 anni, fornire informazioni corrette e disporre legittimamente dell’indirizzo email e delle credenziali usate. Proteggi la password e segnala tempestivamente accessi non autorizzati. Non impersonare altre persone, condividere credenziali altrui o aggirare le limitazioni dell’account.",
      "La data di nascita è una dichiarazione dell’utente. Un’email confermata, una qualifica professionale approvata o uno stato relativo ai pagamenti indicano verifiche diverse e non equivalgono a una garanzia generale sull’identità o sull’affidabilità commerciale della persona.",
    ],
  },
  {
    titolo: "3. Annunci e contenuti",
    paragrafi: [
      "Pubblica soltanto contenuti che hai diritto di utilizzare e descrizioni veritiere. Per le bottiglie indica correttamente caratteristiche, condizioni, conservazione e difetti conosciuti; non presentare come accertata una provenienza o autenticità che non puoi sostenere. Sono vietati prodotti contraffatti, contenuti illeciti, truffe e offerte rivolte a minorenni.",
      "Il perimetro attuale degli annunci è il vino. Accessori, bottiglie vuote da collezione, promozioni a pagamento e verifiche fisiche sono sviluppi futuri. Non utilizzare categorie o funzioni esistenti per simulare servizi non disponibili.",
      "Mantieni i diritti sui contenuti caricati. Consenti a Vinea di ospitarli, riprodurli tecnicamente e mostrarli nella misura necessaria al servizio e alla visibilità scelta, per la durata necessaria a tali finalità. Questa autorizzazione non trasferisce la proprietà dei contenuti e non è un’autorizzazione generale a usarli in campagne pubblicitarie esterne.",
    ],
  },
  {
    titolo: "4. Community, messaggi e moderazione",
    paragrafi: [
      "Rispetta le persone e le regole del club. Non pubblicare minacce, molestie, discriminazioni, spam, dati riservati di terzi o contenuti di cui non possiedi i diritti. Non usare messaggi e club per frodi, richieste di credenziali o diffusione di file dannosi.",
      "Puoi segnalare un contenuto attraverso le funzioni di segnalazione disponibili, indicando il contenuto e il motivo con elementi utili alla verifica. Non presentare segnalazioni deliberatamente false. Il personale autorizzato può esaminare la segnalazione e il contesto pertinente.",
      "In caso di violazione possono essere rimossi contenuti o limitati account e funzioni, in modo proporzionato alla gravità e alla reiterazione. Salvo impedimenti di legge o esigenze di sicurezza da motivare, l’interessato deve poter conoscere il motivo e chiedere un riesame attraverso i recapiti del gestore. Restano ferme le garanzie inderogabili applicabili ai servizi digitali.",
    ],
  },
  {
    titolo: "5. Qualifiche e informazioni sul vino",
    paragrafi: [
      "Puoi richiedere la verifica di una qualifica professionale caricando la documentazione pertinente. Non falsificare titoli o documenti. L’approvazione indica l’esito della verifica del titolo dichiarato, non una certificazione rilasciata da Vinea e non un’autenticazione delle bottiglie possedute o vendute.",
      "Finestre di consumo, abbinamenti e riferimenti di prezzo sono informazioni orientative: condizioni reali, conservazione e disponibilità possono modificarne la rilevanza. Non costituiscono una promessa di rendimento, una perizia della bottiglia o un consiglio sanitario. La community non sostituisce un esame professionale quando necessario.",
    ],
  },
  {
    titolo: "6. Costi e future compravendite",
    paragrafi: [
      "La beta descritta non addebita commissioni per acquisti, abbonamenti, vetrine o ispezioni. Prezzi e importi mostrati nei percorsi non operativi non autorizzano un addebito. Prima di introdurre un servizio a pagamento saranno comunicati prezzo completo, condizioni e modalità di accettazione.",
      "Prima delle vendite operative saranno definite e comunicate l’identità delle parti, la distinzione tra venditori privati e professionali, le condizioni di pagamento e spedizione e i diritti applicabili a recesso, conformità, reclami e rimborsi. Vinea non presume che ogni venditore sia privato e non esclude con questi termini le tutele inderogabili dei consumatori.",
      "Vetrina a pagamento, verifica fisica e servizi per eventi richiederanno condizioni specifiche. La pianificazione di tali attività non costituisce una loro offerta al pubblico.",
    ],
  },
  {
    titolo: "7. Disponibilità, chiusura e responsabilità",
    paragrafi: [
      "Durante lo sviluppo possono essere necessarie manutenzioni, correzioni o sospensioni. Le interruzioni programmate rilevanti devono essere comunicate quando possibile. Conserva una copia delle informazioni essenziali per te; ciò non esonera il gestore dai propri obblighi di sicurezza e protezione dei dati.",
      "Puoi cessare l’uso e chiedere la chiusura dell’account al gestore. La richiesta viene distinta dagli obblighi di conservazione e dai diritti degli altri interessati secondo l’informativa privacy. L’uscita dall’account o la cancellazione dei cookie non costituiscono chiusura dell’account.",
      "Il carattere sperimentale del servizio non esclude le responsabilità inderogabili del gestore, né quelle per dolo o colpa grave. Gli utenti rispondono delle proprie condotte secondo la legge; non è richiesta una rinuncia generale ai diritti o un’indennità illimitata a favore di Vinea.",
    ],
  },
  {
    titolo: "8. Modifiche, reclami e controversie",
    paragrafi: [
      "La versione è identificata dalla data in questa pagina. Le modifiche sostanziali ai termini devono essere comunicate in modo conoscibile, con le modalità di accettazione richieste dalla normativa. Non introducono retroattivamente costi o obblighi sulle operazioni già concluse.",
      "Per richieste, reclami e riesame di una decisione usa i recapiti del gestore nella scheda Contatti. Nessuna clausola impone un foro esclusivo in deroga alle tutele inderogabili del consumatore; restano ferme la legge applicabile e la competenza determinate dalle norme pertinenti.",
    ],
  },
];

export const cookie: readonly CapitoloLegale[] = [
  {
    titolo: "1. Cookie e altre memorie del dispositivo",
    paragrafi: [
      "I cookie sono piccoli dati conservati dal browser e inviati al sito nelle richieste successive. Il localStorage conserva invece informazioni nel browser senza inviarle automaticamente a ogni richiesta. Questa informativa riguarda entrambi: il nome della tecnologia non determina da solo se sia necessario il consenso.",
      "La beta utilizza strumenti per l’autenticazione e le funzioni richieste. Nel codice esaminato non sono integrati Google Analytics, Meta Pixel, pubblicità comportamentale o strumenti di registrazione delle sessioni. L’assenza di un banner non costituisce consenso e la navigazione non vale come accettazione di tracciatori facoltativi.",
    ],
  },
  {
    titolo: "2. Autenticazione Supabase",
    paragrafi: [
      "I cookie di prima parte con nome sb-<progetto>-auth-token, eventualmente suddiviso in parti come .0 e .1, mantengono la sessione autenticata. Contengono informazioni di sessione e non servono a inviare pubblicità. Sono utilizzati per l’accesso richiesto dall’utente.",
      "Il cookie sb-<progetto>-auth-token-code-verifier serve a completare in sicurezza il ritorno da un flusso di autenticazione. Il verificatore viene rimosso quando il flusso viene completato; in caso di flusso interrotto può restare fino alla scadenza o alla cancellazione del browser.",
      "La libreria usata dalla beta imposta una durata massima del cookie di 400 giorni, rinnovabile alla scrittura. Questa durata non equivale alla validità del singolo token né garantisce una sessione utilizzabile per tutto quel periodo. Logout, scadenza o revoca della sessione e impostazioni del browser possono interrompere prima l’accesso.",
    ],
  },
  {
    titolo: "3. Memorie delle funzioni",
    paragrafi: [
      "vinea:sommelier:session è una voce di localStorage che riconosce la conversazione del Sommelier sul dispositivo. Non contiene il testo della conversazione e non assegna diritti di accesso. Nella versione qui predisposta viene letta o creata soltanto all’apertura della chat quando il servizio AI è abilitato. Non ha una scadenza automatica; puoi eliminarla dai dati del sito nel browser. Un valore creato da una versione precedente può essere ancora presente anche con AI disattivata.",
      "sidebar_state è il cookie tecnico previsto dal componente di barra laterale, con durata di 7 giorni, per ricordarne lo stato aperto o chiuso quando quel componente viene utilizzato. Non è necessario alla lettura del Centro legale e non viene presentato come un cookie sempre installato su ogni pagina.",
    ],
  },
  {
    titolo: "4. Risorse esterne e servizi futuri",
    paragrafi: [
      "Il caricamento dei caratteri Google Fonts e di eventuali immagini remote trasmette al relativo server i dati tecnici della richiesta, anche in assenza di cookie. Il pulsante di accesso Google apre invece il servizio di autenticazione su tua richiesta: sul dominio Google si applicano anche le sue informazioni e impostazioni privacy.",
      "Un servizio di hosting può conservare log delle richieste senza installare cookie: tali dati sono descritti nella privacy. Non attribuiamo a Resend, Stripe o a corrieri cookie di acquisto già attivi nella beta, dove quei flussi non sono operativi.",
      "Prima di introdurre tracciatori non necessari saranno aggiornati elenco, finalità e durate e predisposti blocco preventivo, rifiuto e scelta revocabile. L’installazione di un banner, da sola, non rende conforme un tracciamento che parte prima della scelta.",
    ],
  },
  {
    titolo: "5. Come controllarli",
    paragrafi: [
      "Puoi consultare e cancellare cookie e dati del sito dalle impostazioni privacy del browser. Per chiudere la sessione usa anche Esci nell’account. Bloccare i cookie di autenticazione può impedire accesso, recupero password e funzioni private; non serve invece abilitare tracciatori pubblicitari per leggere le pagine pubbliche.",
      "La cancellazione del localStorage elimina le preferenze locali, non i dati conservati dal servizio. Per accesso, rettifica o cancellazione dei dati personali fai riferimento alla sezione I tuoi diritti della privacy e ai recapiti del titolare.",
    ],
  },
];
