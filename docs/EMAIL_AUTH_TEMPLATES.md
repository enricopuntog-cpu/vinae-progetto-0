# Template email di Supabase Auth — distribuzione

Stato al 13 ottobre 2026. Fonte del contenuto: i file in `supabase/templates/`
di questo repository. Il progetto di produzione è `pijnmcllmfgjmgsvtcej`; il
mittente è `Vinea Wine Club <noreply@vineawineclub.com>` via SMTP Resend
(`docs/ENVIRONMENT.md`).

Questo documento dice **che cosa** pubblicare e **come**. Il template «Confirm
signup» e la route `/auth/confirm` sono descritti in `docs/ENVIRONMENT.md`
(sezione del 9 ottobre 2026) e non cambiano.

## Che cosa è applicato e che cosa no

| Ambito | Stato |
| --- | --- |
| File HTML in `supabase/templates/` | versionati su `main` |
| `supabase/config.toml` | collega ogni file agli stack **locali e CI**; notifiche `enabled = false` |
| Progetto Supabase di produzione | **nessuna modifica**: ogni template va incollato a mano dal titolare (sotto) |
| Notifiche di sicurezza in produzione | **non attivate**; accenderle è una decisione del titolare |

`config.toml` non raggiunge la produzione: non si usa `supabase config push`
(porterebbe anche `site_url` e il resto della configurazione locale).

## Regole sui link

- `/auth/confirm` verifica `token_hash` lato server e accetta **solo** i tipi
  `email` e `signup` (`frontend-next/src/lib/auth/conferma-email.ts`). È usato
  solo da «Confirm signup».
- Invito, magic link, cambio email e recupero password usano il link standard
  `{{ .ConfirmationURL }}`: `/auth/v1/verify` di Supabase, che poi rimanda al
  `redirect_to` già validato contro l'elenco dei Redirect URLs. È lo stesso link
  dei template predefiniti: la grafica cambia, il flusso no.
- Pulsante (anche nella variante VML per Outlook) e link alternativo puntano
  alla stessa destinazione; il test
  `frontend-next/src/lib/auth/template-email-auth.test.ts` lo impone.
- Reauthentication non ha link: mostra il codice `{{ .Token }}`.
- Le notifiche non contengono token: solo `https://vineawineclub.com/accedi` e
  il link al sito.
- Nessun testo dichiara una durata: la scadenza effettiva dipende dalla
  configurazione del progetto (OTP expiry) e non è stata letta da qui.

## Template di autenticazione

Dashboard: pagina «Email Templates» del progetto,
`https://supabase.com/dashboard/project/pijnmcllmfgjmgsvtcej/auth/templates`
(i nomi delle voci sono quelli della documentazione Supabase; la disposizione
della pagina può cambiare).

| Voce del dashboard | Oggetto | File | Variabili usate | Link / codice |
| --- | --- | --- | --- | --- |
| Confirm sign up | `Conferma la tua email \| Vinea Wine Club` | `supabase/templates/confirm-signup.html` | `SiteURL`, `TokenHash`, `RedirectTo` | `/auth/confirm` (già attivo, invariato) |
| Invite user | `Il tuo invito a Vinea Wine Club` | `supabase/templates/invite.html` | `ConfirmationURL` | link standard |
| Magic link or OTP | `Accedi a Vinea Wine Club` | `supabase/templates/magic-link.html` | `ConfirmationURL` | link standard → `/auth/callback?code=` |
| Change email address | `Conferma il tuo nuovo indirizzo email \| Vinea` | `supabase/templates/email-change.html` | `ConfirmationURL`, `Email`, `NewEmail` | link standard |
| Reset password | `Reimposta la password \| Vinea Wine Club` | `supabase/templates/reset-password.html` | `ConfirmationURL` | link standard → `/auth/callback?code=…&next=/reimposta-password` |
| Reauthentication | `Verifica di sicurezza \| Vinea Wine Club` | `supabase/templates/reauthentication.html` | `Token` | codice OTP, nessun link |

Nel campo «Subject» va il testo senza le barre rovesciate della tabella
(`Conferma il tuo nuovo indirizzo email | Vinea`).

## Notifiche di sicurezza

Dashboard: stessa area «Email Templates», gruppo delle notifiche di sicurezza. Supabase le invia solo se la singola notifica è attiva nel
progetto. Incollare oggetto e corpo **non** richiede di attivarle; se il
dashboard salva il contenuto solo con l'interruttore acceso, lasciare la voce
com'è e rimandare alla decisione del titolare.

