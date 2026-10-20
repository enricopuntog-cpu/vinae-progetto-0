# VPM-015B1 — Cantina Accessori personale

Contratto del sotto-blocco 015B1 (21 ottobre 2026), costruito sulla fondazione
[VPM-015A](VPM_015A_ACCESSORI.md). Gli utenti possono tenere nella propria
Cantina anche gli **accessori che possiedono**, sul modello della Cantina delle
bottiglie. **Nessuna vendita, nessun checkout, nessun pagamento**: «esposto»
non significa «in vendita»; la vendita è solo una possibilità futura.

## Perimetro

Fatto in questo sotto-blocco:

- **A. Inventario personale** (`private.cantina_accessori`): proprietario dal
  contesto autenticato, tipo controllato, nome, condizione, quantità, foto
  facoltative, dettagli facoltativi, visibilità, archiviazione.
- **B. Sezione «Accessori» nella Cantina dell'utente** (`/cantina`): aggiungi,
  modifica, foto, quantità, archivia/ripristina, rimuovi, esponi/rendi privato.
  È un componente a parte dentro la pagina esistente: le funzioni delle
  bottiglie non cambiano e la pagina non è duplicata.
- **C. «Accessori della cantina»** nel profilo pubblico (`/profilo/[id]`, prime 6
  voci con rinvio) e nella Cantina pubblica (`/profilo/[id]/cantina`, fino a 48):
  il visitatore vede solo ciò che il proprietario ha esposto.
- **D. Predisposizione** a un futuro legame con un annuncio: nessuna tabella,
  colonna o pulsante di vendita. Vedi «Predisposizione alla vendita».
