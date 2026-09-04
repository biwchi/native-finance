import { sql } from "drizzle-orm";
import {
  check,
  date,
  index,
  numeric,
  pgTable,
  primaryKey,
  timestamp,
  varchar,
} from "drizzle-orm/pg-core";

export const exchangeRates = pgTable(
  "exchange_rates",
  {
    baseCurrency: varchar({ length: 3 }).notNull(),
    quoteCurrency: varchar({ length: 3 }).notNull(),
    rate: numeric({ precision: 30, scale: 15 }).notNull(),
    effectiveDate: date({ mode: "string" }).notNull(),
    provider: varchar({ length: 40 }).default("frankfurter").notNull(),
    fetchedAt: timestamp({ withTimezone: true }).notNull(),
  },
  (table) => [
    primaryKey({
      name: "exchange_rates_base_quote_date_provider_pk",
      columns: [
        table.baseCurrency,
        table.quoteCurrency,
        table.effectiveDate,
        table.provider,
      ],
    }),
    index("exchange_rates_latest_idx").on(
      table.baseCurrency,
      table.quoteCurrency,
      table.effectiveDate,
    ),
    check("exchange_rates_rate_positive", sql`${table.rate} > 0`),
  ],
);
