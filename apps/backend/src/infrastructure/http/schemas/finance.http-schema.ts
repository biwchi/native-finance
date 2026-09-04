import { t } from "elysia";

export const transactionKindSchema = t.Union([
  t.Literal("expense"),
  t.Literal("income"),
]);

export const amountSchema = t.String({
  pattern: "^(?=.{1,20}$)(?!0+(?:\\.0{1,4})?$)(?:0|[1-9]\\d{0,14})(?:\\.\\d{1,4})?$",
});
