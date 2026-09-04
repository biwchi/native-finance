import type {
  ExchangeRateResponse,
} from "../../domain/exchange-rates/exchange-rate.ts";
import {
  createUsdRate,
  latestRatesByCurrency,
  normalizeCurrency,
  uniqueCurrencies,
} from "../../domain/exchange-rates/exchange-rate.ts";
import { error, ok, type Result } from "../../domain/shared/result.ts";
import type { ExchangeRateProvider } from "./exchange-rate-provider.ts";
import type { ExchangeRateRepository } from "./exchange-rate.repository.ts";

const canonicalBaseCurrency = "USD";
const providerName = "frankfurter";
const defaultCacheTtl = 60 * 60 * 1_000;

export async function getLatestExchangeRates(
  input: {
    reportingCurrency: string;
    currencies: string[];
    forceRefresh?: boolean;
  },
  dependencies: {
    repository: ExchangeRateRepository;
    provider: ExchangeRateProvider;
    now?: () => Date;
    cacheTtl?: number;
  },
): Promise<Result<ExchangeRateResponse, "exchange_rates_unavailable">> {
  const now = dependencies.now ?? (() => new Date());
  const cacheTtl = dependencies.cacheTtl ?? defaultCacheTtl;
  const reporting = normalizeCurrency(input.reportingCurrency);
  const requestedCurrencies = uniqueCurrencies([reporting, ...input.currencies]);
  const providerQuotes = requestedCurrencies.filter(
    (currency) => currency !== canonicalBaseCurrency,
  );

  if (providerQuotes.length === 0) {
    const currentTime = now();
    return ok({
      baseCurrency: canonicalBaseCurrency,
      reportingCurrency: reporting,
      quotes: [createUsdRate(currentTime)],
      fetchedAt: currentTime,
      stale: false,
    });
  }

  const cached = await dependencies.repository.findLatest(providerQuotes);
  let ratesByCurrency = latestRatesByCurrency(cached);
  let stale = false;
  const currentTime = now();
  const needsRefresh = input.forceRefresh || providerQuotes.some((currency) => {
    const rate = ratesByCurrency.get(currency);
    return !rate || currentTime.getTime() - rate.fetchedAt.getTime() >= cacheTtl;
  });

  if (needsRefresh) {
    try {
      const providerRates = await dependencies.provider(providerQuotes);
      const fetchedAt = now();
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
        throw new Error("Provider omitted a requested exchange rate");
      }
      await dependencies.repository.save(storedRates);
      ratesByCurrency = latestRatesByCurrency([...cached, ...storedRates]);
    } catch {
      if (providerQuotes.some((currency) => !ratesByCurrency.has(currency))) {
        return error(
          "exchange_rates_unavailable",
          "Exchange rates are temporarily unavailable",
        );
      }
      stale = true;
    }
  }

  const selectedRates = requestedCurrencies.map((currency) => {
    if (currency === canonicalBaseCurrency) return createUsdRate(currentTime);
    const rate = ratesByCurrency.get(currency);
    return rate
      ? { currency, rate: rate.rate, effectiveDate: rate.effectiveDate }
      : null;
  });
  if (selectedRates.some((rate) => rate === null)) {
    return error(
      "exchange_rates_unavailable",
      "Exchange rates are temporarily unavailable",
    );
  }

  const fetchedAt = selectedRates.reduce((oldest, rate) => {
    if (!rate || rate.currency === canonicalBaseCurrency) return oldest;
    const fetched = ratesByCurrency.get(rate.currency)?.fetchedAt;
    return fetched && fetched < oldest ? fetched : oldest;
  }, currentTime);

  return ok({
    baseCurrency: canonicalBaseCurrency,
    reportingCurrency: reporting,
    quotes: selectedRates.filter((rate) => rate !== null),
    fetchedAt,
    stale,
  });
}
