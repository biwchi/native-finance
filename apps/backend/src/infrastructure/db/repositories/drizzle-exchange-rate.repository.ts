import { and, desc, eq, inArray, sql } from "drizzle-orm";

import type { ExchangeRateRepository } from "../../../application/exchange-rates/exchange-rate.repository.ts";
import { latestRatesByCurrency } from "../../../domain/exchange-rates/exchange-rate.ts";
import type { Database } from "../client.ts";
import { exchangeRates } from "../schema/exchange-rate.schema.ts";
import { exchangeRateRefreshes } from "../schema/sync.schema.ts";

const canonicalBaseCurrency = "USD";
const providerName = "frankfurter";

export function createDrizzleExchangeRateRepository(
  database: Database,
): ExchangeRateRepository {
  return {
    async findAllLatest() {
      return database.selectDistinctOn([exchangeRates.quoteCurrency]).from(exchangeRates)
        .where(and(eq(exchangeRates.baseCurrency, canonicalBaseCurrency), eq(exchangeRates.provider, providerName)))
        .orderBy(exchangeRates.quoteCurrency, desc(exchangeRates.effectiveDate), desc(exchangeRates.fetchedAt));
    },
    async lastFullRefresh() {
      const [row] = await database.select().from(exchangeRateRefreshes).where(eq(exchangeRateRefreshes.key, "USD:frankfurter"));
      return row?.fetchedAt ?? null;
    },
    async saveFullSnapshot(rates, fetchedAt) {
      await database.transaction(async (tx) => {
        await tx.insert(exchangeRates).values(rates).onConflictDoUpdate({
          target: [exchangeRates.baseCurrency, exchangeRates.quoteCurrency, exchangeRates.effectiveDate, exchangeRates.provider],
          set: { rate: sql`excluded.rate`, fetchedAt: sql`excluded.fetched_at` },
        });
        await tx.insert(exchangeRateRefreshes).values({ key: "USD:frankfurter", fetchedAt }).onConflictDoUpdate({ target: exchangeRateRefreshes.key, set: { fetchedAt } });
      });
    },
    async findLatest(quoteCurrencies) {
      if (quoteCurrencies.length === 0) return [];
      const rows = await database
        .select()
        .from(exchangeRates)
        .where(and(
          eq(exchangeRates.baseCurrency, canonicalBaseCurrency),
          eq(exchangeRates.provider, providerName),
          inArray(exchangeRates.quoteCurrency, quoteCurrencies),
        ))
        .orderBy(desc(exchangeRates.effectiveDate), desc(exchangeRates.fetchedAt));
      return [...latestRatesByCurrency(rows).values()];
    },

    async save(rates) {
      if (rates.length === 0) return;
      await database
        .insert(exchangeRates)
        .values(rates)
        .onConflictDoUpdate({
          target: [
            exchangeRates.baseCurrency,
            exchangeRates.quoteCurrency,
            exchangeRates.effectiveDate,
            exchangeRates.provider,
          ],
          set: {
            rate: sql`excluded.rate`,
            fetchedAt: sql`excluded.fetched_at`,
          },
        });
    },
  };
}
