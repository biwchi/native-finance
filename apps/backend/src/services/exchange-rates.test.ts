import { describe, expect, it } from "bun:test";

import {
  ExchangeRateService,
  ExchangeRatesUnavailableError,
  type ExchangeRateRepository,
  type StoredExchangeRate,
} from "./exchange-rates.ts";

class MemoryRateRepository implements ExchangeRateRepository {
  rates: StoredExchangeRate[] = [];

  async findLatest(quoteCurrencies: string[]) {
    return this.rates.filter((rate) => quoteCurrencies.includes(rate.quoteCurrency));
  }

  async save(rates: StoredExchangeRate[]) {
    this.rates.push(...rates);
  }
}

describe("ExchangeRateService", () => {
  const now = new Date("2026-09-02T12:00:00Z");

  it("fetches and returns canonical USD quotes for conversion", async () => {
    const repository = new MemoryRateRepository();
    const service = new ExchangeRateService(
      repository,
      async (currencies) => {
        expect(currencies).toEqual(["EUR", "KZT"]);
        return [
          { quoteCurrency: "EUR", rate: "0.86", effectiveDate: "2026-09-02" },
          { quoteCurrency: "KZT", rate: "540.12", effectiveDate: "2026-09-02" },
        ];
      },
      () => now,
    );

    const result = await service.latest("kzt", ["EUR", "USD"]);

    expect(result).toEqual({
      baseCurrency: "USD",
      reportingCurrency: "KZT",
      quotes: [
        { currency: "EUR", rate: "0.86", effectiveDate: "2026-09-02" },
        { currency: "KZT", rate: "540.12", effectiveDate: "2026-09-02" },
        { currency: "USD", rate: "1", effectiveDate: "2026-09-02" },
      ],
      fetchedAt: now,
      stale: false,
    });
    expect(repository.rates).toHaveLength(2);
  });

  it("uses a fresh cached snapshot without calling Frankfurter", async () => {
    const repository = new MemoryRateRepository();
    repository.rates = [storedRate("EUR", "0.86", now)];
    let providerCalls = 0;
    const service = new ExchangeRateService(
      repository,
      async () => {
        providerCalls += 1;
        return [];
      },
      () => now,
    );

    const result = await service.latest("EUR", ["USD"]);

    expect(providerCalls).toBe(0);
    expect(result.stale).toBe(false);
    expect(result.quotes.find((quote) => quote.currency === "EUR")?.rate).toBe("0.86");
  });

  it("falls back to an expired snapshot when Frankfurter is down", async () => {
    const repository = new MemoryRateRepository();
    repository.rates = [
      storedRate("KZT", "537.5", new Date("2026-09-02T09:00:00Z")),
    ];
    const service = new ExchangeRateService(
      repository,
      async () => { throw new Error("offline"); },
      () => now,
    );

    const result = await service.latest("KZT", ["USD"]);

    expect(result.stale).toBe(true);
    expect(result.fetchedAt).toEqual(new Date("2026-09-02T09:00:00Z"));
  });

  it("fails when a required rate has never been cached", async () => {
    const service = new ExchangeRateService(
      new MemoryRateRepository(),
      async () => { throw new Error("offline"); },
      () => now,
    );

    expect(service.latest("KZT", ["EUR"])).rejects.toBeInstanceOf(
      ExchangeRatesUnavailableError,
    );
  });
});

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
