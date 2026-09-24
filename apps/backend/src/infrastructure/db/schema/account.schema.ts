import { integer, numeric, pgTable, timestamp, uuid, varchar } from "drizzle-orm/pg-core";


export const accounts = pgTable("accounts", {
  id: uuid().defaultRandom().primaryKey(),
  name: varchar({ length: 120 }).notNull(),
  initialBalance: numeric({ precision: 19, scale: 4 }).default("0").notNull(),
  currency: varchar({ length: 3 }).notNull(),
  icon: varchar({ length: 80 }).default("creditcard.fill").notNull(),
  iconColor: varchar({ length: 20 }).default("blue").notNull(),
  sortOrder: integer().default(1_000).notNull(),
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
});
