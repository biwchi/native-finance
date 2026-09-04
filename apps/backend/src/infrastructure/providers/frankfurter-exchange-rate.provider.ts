import type { ExchangeRateProvider } from "../../application/exchange-rates/exchange-rate-provider.ts";
import type { ProviderExchangeRate } from "../../domain/exchange-rates/exchange-rate.ts";

const canonicalBaseCurrency = "USD";

export function createFrankfurterExchangeRateProvider(
  baseUrl: string,
  request: typeof fetch = fetch,
): ExchangeRateProvider {
  return async (quoteCurrencies) => {
    const url = new URL("/v2/rates", baseUrl);
    url.searchParams.set("base", canonicalBaseCurrency);
    url.searchParams.set("quotes", quoteCurrencies.join(","));

    const response = await request(url, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error(`Frankfurter returned HTTP ${response.status}`);

    const payload: unknown = await response.json();
    if (!Array.isArray(payload)) throw new Error("Frankfurter returned an invalid response");

    const requested = new Set(quoteCurrencies);
    const parsed = payload.flatMap((value): ProviderExchangeRate[] => {
      if (!isRecord(value)) return [];
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
      return [{ quoteCurrency: quote, rate: rate.toString(), effectiveDate: date }];
    });

    if (requested.size !== new Set(parsed.map((rate) => rate.quoteCurrency)).size) {
      throw new Error("Frankfurter did not return every requested currency");
    }
    return parsed;
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
