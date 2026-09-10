import { t } from "elysia";

export const exchangeRateQuerySchema = t.Object({
  reportingCurrency: t.Optional(t.String({ pattern: "^[A-Za-z]{3}$" })),
  currencies: t.Optional(t.String({
    pattern: "^[A-Za-z]{3}(?:,[A-Za-z]{3})*$",
    maxLength: 399,
  })),
  refresh: t.Optional(t.Union([t.Literal("true"), t.Literal("false")])),
});
