import { Elysia } from "elysia";

import type { ExchangeRateResponse } from "../../../domain/exchange-rates/exchange-rate.ts";
import type { Result } from "../../../domain/shared/result.ts";
import { exchangeRateQuerySchema } from "../schemas/exchange-rate.http-schema.ts";

export type ExchangeRateController = {
  latest(input: {
    reportingCurrency: string;
    currencies: string[];
    forceRefresh: boolean;
  }): Promise<Result<ExchangeRateResponse, string>>;
};

export function createExchangeRatesRouter(controller: ExchangeRateController) {
  return new Elysia({ prefix: "/exchange-rates" })
    .get("/latest", async ({ query, set }) => {
      const result = await controller.latest({
        reportingCurrency: query.reportingCurrency,
        currencies: query.currencies.split(","),
        forceRefresh: query.refresh === "true",
      });
      if (!result.ok) {
        set.status = 503;
        return { message: result.error.message };
      }
      return result.value;
    }, { query: exchangeRateQuerySchema });
}
