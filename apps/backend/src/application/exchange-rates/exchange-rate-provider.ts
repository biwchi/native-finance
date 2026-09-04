import type { ProviderExchangeRate } from "../../domain/exchange-rates/exchange-rate.ts";

export type ExchangeRateProvider = (
  quoteCurrencies: string[],
) => Promise<ProviderExchangeRate[]>;
