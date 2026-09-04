import { t } from "elysia";

import { amountSchema, transactionKindSchema } from "./finance.http-schema.ts";

const recurrenceFrequencySchema = t.Union([
  t.Literal("daily"),
  t.Literal("weekly"),
  t.Literal("monthly"),
  t.Literal("yearly"),
]);

const recurrenceBodySchema = t.Object({
  frequency: recurrenceFrequencySchema,
  endAt: t.Optional(t.Nullable(t.String({ format: "date-time" }))),
});

export const recurringDeletionActionSchema = t.Union([
  t.Literal("occurrence"),
  t.Literal("stopRepeating"),
  t.Literal("occurrenceAndFuture"),
]);

export const transactionBodySchema = t.Object({
  accountId: t.String({ format: "uuid" }),
  kind: transactionKindSchema,
  amount: amountSchema,
  categoryId: t.Optional(t.Nullable(t.String({ format: "uuid" }))),
  merchant: t.Optional(t.Nullable(t.String({ maxLength: 500 }))),
  payee: t.Optional(t.Nullable(t.String({ maxLength: 500 }))),
  note: t.Optional(t.Nullable(t.String({ maxLength: 2_000 }))),
  recurrence: t.Optional(t.Nullable(recurrenceBodySchema)),
  occurredAt: t.String({ format: "date-time" }),
});

export const transferBodySchema = t.Object({
  fromAccountId: t.String({ format: "uuid" }),
  toAccountId: t.String({ format: "uuid" }),
  amount: amountSchema,
  merchant: t.Optional(t.Nullable(t.String({ maxLength: 500 }))),
  payee: t.Optional(t.Nullable(t.String({ maxLength: 500 }))),
  note: t.Optional(t.Nullable(t.String({ maxLength: 2_000 }))),
  occurredAt: t.String({ format: "date-time" }),
});

export const transactionBatchBodySchema = t.Object({
  transactions: t.Array(t.Union([
    t.Object({
      type: t.Literal("transaction"),
      transaction: transactionBodySchema,
    }),
    t.Object({
      type: t.Literal("transfer"),
      transfer: transferBodySchema,
    }),
  ]), { minItems: 1, maxItems: 100 }),
});

export const transactionIdParamsSchema = t.Object({
  id: t.String({ format: "uuid" }),
});
