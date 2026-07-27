import { z } from "zod";

export const checkoutSessionSchema = z.object({
  checkout_url: z.string().url(),
  session_id: z.string().min(1),
  order_id: z.string().min(1),
});

export const paymentStatusSchema = z.object({
  session_id: z.string().min(1),
  payment_status: z.string(),
  status: z.string(),
  order_id: z.string().min(1),
});

export const pairingSchema = z.object({
  intro: z.string(),
  picks: z.array(
    z.object({
      wine_id: z.string(),
      reasoning: z.string(),
    }),
  ),
});

export const listingSuggestionSchema = z.object({
  nome: z.string(),
  produttore: z.string(),
  annata: z.number().int().nullable(),
  regione: z.string(),
  denominazione: z.string(),
  tipologia: z.string(),
  note_degustazione: z.string(),
  condizioni_suggerite: z.string(),
  confidence: z.number().min(0).max(1),
});

export const chatMessageSchema = z.object({
  role: z.enum(["user", "assistant"]),
  content: z.string(),
  at: z.string().optional(),
});

export const sommelierHistorySchema = z.object({
  messages: z.array(chatMessageSchema).default([]),
});

export const sommelierChunkSchema = z.object({
  delta: z.string().optional(),
  error: z.string().optional(),
});

export type ChatMessage = z.infer<typeof chatMessageSchema>;
export type ListingSuggestion = z.infer<typeof listingSuggestionSchema>;
