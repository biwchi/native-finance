import { and, desc, eq, inArray, sql } from "drizzle-orm";

import type { ExchangeRateRepository } from "../../../application/exchange-rates/exchange-rate.repository.ts";
import { latestRatesByCurrency } from "../../../domain/exchange-rates/exchange-rate.ts";
import type { Database } from "../client.ts";
import { exchangeRates } from "../schema/exchange-rate.schema.ts";

const canonicalBaseCurrency = "USD";
const providerName = "frankfurter";

export function createDrizzleExchangeRateRepository(
  database: Database,
): ExchangeRateRepository {
  return {
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
