import type { StoredExchangeRate } from "../../domain/exchange-rates/exchange-rate.ts";

export interface ExchangeRateRepository {
  findLatest(quoteCurrencies: string[]): Promise<StoredExchangeRate[]>;
  save(rates: StoredExchangeRate[]): Promise<void>;
  findAllLatest?(): Promise<StoredExchangeRate[]>;
  lastFullRefresh?(): Promise<Date | null>;
  saveFullSnapshot?(rates: StoredExchangeRate[], fetchedAt: Date): Promise<void>;
}
