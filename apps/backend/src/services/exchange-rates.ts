import { and, desc, eq, inArray, sql } from "drizzle-orm";

import { config } from "../config.ts";
import { db } from "../db/client.ts";
import { exchangeRates } from "../db/schema.ts";

const canonicalBaseCurrency = "USD";
const providerName = "frankfurter";
const defaultCacheTTL = 60 * 60 * 1_000;

export type StoredExchangeRate = {
  baseCurrency: string;
  quoteCurrency: string;
  rate: string;
  effectiveDate: string;
  provider: string;
  fetchedAt: Date;
};

export type ExchangeRateRepository = {
  findLatest(quoteCurrencies: string[]): Promise<StoredExchangeRate[]>;
  save(rates: StoredExchangeRate[]): Promise<void>;
};

type ProviderExchangeRate = {
  quoteCurrency: string;
  rate: string;
  effectiveDate: string;
};

export type ExchangeRateProvider = (
  quoteCurrencies: string[],
) => Promise<ProviderExchangeRate[]>;

export type ExchangeRateResponse = {
  baseCurrency: string;
  reportingCurrency: string;
  quotes: Array<{
    currency: string;
    rate: string;
    effectiveDate: string;
  }>;
  fetchedAt: Date;
  stale: boolean;
};

export class ExchangeRatesUnavailableError extends Error {
  constructor() {
    super("Exchange rates are temporarily unavailable");
    this.name = "ExchangeRatesUnavailableError";
  }
}

export class ExchangeRateService {
  constructor(
    private readonly repository: ExchangeRateRepository,
    private readonly provider: ExchangeRateProvider,
    private readonly now: () => Date = () => new Date(),
    private readonly cacheTTL = defaultCacheTTL,
  ) {}

  async latest(
    reportingCurrency: string,
    currencies: string[],
    forceRefresh = false,
  ): Promise<ExchangeRateResponse> {
    const reporting = normalizeCurrency(reportingCurrency);
    const requestedCurrencies = uniqueCurrencies([reporting, ...currencies]);
    const providerQuotes = requestedCurrencies.filter(
      (currency) => currency !== canonicalBaseCurrency,
    );

    if (providerQuotes.length === 0) {
      const now = this.now();
      return {
        baseCurrency: canonicalBaseCurrency,
        reportingCurrency: reporting,
        quotes: [usdRate(now)],
        fetchedAt: now,
        stale: false,
      };
    }

    const cached = await this.repository.findLatest(providerQuotes);
    let ratesByCurrency = latestByCurrency(cached);
    let stale = false;
    const now = this.now();
    const needsRefresh = forceRefresh || providerQuotes.some((currency) => {
      const rate = ratesByCurrency.get(currency);
      return !rate || now.getTime() - rate.fetchedAt.getTime() >= this.cacheTTL;
    });

    if (needsRefresh) {
      try {
        const providerRates = await this.provider(providerQuotes);
        const fetchedAt = this.now();
        const storedRates = providerRates.map((rate) => ({
          baseCurrency: canonicalBaseCurrency,
          quoteCurrency: rate.quoteCurrency,
          rate: rate.rate,
          effectiveDate: rate.effectiveDate,
          provider: providerName,
          fetchedAt,
        }));

        if (providerQuotes.some((currency) =>
          !storedRates.some((rate) => rate.quoteCurrency === currency)
        )) {
          throw new ExchangeRatesUnavailableError();
        }

        await this.repository.save(storedRates);
        ratesByCurrency = latestByCurrency([
          ...cached,
          ...storedRates,
        ]);
      } catch (error) {
        if (providerQuotes.some((currency) => !ratesByCurrency.has(currency))) {
          throw new ExchangeRatesUnavailableError();
        }
        stale = true;
      }
    }

    const selectedRates = requestedCurrencies.map((currency) => {
      if (currency === canonicalBaseCurrency) {
        return usdRate(now);
      }
      const rate = ratesByCurrency.get(currency);
      if (!rate) {
        throw new ExchangeRatesUnavailableError();
      }
      return {
        currency,
        rate: rate.rate,
        effectiveDate: rate.effectiveDate,
      };
    });
    const fetchedAt = selectedRates.reduce(
      (oldest, rate) => {
        if (rate.currency === canonicalBaseCurrency) {
          return oldest;
        }
        const fetched = ratesByCurrency.get(rate.currency)?.fetchedAt;
        return fetched && fetched < oldest ? fetched : oldest;
      },
      now,
    );

    return {
      baseCurrency: canonicalBaseCurrency,
      reportingCurrency: reporting,
      quotes: selectedRates,
      fetchedAt,
      stale,
    };
  }
}

