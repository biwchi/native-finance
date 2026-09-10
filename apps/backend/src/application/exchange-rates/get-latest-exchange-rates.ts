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
const defaultCacheTtl = 24 * 60 * 60 * 1_000;
const refreshes = new WeakMap<ExchangeRateRepository, Promise<void>>();

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

  if (input.currencies.length && providerQuotes.length === 0) {
    const currentTime = now();
    return ok({ baseCurrency: canonicalBaseCurrency, reportingCurrency: reporting, quotes: [createUsdRate(currentTime)], fetchedAt: currentTime, stale: false });
  }

  if (dependencies.repository.findAllLatest && dependencies.repository.lastFullRefresh && dependencies.repository.saveFullSnapshot) {
    const repository = dependencies.repository;
    const refreshed = await repository.lastFullRefresh!();
    let stale = false;
    if (!refreshed || now().getTime() - refreshed.getTime() >= cacheTtl) {
      let refresh = refreshes.get(repository);
      if (!refresh) {
        refresh = (async () => {
          // A concurrent caller may have finished between the first read and entering this request.
          const latest = await repository.lastFullRefresh!();
          if (latest && now().getTime() - latest.getTime() < cacheTtl) return;
          const rates = await dependencies.provider([]);
          if (!rates.length) throw new Error("No exchange rates returned");
          const fetchedAt = now();
          await repository.saveFullSnapshot!(rates.map((rate) => ({ ...rate, baseCurrency: canonicalBaseCurrency, provider: providerName, fetchedAt })), fetchedAt);
        })();
        refreshes.set(repository, refresh);
      }
      try { await refresh; } catch { stale = true; }
      finally { if (refreshes.get(repository) === refresh) refreshes.delete(repository); }
    }
    const cached = await repository.findAllLatest!();
    const all = latestRatesByCurrency(cached);
    const quotes = [createUsdRate(now()), ...[...all.values()].filter((r) => r.quoteCurrency !== "USD").map((r) => ({ currency: r.quoteCurrency, rate: r.rate, effectiveDate: r.effectiveDate }))];
    if (!cached.length || requestedCurrencies.some((c) => !quotes.some((r) => r.currency === c))) return error("exchange_rates_unavailable", "Exchange rates are temporarily unavailable");
    return ok({ baseCurrency: canonicalBaseCurrency, reportingCurrency: reporting, quotes: input.currencies.length ? quotes.filter((r) => requestedCurrencies.includes(r.currency)) : quotes, fetchedAt: await repository.lastFullRefresh!() ?? cached.reduce((oldest, r) => r.fetchedAt < oldest ? r.fetchedAt : oldest, now()), stale });
  }

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
  const needsRefresh = providerQuotes.some((currency) => {
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
