import { sql } from "drizzle-orm";
import {
  check,
  index,
  numeric,
  pgTable,
  text,
  timestamp,
  uuid,
  varchar,
} from "drizzle-orm/pg-core";

import { accounts } from "./account.schema.ts";
import { categories } from "./category.schema.ts";
import { recurrenceFrequency, transactionKind } from "./enums.schema.ts";

export const recurringSchedules = pgTable(
  "recurring_schedules",
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
    merchant: text(),
    payee: text(),
    note: text(),
    frequency: recurrenceFrequency().notNull(),
    startAt: timestamp({ withTimezone: true }).notNull(),
    lastOccurrenceAt: timestamp({ withTimezone: true }).notNull(),
    nextOccurrenceAt: timestamp({ withTimezone: true }),
    endAt: timestamp({ withTimezone: true }),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [
    index("recurring_schedules_next_occurrence_at_idx").on(
      table.nextOccurrenceAt,
    ),
    check(
      "recurring_schedules_end_after_start",
      sql`${table.endAt} is null or ${table.endAt} >= ${table.startAt}`,
    ),
  ],
);