export const exchangeRateRepository: ExchangeRateRepository = {
  async findLatest(quoteCurrencies) {
    if (quoteCurrencies.length === 0) {
      return [];
    }

    const rows = await db
      .select()
      .from(exchangeRates)
      .where(
        and(
          eq(exchangeRates.baseCurrency, canonicalBaseCurrency),
          eq(exchangeRates.provider, providerName),
          inArray(exchangeRates.quoteCurrency, quoteCurrencies),
        ),
      )
      .orderBy(
        desc(exchangeRates.effectiveDate),
        desc(exchangeRates.fetchedAt),
      );

    return [...latestByCurrency(rows).values()];
  },

  async save(rates) {
    if (rates.length === 0) {
      return;
    }

    await db
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

export async function fetchFrankfurterRates(
  quoteCurrencies: string[],
): Promise<ProviderExchangeRate[]> {
  const url = new URL("/v2/rates", config.frankfurterBaseUrl);
  url.searchParams.set("base", canonicalBaseCurrency);
  url.searchParams.set("quotes", quoteCurrencies.join(","));

  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) {
    throw new Error(`Frankfurter returned HTTP ${response.status}`);
  }

  const payload: unknown = await response.json();
  if (!Array.isArray(payload)) {
    throw new Error("Frankfurter returned an invalid response");
  }

  const requested = new Set(quoteCurrencies);
  const parsed = payload.flatMap((value): ProviderExchangeRate[] => {
    if (!isRecord(value)) {
      return [];
    }
    const base = typeof value.base === "string" ? value.base.toUpperCase() : "";
    const quote = typeof value.quote === "string" ? value.quote.toUpperCase() : "";
    const date = typeof value.date === "string" ? value.date : "";
    const rate = typeof value.rate === "number" ? value.rate : Number.NaN;
    if (
      base !== canonicalBaseCurrency ||
      !requested.has(quote) ||
      !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
      !Number.isFinite(rate) ||
      rate <= 0
    ) {
      return [];
    }
    return [{
      quoteCurrency: quote,
      rate: rate.toString(),
      effectiveDate: date,
    }];
  });

  if (requested.size !== new Set(parsed.map((rate) => rate.quoteCurrency)).size) {
    throw new Error("Frankfurter did not return every requested currency");
  }
  return parsed;
}

export const exchangeRateService = new ExchangeRateService(
  exchangeRateRepository,
  fetchFrankfurterRates,
);

function latestByCurrency(
  rates: StoredExchangeRate[],
): Map<string, StoredExchangeRate> {
  const latest = new Map<string, StoredExchangeRate>();
  for (const rate of rates) {
    const existing = latest.get(rate.quoteCurrency);
    if (
      !existing ||
      rate.effectiveDate > existing.effectiveDate ||
      (rate.effectiveDate === existing.effectiveDate && rate.fetchedAt > existing.fetchedAt)
    ) {
      latest.set(rate.quoteCurrency, rate);
    }
  }
  return latest;
}

function uniqueCurrencies(currencies: string[]): string[] {
  return [...new Set(currencies.map(normalizeCurrency))].sort();
}

function normalizeCurrency(currency: string): string {
  return currency.trim().toUpperCase();
}

function usdRate(date: Date) {
  return {
    currency: canonicalBaseCurrency,
    rate: "1",
    effectiveDate: date.toISOString().slice(0, 10),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