| Voce del dashboard | Oggetto | File | Variabili |
| --- | --- | --- | --- |
| Password changed | `La tua password è stata modificata \| Vinea Wine Club` | `supabase/templates/password-changed-notification.html` | `Email` |
| Email address changed | `Il tuo indirizzo email è stato modificato \| Vinea Wine Club` | `supabase/templates/email-changed-notification.html` | `OldEmail`, `Email` |
| Phone number changed | `Il tuo numero di telefono è stato modificato \| Vinea Wine Club` | `supabase/templates/phone-changed-notification.html` | `Email`, `OldPhone`, `Phone` |
| Sign-in method linked | `Nuovo metodo di accesso collegato \| Vinea Wine Club` | `supabase/templates/identity-linked-notification.html` | `Email`, `Provider` |
| Sign-in method removed | `Metodo di accesso rimosso \| Vinea Wine Club` | `supabase/templates/identity-unlinked-notification.html` | `Email`, `Provider` |
| Verification method added | `Nuovo metodo di verifica aggiunto \| Vinea Wine Club` | `supabase/templates/mfa-factor-enrolled-notification.html` | `Email`, `FactorType` |
| Verification method removed | `Metodo di verifica rimosso \| Vinea Wine Club` | `supabase/templates/mfa-factor-unenrolled-notification.html` | `Email`, `FactorType` |

`Provider` e `FactorType` arrivano come identificatori tecnici di GoTrue (per
esempio `google`, `totp`) e sono mostrati così come sono.

## Variabili: da dove vengono

Elenco ufficiale: <https://supabase.com/docs/guides/auth/auth-email-templates>.
Chiavi effettivamente passate a `html/template` da GoTrue
(`supabase/auth`, `internal/mailer/templatemailer/templatemailer.go`, letto il
13 ottobre 2026):

- invito, conferma, recupero, magic link: `SiteURL`, `ConfirmationURL`,
  `Email`, `Token`, `TokenHash`, `Data`, `RedirectTo`;
- cambio email: le stesse più `NewEmail` e `SendingTo`;
- riautenticazione: `SiteURL`, `Email`, `Token`, `Data`;
- notifiche: `SiteURL`, `Email`, `Data` più `OldEmail`, `Phone`/`OldPhone`,
  `Provider` o `FactorType` secondo la notifica.

Il test impone che ogni template usi solo le chiavi del proprio elenco. Corpo e
oggetto sono resi con `html/template`: i commenti condizionali per Outlook
vengono rimossi (resta il pulsante HTML) e i valori sono sottoposti a escape.

## Pubblicazione in produzione

Ordine: un template alla volta, partendo da quelli a basso rischio.

1. Aprire il dashboard del progetto `pijnmcllmfgjmgsvtcej` e controllare in alto
   che sia il progetto di produzione.
2. **Prima di toccare un template, salvarne il contenuto attuale** (oggetto e
   corpo) in un file locale fuori dal repository: è il rollback.
3. Incollare nel campo «Subject» l'oggetto della tabella.
4. Incollare nel corpo **l'intero file** HTML da `main` (aperto «Raw» su GitHub
   o dal repository locale aggiornato), dal `<!DOCTYPE html>` all'ultima riga.
5. Salvare.
6. Provare con un account di test autorizzato, mai con utenti reali:
   - Reset password: da `https://vineawineclub.com/accedi`, «Password
     dimenticata?» con l'indirizzo di test; aprire il link **nello stesso
     browser** → `/reimposta-password` con il modulo della nuova password;
   - Magic link: accesso via link dalla pagina di accesso, stesso browser →
     area utente;
   - Invite user: dal dashboard (Authentication → Users → Invite) verso un
     indirizzo di test; vedere il limite noto qui sotto;
   - Change email address e Reauthentication: oggi nessuna pagina del sito li
     avvia; la resa si verifica solo con chiamate API su un account di test.
7. Controllare la resa in Gmail, Apple Mail e Outlook (logo, nome del club,
   pulsante) e annotare data ed esito in `CHANGES.log`.

Per automatizzare, la Management API accetta gli stessi campi
(`mailer_subjects_*`, `mailer_templates_*_content`, e per le notifiche
`mailer_notifications_*_enabled`) con un token personale del titolare; questa
procedura non è stata eseguita e non è necessaria.

