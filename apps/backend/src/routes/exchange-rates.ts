import { Elysia, t } from "elysia";

import {
  type ExchangeRateService,
  ExchangeRatesUnavailableError,
  exchangeRateService,
} from "../services/exchange-rates.ts";

const currencyPattern = "^[A-Za-z]{3}$";
const currencyListPattern = "^[A-Za-z]{3}(?:,[A-Za-z]{3})*$";

export function createExchangeRatesRoutes(service: ExchangeRateService) {
  return new Elysia({ prefix: "/exchange-rates" })
    .get(
      "/latest",
      async ({ query, set }) => {
        try {
          return await service.latest(
            query.reportingCurrency,
            query.currencies.split(","),
            query.refresh === "true",
          );
        } catch (error) {
          if (error instanceof ExchangeRatesUnavailableError) {
            set.status = 503;
            return { message: error.message };
          }
          throw error;
        }
      },
      {
        query: t.Object({
          reportingCurrency: t.String({ pattern: currencyPattern }),
          currencies: t.String({ pattern: currencyListPattern, maxLength: 399 }),
          refresh: t.Optional(t.Union([t.Literal("true"), t.Literal("false")])),
        }),
      },
    );
}

export const exchangeRatesRoutes = createExchangeRatesRoutes(exchangeRateService);
