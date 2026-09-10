import { describe, expect, it } from "bun:test";

import {
  convertExchangeAmount,
  type StoredExchangeRate,
} from "../../domain/exchange-rates/exchange-rate.ts";
import type { ExchangeRateRepository } from "./exchange-rate.repository.ts";
import { getLatestExchangeRates } from "./get-latest-exchange-rates.ts";

describe("getLatestExchangeRates", () => {
  const now = new Date("2026-09-02T12:00:00Z");

  it("fetches and returns canonical USD quotes for conversion", async () => {
    const memory = createMemoryRepository();
    const result = await getLatestExchangeRates({
      reportingCurrency: "kzt",
      currencies: ["EUR", "USD"],
    }, {
      repository: memory.repository,
      provider: async (currencies) => {
        expect(currencies).toEqual(["EUR", "KZT"]);
        return [
          { quoteCurrency: "EUR", rate: "0.86", effectiveDate: "2026-09-02" },
          { quoteCurrency: "KZT", rate: "540.12", effectiveDate: "2026-09-02" },
        ];
      },
      now: () => now,
    });

    expect(result).toEqual({
      ok: true,
      value: {
        baseCurrency: "USD",
        reportingCurrency: "KZT",
        quotes: [
          { currency: "EUR", rate: "0.86", effectiveDate: "2026-09-02" },
          { currency: "KZT", rate: "540.12", effectiveDate: "2026-09-02" },
          { currency: "USD", rate: "1", effectiveDate: "2026-09-02" },
        ],
        fetchedAt: now,
        stale: false,
      },
    });
    expect(memory.rates).toHaveLength(2);
  });

  it("uses a fresh cached snapshot without calling Frankfurter", async () => {
    const memory = createMemoryRepository([storedRate("EUR", "0.86", now)]);
    let providerCalls = 0;
    const result = await getLatestExchangeRates({
      reportingCurrency: "EUR",
      currencies: ["USD"],
    }, {
      repository: memory.repository,
      provider: async () => {
        providerCalls += 1;
        return [];
      },
      now: () => now,
    });

    expect(providerCalls).toBe(0);
    expect(result.ok).toBeTrue();
    if (!result.ok) return;
    expect(result.value.stale).toBe(false);
    expect(result.value.quotes.find((quote) => quote.currency === "EUR")?.rate).toBe("0.86");
  });

  it("falls back to an expired snapshot when Frankfurter is down", async () => {
    const memory = createMemoryRepository([
      storedRate("KZT", "537.5", new Date("2026-09-01T09:00:00Z")),
    ]);
    const result = await getLatestExchangeRates({
      reportingCurrency: "KZT",
      currencies: ["USD"],
    }, {
      repository: memory.repository,
      provider: async () => { throw new Error("offline"); },
      now: () => now,
    });

    expect(result.ok).toBeTrue();
    if (!result.ok) return;
    expect(result.value.stale).toBe(true);
    expect(result.value.fetchedAt).toEqual(new Date("2026-09-01T09:00:00Z"));
  });

  it("fails when a required rate has never been cached", async () => {
    const memory = createMemoryRepository();
    const result = await getLatestExchangeRates({
      reportingCurrency: "KZT",
      currencies: ["EUR"],
    }, {
      repository: memory.repository,
      provider: async () => { throw new Error("offline"); },
      now: () => now,
    });

    expect(result).toEqual({
      ok: false,
      error: {
        code: "exchange_rates_unavailable",
        message: "Exchange rates are temporarily unavailable",
      },
    });
  });
});

describe("convertExchangeAmount", () => {
  it("converts between two canonical USD quotes and rounds to four decimals", () => {
    const converted = convertExchangeAmount("4", "USD", "KZT", {
      baseCurrency: "USD",
      reportingCurrency: "KZT",
      fetchedAt: new Date("2026-09-02T12:00:00Z"),
      stale: false,
      quotes: [
        { currency: "USD", rate: "1", effectiveDate: "2026-09-02" },
        { currency: "KZT", rate: "540.12345", effectiveDate: "2026-09-02" },
      ],
    });

    expect(converted).toEqual({
      amount: "2160.4938",
      rate: "540.12345",
      effectiveDate: "2026-09-02",
    });
  });
});

