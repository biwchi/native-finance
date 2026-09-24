import { sql } from "drizzle-orm";
import { check, date, index, integer, numeric, pgTable, timestamp, uuid, varchar } from "drizzle-orm/pg-core";
import { accounts } from "./account.schema.ts";

export const goals = pgTable("goals", {
  id: uuid().defaultRandom().primaryKey(),
  accountId: uuid().notNull().references(() => accounts.id, { onDelete: "cascade" }),
  name: varchar({ length: 120 }).notNull(),
  targetAmount: numeric({ precision: 19, scale: 4 }).notNull(),
  icon: varchar({ length: 80 }).notNull(),
  color: varchar({ length: 20 }).notNull(),
  deadline: date({ mode: "string" }),
  sortOrder: integer().default(0).notNull(),
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index("goals_account_id_idx").on(table.accountId),
  check("goals_positive_target", sql`${table.targetAmount} > 0`),
  check("goals_nonnegative_order", sql`${table.sortOrder} >= 0`),
]);
