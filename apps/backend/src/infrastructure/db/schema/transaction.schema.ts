import { sql } from "drizzle-orm";
import {
  index,
  numeric,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
  varchar,
} from "drizzle-orm/pg-core";

import { accounts } from "./account.schema.ts";
import { categories } from "./category.schema.ts";
import { transactionKind } from "./enums.schema.ts";
import { recurringSchedules } from "./recurring-schedule.schema.ts";

export const transactions = pgTable(
  "transactions",
  {
    id: uuid().defaultRandom().primaryKey(),
    accountId: uuid().notNull().references(() => accounts.id, {
      onDelete: "cascade",
    }),
    kind: transactionKind().notNull(),
    amount: numeric({ precision: 19, scale: 4 }).notNull(),
    currency: varchar({ length: 3 }).notNull(),
    categoryId: uuid().references(() => categories.id, {
      onDelete: "set null",
    }),
    recurringScheduleId: uuid().references(() => recurringSchedules.id, {
      onDelete: "set null",
    }),
    merchant: text(),
    payee: text(),
    note: text(),
    occurredAt: timestamp({ withTimezone: true }).notNull(),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [
    index("transactions_account_id_idx").on(table.accountId),
    index("transactions_category_id_idx").on(table.categoryId),
    index("transactions_recurring_schedule_id_idx").on(
      table.recurringScheduleId,
    ),
    uniqueIndex("transactions_schedule_occurrence_unique")
      .on(table.recurringScheduleId, table.occurredAt)
      .where(sql`${table.recurringScheduleId} is not null`),
    index("transactions_occurred_at_idx").on(table.occurredAt),
  ],
);