function createMemoryRepository(initial: StoredExchangeRate[] = []): {
  rates: StoredExchangeRate[];
  repository: ExchangeRateRepository;
} {
  const rates = [...initial];
  return {
    rates,
    repository: {
      async findLatest(quoteCurrencies) {
        return rates.filter((rate) => quoteCurrencies.includes(rate.quoteCurrency));
      },
      async save(newRates) {
        rates.push(...newRates);
      },
    },
  };
}

function storedRate(
  quoteCurrency: string,
  rate: string,
  fetchedAt: Date,
): StoredExchangeRate {
  return {
    baseCurrency: "USD",
    quoteCurrency,
    rate,
    effectiveDate: "2026-09-02",
    provider: "frankfurter",
    fetchedAt,
  };
}

describe("complete daily rate table", () => {
  it("coalesces concurrent callers and ignores force refresh within 24 hours", async () => {
    const memory = fullMemoryRepository(); let calls = 0; let clock = new Date("2026-09-02T12:00:00Z");
    const dependencies = { repository: memory.repository, now: () => clock, provider: async (currencies: string[]) => {
      calls += 1; expect(currencies).toEqual([]); await new Promise(r => setTimeout(r, 10));
      return [{ quoteCurrency: "EUR", rate: "0.8", effectiveDate: "2026-09-02" }, { quoteCurrency: "KZT", rate: "500", effectiveDate: "2026-09-02" }];
    } };
    const results = await Promise.all(Array.from({ length: 20 }, () => getLatestExchangeRates({ reportingCurrency: "USD", currencies: [] }, dependencies)));
    expect(calls).toBe(1); expect(results.every(r => r.ok && r.value.quotes.length === 3)).toBe(true);
    clock = new Date(clock.getTime() + 86399_000);
    const filtered = await getLatestExchangeRates({ reportingCurrency: "KZT", currencies: ["EUR"], forceRefresh: true }, dependencies);
    expect(calls).toBe(1); expect(filtered.ok).toBe(true);
    clock = new Date(clock.getTime() + 1000);
    await getLatestExchangeRates({ reportingCurrency: "USD", currencies: [] }, dependencies);
    expect(calls).toBe(2);
  });
  it("keeps dates and cached conversions when provider fails, but never invents missing rates", async () => {
    const fetchedAt = new Date("2026-09-01T00:00:00Z"); const memory = fullMemoryRepository([storedRate("EUR", "0.8", fetchedAt)], fetchedAt);
    const dependencies = { repository: memory.repository, now: () => new Date("2026-09-03T00:00:00Z"), provider: async () => { throw new Error("offline"); } };
    const result = await getLatestExchangeRates({ reportingCurrency: "USD", currencies: [] }, dependencies);
    expect(result.ok).toBe(true);
    if (result.ok) { expect(result.value.stale).toBe(true); expect(result.value.fetchedAt).toEqual(fetchedAt); expect(convertExchangeAmount("100", "EUR", "USD", result.value)?.amount).toBe("125"); }
    expect(await memory.repository.lastFullRefresh!()).toEqual(fetchedAt);
    const missing = await getLatestExchangeRates({ reportingCurrency: "JPY", currencies: ["EUR"] }, dependencies);
    expect(missing.ok).toBe(false);
  });
});
function fullMemoryRepository(initial: StoredExchangeRate[] = [], initialRefresh: Date | null = null) {
  let rates = initial; let refreshed = initialRefresh;
  const repository: ExchangeRateRepository = {
    async findLatest(currencies) { return rates.filter(r => currencies.includes(r.quoteCurrency)); },
    async save(values) { rates = values; },
    async findAllLatest() { return rates; },
    async lastFullRefresh() { return refreshed; },
    async saveFullSnapshot(values, date) { rates = values; refreshed = date; },
  };
  return { repository };
}
