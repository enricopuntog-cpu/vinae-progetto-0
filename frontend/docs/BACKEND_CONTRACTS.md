# Backend contracts

Contratti futuri per l'integrazione Supabase. **Nessuna credenziale, nessun
segreto in questo file.** Le firme TypeScript vivono in
`src/services/types.ts`.

## Tabelle previste

```text
profiles            (id → auth.users, nome, bio, città, avatar, obiettivi[])
user_roles          (user_id, role)  — separata dal profilo (anti-escalation)
verifications       (user_id, tipo, stato, updated_at)
wines               (id, produttore, denominazione, annata, regione, tipologia)
listings            (id, wine_id, seller_id, prezzo, stato, immagini[], provenance)
cellar_environments (id, user_id, tipo, nome)
cellar_modules      (id, environment_id, forma, slots)
cellar_bottles      (id, user_id, wine_id, slot_id, stato, drink_window_override)
proposals           (id, listing_id, buyer_id, prezzo, stato, scadenza)
orders              (id, listing_id, buyer_id, seller_id, prezzo, modo_consegna,
                     buyer_status, seller_status, indirizzo)
order_events        (id, order_id, tipo, payload, created_at)
disputes            (id, order_id, motivo, descrizione, prove[], stato, esito)
order_reviews       (id, order_id, voti, testo, created_at)
clubs               (slug, nome, territorio, denominazione, descrizione, regole)
club_memberships    (user_id, club_slug, ruolo)
discussions         (id, club_slug, autore_id, titolo, corpo, created_at)
messages            (id, conversation_id, autore_id, corpo, tipo)
conversations       (id, partecipanti[], listing_id?)
notifications       (id, user_id, categoria, titolo, testo, letta, link)
reports             (id, reporter_id, target_type, target_id, motivo, stato)
audit_log           (id, actor_id, action, target_type, target_id, motivo, at)
```

## RLS (principi)

- Ogni tabella `public.*` deve avere `GRANT` esplicito prima delle policy
  (anon/authenticated/service_role).
- `profiles`: SELECT pubblica per campi non sensibili, UPDATE solo owner.
- `listings`: SELECT pubblica solo per `stato = 'attivo'`; INSERT/UPDATE
  solo `seller_id = auth.uid()` E `has_role(auth.uid(), 'seller_enabled')`.
- `orders`/`disputes`/`messages`: SELECT solo se `auth.uid()` è tra
  buyer/seller/partecipanti.
- `reports`: INSERT authenticated; SELECT solo owner o moderatore.
- `audit_log`: SELECT solo admin; INSERT via SECURITY DEFINER function.
- `user_roles`: SELECT authenticated (usato da `has_role()` SECURITY DEFINER);
  INSERT/UPDATE solo service_role.

## Edge Functions previste

- `payments-checkout` — crea PaymentIntent Stripe (input: `orderId`).
- `payments-webhook` — Route Handler `/api/public/webhooks/stripe`, verifica
  firma HMAC prima di aggiornare l'ordine.
- `ai-identify-bottle` — proxy verso provider vision (rate-limit per utente).
- `moderation-decision` — applica azione, scrive `audit_log`, notifica utente.

## Realtime

- `notifications:user_id=eq.$uid` → push in-app.
- `conversations:conversation_id=eq.$cid` → messaggistica.
- `orders:order_id=eq.$oid` → timeline live.

## Storage

- Bucket `listings/{listing_id}/*` — foto annuncio (upload firmato lato server).
- Bucket `avatars/{user_id}.jpg` — public.
- Bucket `disputes/{dispute_id}/*` — private, signed URLs.

## Secrets attesi (mai in repo)

- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`
- `RESEND_API_KEY` (o equivalente per email transazionali)
- `AI_PROVIDER_API_KEY`

Da configurare in Supabase → Vault / Vercel → Environment Variables.
Nessuno di questi valori appartiene al bundle client.
