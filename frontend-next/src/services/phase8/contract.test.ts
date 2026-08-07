import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const migration = readFileSync(
  join(
    import.meta.dir,
    "../../../../supabase/migrations/20260806224517_phase_8_messaging_notifications.sql",
  ),
  "utf8",
);
const types = readFileSync(join(import.meta.dir, "../../services/types.ts"), "utf8");
const composer = readFileSync(
  join(import.meta.dir, "../../components/vinea/messaging/MessageComposer.tsx"),
  "utf8",
);

const publicRpcBlock = migration.slice(
  migration.indexOf("create or replace function public.conversation_open"),
  migration.indexOf("notify pgrst"),
);

describe("contratto SQL Fase 8", () => {
  it("crea le quattro tabelle canoniche", () => {
    for (const table of [
      "conversations",
      "conversation_participants",
      "messages",
      "notifications",
    ]) {
      expect(migration).toContain(`create table public.${table}`);
    }
  });

  it("non concede scritture tabellari ai ruoli client", () => {
    expect(migration).not.toMatch(/grant\s+(?:insert|update|delete)[\s\S]{0,120}to authenticated/i);
    expect(migration).toContain("revoke all on public.conversations");
  });

  it("le RPC derivano l identita da auth.uid senza p_user_id", () => {
    expect(publicRpcBlock).toContain("auth.uid()");
    expect(publicRpcBlock).not.toContain("p_user_id");
  });

  it("il controllo idempotente precede entrambi i rate limit", () => {
    const body = migration.slice(
      migration.indexOf("create or replace function public.message_send"),
      migration.indexOf("create or replace function public.conversation_mark_read"),
    );
    expect(body.indexOf("if found then")).toBeLessThan(body.indexOf("rate_limit_consume"));
  });

  it("applica 30 al minuto e 10 ogni 10 secondi", () => {
    expect(publicRpcBlock).toContain("'message:send', 'user:' || v_uid::text, 30, 60");
    expect(publicRpcBlock).toMatch(/'message:send:conversation'[\s\S]*?10,\s*10/);
  });

  it("Realtime ha una sola policy SELECT di fase e nessuna INSERT", () => {
    expect(migration).toContain("create policy vinea_phase8_private_broadcast_select");
    expect(migration).not.toMatch(/on realtime\.messages for insert/i);
  });

  it("i payload Realtime sono invalidazioni e non righe complete", () => {
    expect(migration).toContain("'schemaVersion', 1");
    expect(migration).toContain("'conversationId', new.conversation_id");
    expect(migration).not.toContain("to_jsonb(new)");
  });

  it("le notifiche usano destinazioni tipizzate e nessun URL", () => {
    const notificationTable = migration.slice(
      migration.indexOf("create table public.notifications"),
      migration.indexOf("create index notifications_recipient_page_idx"),
    );
    expect(migration).toContain("notifications_destination_shape");
    expect(notificationTable).not.toMatch(/\b(?:destination_url|href|url)\s+text\b/i);
  });

  it("la porta system e chiusa al browser e aperta solo al service_role", () => {
    expect(migration).toContain("private.conversation_system_event");
    expect(migration).toMatch(/grant execute on function private\.conversation_system_event[\s\S]*?to service_role/);
  });

  it("il retry system respinge una chiave riusata con payload diverso", () => {
    const body = migration.slice(
      migration.indexOf("create or replace function private.conversation_system_event"),
      migration.indexOf("create or replace function public.conversation_open"),
    );
    expect(body).toContain("v_existing.body <> v_body");
    expect(body).toContain("Evento sistema gia usato con un altro payload");
  });
});

describe("contratto TypeScript Fase 8", () => {
  it("MessagingService e NotificationService non accettano userId", () => {
    const block = types.slice(
      types.indexOf("export interface MessagingService"),
      types.indexOf("// ---- Moderazione"),
    );
    expect(block).not.toContain("userId:");
    expect(types).toContain("idempotencyKey: string;");
  });

  it("il retry del composer conserva la chiave finche l invio non riesce", () => {
    expect(composer).toContain("idempotencyKey.current");
    expect(composer.indexOf("if (!result.ok)")).toBeLessThan(
      composer.indexOf("idempotencyKey.current = newKey()"),
    );
  });
});
