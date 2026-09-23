# Status page indipendente

Pagina statica pubblicata da `status-page/site/` su **Cloudflare Pages** (piano
gratuito) all'indirizzo `https://status.vineawineclub.com`. Non dipende da
Netlify produzione, Supabase, dal frontend Next o da alcuna API: niente
JavaScript, niente risorse esterne, solo HTML e CSS inline. Resta leggibile se
il sito principale non risponde.

Contenuto di `site/`:

- `index.html` — stato corrente, aggiornamenti, legenda;
- `404.html` — evita che Cloudflare serva `index.html` su percorsi inesistenti;
- `_headers` — CSP `default-src 'none'`, niente frame, `nosniff`, HSTS,
  `no-referrer`, cache con rivalidazione immediata.

`node .github/scripts/status-page-check.mjs` (eseguito in CI) rifiuta script,
risorse esterne, link non ammessi, stati sconosciuti, etichette incoerenti,
timestamp senza fuso e testo simile a secret.

## Pubblicare un aggiornamento durante un incidente

Serve solo GitHub: funziona anche con Netlify, Supabase e l'app Vinea fermi.

1. Modifica `status-page/site/index.html`, anche dall'editor web di GitHub.
2. Nella `<section class="status">` imposta `data-state` e l'etichetta
   corrispondente:

   | `data-state` | Etichetta |
   | --- | --- |
   | `operativo` | Operativo |
   | `investigazione` | Investigazione in corso |
   | `identificato` | Problema identificato |
   | `aggiornamento` | Aggiornamento |
   | `risolto` | Risolto |

3. Scrivi una descrizione breve dell'impatto per gli utenti. Niente dettagli
   tecnici interni, nomi di fornitori, dati personali o tempi promessi.
4. Aggiorna `<time datetime="AAAA-MM-GGTHH:MM:SS+02:00">` (fuso obbligatorio)
   e il testo leggibile.
5. Aggiungi in cima a `<ol class="updates">` una voce:

   ```html
   <li data-state="investigazione"><strong>Investigazione in corso</strong> — <time datetime="2026-09-23T18:10:00+02:00">23 settembre 2026, 18:10</time><br />Descrizione.</li>
   ```

6. Dall'editor web scegli "Create a new branch and start a pull request", poi
   squash merge. Il job CI `Continuity scripts - syntax` valida la pagina in
   pochi secondi; dopo il merge Cloudflare pubblica in circa un minuto.
7. Nel banner Vinea (`/continuita`, pannello incidente) usa come URL
   `https://status.vineawineclub.com`.

Chiuso l'incidente: stato `risolto`, poi, quando non serve più, di nuovo
`operativo` con la voce "Nessun aggiornamento pubblicato." o lo storico breve.

## Configurazione Cloudflare Pages

Pubblicata il 23 settembre 2026. Progetto Git collegato al repository, senza
build:

- nome progetto `vinea-status` (URL di riserva `https://vinea-status.pages.dev`);
- branch di produzione `main`; preset framework *None*; comando di build vuoto;
  directory di output `status-page/site`;
- build watch paths: include `status-page/*`, così gli altri commit non
  consumano build;
- dominio personalizzato `status.vineawineclub.com`, aggiunto nel progetto
  **prima** del record DNS.

DNS (Netlify DNS, zona `vineawineclub.com`): un solo record `CNAME`
`status` → `vinea-status.pages.dev`, TTL 3600. Nessun altro record cambia.

Limite noto: la zona DNS è ospitata da Netlify. Se cadesse proprio il DNS
Netlify, `status.vineawineclub.com` non risolverebbe; l'indirizzo
`https://vinea-status.pages.dev` resta raggiungibile e va citato nelle
comunicazioni email in quel caso.

I branch che modificano `status-page/` generano anche un deploy di anteprima
pubblico su un URL `*.vinea-status.pages.dev` (con `noindex`): nelle bozze non
scrivere nulla che non possa diventare pubblico.

## Anteprima locale

Aprire `site/index.html` nel browser basta: la pagina non carica nulla
dall'esterno. Per simulare un incidente senza pubblicarlo, modificare una copia
locale.
