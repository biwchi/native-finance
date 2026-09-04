import { integer, pgTable, timestamp, uuid, varchar } from "drizzle-orm/pg-core";

import { accountType } from "./enums.schema.ts";

export const accounts = pgTable("accounts", {
  id: uuid().defaultRandom().primaryKey(),
  name: varchar({ length: 120 }).notNull(),
  type: accountType().notNull(),
  currency: varchar({ length: 3 }).notNull(),
  icon: varchar({ length: 80 }).default("creditcard.fill").notNull(),
  iconColor: varchar({ length: 20 }).default("blue").notNull(),
  sortOrder: integer().default(1_000).notNull(),
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
});
