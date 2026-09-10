import { bigint, integer, jsonb, pgTable, primaryKey, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";

export const syncWorkspace = pgTable("sync_workspace", {
  id: integer().primaryKey().default(1),
  workspaceId: uuid().defaultRandom().notNull(),
  generation: integer().default(1).notNull(),
  revision: bigint({ mode: "bigint" }).default(sql`0`).notNull(),
});

export const syncRecords = pgTable("sync_records", {
  entity: text().notNull(),
  key: text().notNull(),
  version: bigint({ mode: "bigint" }).notNull(),
  data: jsonb().$type<Record<string, unknown>>(),
}, (table) => [primaryKey({ columns: [table.entity, table.key] })]);

export const syncChanges = pgTable("sync_changes", {
  revision: bigint({ mode: "bigint" }).notNull(),
  entity: text().notNull(),
  key: text().notNull(),
  version: bigint({ mode: "bigint" }).notNull(),
  data: jsonb().$type<Record<string, unknown>>(),
}, (table) => [primaryKey({ columns: [table.revision, table.entity, table.key] })]);

export const syncReceipts = pgTable("sync_receipts", {
  clientId: uuid().notNull(),
  mutationId: uuid().notNull(),
  digest: text().notNull(),
  response: jsonb().notNull(),
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
}, (table) => [primaryKey({ columns: [table.clientId, table.mutationId] })]);

// Exceptions outlive deleted transactions, preventing recurrence regeneration.
export const recurrenceExclusions = pgTable("recurrence_exclusions", {
  id: uuid().primaryKey(),
  scheduleId: uuid().notNull(),
  scheduledFor: timestamp({ withTimezone: true }).notNull(),
});

export const exchangeRateRefreshes = pgTable("exchange_rate_refreshes", {
  key: text().primaryKey(),
  fetchedAt: timestamp({ withTimezone: true }).notNull(),
});