## Rollback

Per ogni template: incollare di nuovo oggetto e corpo salvati al passo 2 e
salvare. In mancanza della copia, il template predefinito di Supabase con
`{{ .ConfirmationURL }}` (o `{{ .Token }}` per Reauthentication) ripristina il
comportamento originale: i template nuovi non cambiano i link, quindi tornare
indietro non rompe email già inviate. Il repository non va modificato per un
rollback del dashboard.

## Verifiche eseguite (13 ottobre 2026)

- **Rendering Go**: tutti i template, più il «Confirm signup» di riferimento,
  resi con `html/template` di Go 1.23 nello stesso modo di GoTrue (Parse ed
  Execute su `map[string]any`, nessuna opzione `missingkey`) con dati sintetici:
  14 casi, 0 errori, nessun `{{`, `<no value>`, `ZgotmplZ` o `href=""`.
- **Screenshot**: Chromium (Playwright 1.48.2) a 600px e 375px su ogni
  anteprima resa: logo caricato da produzione (240px naturali, 80px mostrati),
  «VINEA WINE CLUB» presente, nessuno scroll orizzontale, nessun elemento oltre
  il bordo, pulsante e link alternativo con la stessa destinazione, codice OTP
  leggibile (34px, 28px sotto i 620px). Sono anteprime HTML, non email ricevute
  in un client di posta. A 600px vale già la regola mobile del template
  approvato (`max-width:620px`).
- **GoTrue locale** (Supabase CLI 2.117.0, GoTrue v2.196.0, Mailpit, indirizzi
  `.test`, stack spento dopo la prova): un utente per flusso, email consegnate
  con l'oggetto italiano e nessun residuo di template.
  - magic link (PKCE) → `303 …/auth/callback?code=…`;
  - reset password (PKCE, `next=/reimposta-password`) →
    `303 …/auth/callback?code=…&next=%2Freimposta-password`;
  - cambio email (PKCE) → due email, una all'indirizzo attuale e una al nuovo,
    stesso template; il link porta a `…/auth/callback?code=…`;
  - riautenticazione → codice di 6 cifre, nessun link;
  - invito → `303 <Site URL>#access_token=…&type=invite` (vedi limiti).
  Le notifiche non sono state inviate dallo stack: restano spente anche in
  locale; la loro resa è coperta dal rendering Go.
- **Test**: `template-email-auth.test.ts` (75 casi) in CI con `frontend-next`.

## Limiti noti e problemi preesistenti

Segnalati, non corretti: nessuno dipende dalla grafica.

- **Magic link e recupero password richiedono lo stesso browser** della
  richiesta: il link torna su `/auth/callback?code=` e lo scambio PKCE richiede
  il `code_verifier` di quel browser (stessa causa misurata il 9 ottobre 2026
  per la registrazione). I template lo dicono all'utente. Il rimedio, se
  diventerà necessario, è una route `token_hash` dedicata, non `/auth/confirm`.
- **Inviti Supabase Auth**: nessuna parte del sito li usa. Un invito dal
  dashboard torna al Site URL con la sessione nel frammento
  (`#access_token=…`, flusso implicito), mentre il client del sito usa PKCE e
  `/auth/callback` si aspetta `?code=`. Prima di usare gli inviti Supabase va
  provato il percorso completo. Non sono gli inviti commerciali di Vinea
  Partner, che non passano da questi template.
- **Cambio email**: nessuna pagina del sito lo avvia. Sullo stack locale
  (GoTrue v2.196.0, `double_confirm_changes = true`) la **prima** conferma, da
  uno qualunque dei due indirizzi, ha completato la modifica e l'altro link è
  risultato scaduto. Per questo il template chiede di confermare «solo se l'hai
  richiesta tu». Il comportamento del progetto di produzione non è stato
  misurato.
- **Reauthentication**: il sito non chiama `reauthenticate()`;
  `secure_password_change` è `false` in `config.toml` (produzione non letta).
  La regola dei prelievi (`reauth_required`) misura la recenza della sessione e
  non usa questa email.
- **Phone number changed**: il sito non gestisce numeri di telefono; il
  template è pronto ma oggi non ha un flusso che lo invii.
- La configurazione Auth di produzione (template attivi, notifiche, OTP expiry,
  doppia conferma) **non è stata letta**: nessun token della Management API era
  disponibile in questa sessione.