- **E. Interruttori** minimi, fail-closed, nel database (nessuna variabile
  d'ambiente nuova).

Escluso (invariato dal task): checkout, pagamenti reali, commissioni, IVA,
spedizione e assicurazione definitive, vendita Partner di accessori, fornitori e
magazzini, casse personalizzate, configuratori, alcolici, articoli regolamentati,
revisione generale della tassonomia, redesign Vinea. Non si avviano VPM-015B2,
VPM-015C o altri blocchi.

## Modello dati

Migrazione `20261021090000_vpm_015b1_cantina_accessori.sql` (additiva). Tutto in
`private`, RLS attiva, **nessun grant** ai ruoli client; solo funzioni `public.cantina_accessori_*`
`security definer` con `search_path` vuoto.

| Oggetto | Ruolo |
|---|---|
| `private.cantina_accessori` | una riga per tipo di accessorio posseduto, con `quantita` 1–999 (gli accessori non hanno uno stato per singolo pezzo come le bottiglie, quindi non c'è una riga per pezzo) |
| `private.cantina_accessori_impostazioni` | singleton con i due interruttori, spenti di default |
| `private.cantina_accessori_pubblica` | vista chiusa (`security_invoker = off`, `security_barrier`): la proiezione pubblicabile |
| bucket `cantina-accessori-foto` | Storage **privato**, WebP ≤ 2 MB |
| `private.accessori_registro` | riuso del registro append-only della 015A (il vincolo `oggetto` accoglie `cantina_accessori`) |

Colonne di `cantina_accessori`: `owner_id` (FK `profiles`, `on delete cascade`),
`categoria_id` (FK su `private.accessori_categorie`, **per id**: rinominare una
categoria non rompe i legami), `catalogo_id` (FK facoltativa e in sola lettura su
`private.accessori`, `on delete set null`), `nome`, `descrizione`, `marchio`,
`condizione` (`nuovo`/`come_nuovo`/`usato`/`da_collezione`), `quantita`,
`note_private`, `immagini` (≤ 4), `visibilita` (`privata` | `cantina_pubblica`,
stesso lessico delle bottiglie), `archiviato_at`. Nessun numero di serie, prezzo,
valuta o legame con `wines`, `bottle_units`, `cellar_slots`, `listings`, `orders`.

Un trigger (`cantina_accessori_guard`) vincola **anche i writer privilegiati**:
proprietario e id immutabili, categoria valida (vedi sotto), legame col catalogo
solo verso schede pubblicate, foto solo in `<owner>/<accessorio>/`, accessorio
**privato alla nascita**, esposizione solo se la porta ha dichiarato la scelta
del proprietario nella stessa transazione, archiviato ⇒ privato.

## Inserimento guidato

L'utente sceglie il **tipo** dalla tassonomia Vinea (`private.accessori_categorie`),
poi nome, condizione, quantità; marchio, descrizione, note private e foto sono
facoltativi. Regole nel database:

- la categoria è obbligatoria, **attiva** e **foglia**: la sottocategoria è
  obbligatoria dove esiste (`sottocategoria_obbligatoria`); «Altri accessori» e le
  categorie senza figli (Degustazione, Pulizia, Set regalo) sono scelte valide;
- gli utenti **non creano categorie**: nessuna porta le scrive, nessun grant sulla
  tabella, e il campo `categoria_nuova` (o qualunque campo ignoto) è rifiutato
  (`campo_sconosciuto`);
- la tassonomia è leggibile per l'inserimento con `cantina_accessori_categorie_elenca()`
  **anche con il catalogo commerciale spento**: l'elenco contiene solo categorie
  attive (id, slug, nome) e non apre schede, bozze, conteggi o la visibilità del
  catalogo;
- il client sceglie l'`id` di un accessorio nuovo: ripetere il salvataggio dopo un
  errore di rete non lo duplica (un id altrui risponde `non_trovato`, come uno
  inesistente); tetto di 300 accessori per utente (`limite_raggiunto`);
- i testi sono ripuliti e senza caratteri di controllo; `owner_id`, `visibilita`,
  `immagini` e ogni campo non previsto non sono accettati da `cantina_accessori_salva`;
- il legame facoltativo con una scheda del catalogo (`catalogo_slug`) accetta solo
  schede **pubblicate** e solo se il catalogo è visibile (o l'utente è admin in
  collaudo); non crea né modifica prodotti del catalogo.

Le foto si caricano dopo il salvataggio (serve l'id): il client ridimensiona in
WebP (`preparaImmagineVetrina`), carica nella propria cartella e collega con
`cantina_accessori_immagini_imposta`. Se il collegamento fallisce il file viene
cancellato.

## Come è protetta la Cantina privata

- **Proprietario sempre da `auth.uid()`**: nessuna porta riceve un id proprietario
  dal browser; un id accessorio altrui risponde come un inesistente.
- Nessun accesso diretto: le tabelle e la vista non hanno grant per `anon` né
  `authenticated`; un accessorio privato non si legge né via URL né via RPC.
- **Foto private a livello Storage**: bucket `public = false`. Il proprietario
  legge/scrive solo la propria cartella (`<uid>/…`); l'inserimento richiede che
  l'accessorio esista ed sia suo; la cancellazione solo di file non in uso.
  Nemmeno un admin legge le foto private di un utente. Verificato anche via HTTP:
  `/object/public/…` → 400, `/object/authenticated/…` con la sola anon key → 400,
  firma con la anon key → 404.
- Nessun ruolo admin o commerciale si acquisisce dal client; il catalogo admin
  della 015A resta invariato (le sue porte rispondono come prima).

## Come funziona la visibilità pubblica

1. Un accessorio **nasce privato**. L'esposizione è una scelta esplicita
   (`cantina_accessori_visibilita_imposta`, con conferma nell'interfaccia) che
   imposta un marcatore valido solo per quella transazione e per quella coppia
   utente/accessorio; un `UPDATE` diretto, anche privilegiato, è rifiutato.
2. La lettura pubblica passa **solo** da
   `cantina_accessori_pubblica_profilo(uuid, limite, offset, anteprima)`: un profilo
   per volta, nessun filtro di ricerca, tetto di 48 deciso dal database. Restituisce
   un **elenco chiuso**: `id`, `nome`, `descrizione`, `marchio`, `condizione`,
   `quantita`, `immagini`, `categoria_slug`, `categoria_nome`, `genitore_nome`. Mai
   note private, id proprietario, legame col catalogo, date o `visibilita`.
   La vista porta con sé la regola a due direzioni di `private.profili_pubblici`.
3. Le foto di un accessorio esposto (le foto sono parte di ciò che si espone) si
   firmano solo se l'accessorio è **esposto e non archiviato** e funzione **e**
   visibilità sono accese.
4. Tornare **privato**, archiviare o spegnere un interruttore ferma le **nuove**
   letture: l'elenco torna vuoto e le nuove firme falliscono. Una URL firmata già
   emessa vale fino a scadenza (**900 s**): residuo accettato e documentato.
   Il proprietario può sempre riportare un accessorio a privato, anche a funzione spenta.
5. Con gli interruttori spenti la pagina non rende **niente** (né titolo né
   segnaposto): un blocco vuoto racconterebbe la funzione o una scelta privata.

## Interruttori (fail-closed)

Tre cose restano separate:

| Cosa | Dove | Default |
|---|---|---|
| visibilità pubblica del **catalogo centrale** | `private.accessori_impostazioni` (015A, invariato) | spenta |
| **funzione** Cantina Accessori personale | `cantina_accessori_impostazioni.funzione_attiva` | spenta |
| visibilità degli **accessori esposti** | `cantina_accessori_impostazioni.visibilita_pubblica` | spenta |

- Sono nel **database** e sono l'unica autorità: nessuna variabile d'ambiente
  nuova (nessun cambiamento a `.env.example` o a `docs/ENVIRONMENT.md`).
- **Accendere** richiede un admin reale con il ruolo `accessori_release` (come la
  015A); un trigger vincola anche i writer privilegiati. **Spegnere** basta un
  admin. Ogni cambio è nel registro append-only con motivo.
- Un **admin reale** può collaudare la funzione (inserire e vedere i propri
  accessori) anche da spenta, e vedere l'anteprima pubblica
  (`p_anteprima = true`) con la visibilità spenta: così la Beta si verifica in
  produzione senza accendere nulla al pubblico. Gli accessori creati in collaudo
  restano privati.
- Pannello admin: `/admin/accessori`, sezione «Cantina Accessori personale»
  (due interruttori, conferma scritta `ATTIVA`).
- Con la funzione spenta la sezione non compare in `/cantina` e le porte rifiutano
  le scritture (`funzione_non_attiva`).

## Predisposizione alla vendita (differita)

Non c'è nulla di acquistabile e nessun pulsante finto. L'architettura è pronta:
l'accessorio ha un `id` stabile, un proprietario, un tipo, una condizione e una
quantità. Un annuncio futuro potrà aggiungere in modo **additivo** una tabella di
appartenenza (sul modello di `listing_unita`) con unicità sull'unica appartenenza
aperta, senza riscrivere questa tabella e senza toccare `wines`/`bottle_units`. La
forma e le regole di quella tabella (unità vs quantità prenotabile, prezzo,
commissione) sono decisioni del blocco commerciale (vedi sotto).

## Prove

- Griglia DB `supabase/tests/12zi_vpm_015b1_cantina_accessori.sql` (39 casi,
  registrata nel gate `Supabase DB regression`): interruttori e rilascio,
  tassonomia con il catalogo spento, creazione/modifica/idempotenza, regole di
  categoria, nessuna categoria creabile, validazione, isolamento fra utenti,
  nascita privata ed esposizione esplicita, proiezione a campi chiusi, ritorno a
  privato/archivio/interruttori, anteprima admin, tetti 48/300, Storage (scrittura,
  lettura, firma pubblica solo se esposto, cancellazione), separazione da vino e
  mercato, catalogo 015A invariato, volatilità e grant. La 12zh ammette l'unica
  FK della Cantina Accessori verso tassonomia e schede.
- `frontend-next`: test di unità (parser, modulo, servizi con client finto,
  lettura fail-closed) e di contratto
  (`src/lib/cantina-accessori/cantina-accessori-contratto.test.ts`): nessun
  percorso di transazione, nessuna tabella del vino, nessuna variabile d'ambiente,
  foto sempre firmate, forma della migrazione. Soglia CI dei test: 2980 (alzata a 3040 da VPM-015B2).
- Verifica in browser su stack locale a 375 px: inserimento, foto, esposizione,
  profilo e Cantina pubblica, nessuno scroll orizzontale, barra mobile intatta.

## Rischi residui e limiti

- **Contenuti pubblici senza pre-moderazione.** Nome, descrizione e foto di un
  accessorio esposto sono testo/immagini liberi dell'utente: nessun filtro
  preventivo; restano la segnalazione del profilo e la moderazione esistenti.
  Decisione per il titolare (moderazione dei contenuti pubblici) in «Decisioni».
- **File orfani su cancellazione dell'account.** `owner_id` cade in cascata e
  rimuove le righe, ma i file nel bucket non si cancellano da SQL: serve un job di
  pulizia (non in questo blocco).
- URL firmate già emesse valide fino a 900 s dopo il ritiro.
- Il ruolo di rilascio si assegna a mano (come in 015A).

## Decisioni del titolare per il prossimo blocco commerciale

Non inventate qui; vanno delimitate e decise (si aggiungono a «Decisioni per
VPM-015B» di [VPM_015A_ACCESSORI.md](VPM_015A_ACCESSORI.md)):

1. **Unità o quantità prenotabile**: un annuncio vende «1 di N» (quantità) o solo
   un accessorio intero? Impatta unicità e prenotazione.
2. **Chi può mettere in vendita** un accessorio posseduto (solo privati, anche
   Partner) e **a quali condizioni** (condizione minima, foto obbligatorie).
3. **Moderazione** di foto e descrizioni, oggi pubbliche senza revisione preventiva.
4. **Prezzo, commissione, IVA, spedizione** per accessori posseduti (stesse
   domande di VPM-015B: FIN/LEG).
5. Rapporto con la **vendita Partner di accessori nuovi** (catalogo vs bene posseduto).
