import { Type as t, type TSchema } from "@sinclair/typebox";
import type { QuickEntryInterpreterInput } from "../../../application/quick-entry/quick-entry-interpreter.ts";
import { quickEntryDraftLimitFor } from "../../../application/quick-entry/quick-entry-interpreter.ts";

const closed = { additionalProperties: false } as const;
// Use JSON Schema types, not Elysia's HTTP coercion types (e.g. format: "integer").
const nullable = <T extends TSchema>(schema: T) => t.Union([schema, t.Null()]);
const enumValues = <const T extends string>(values: readonly T[]) => t.Union(values.map((value) => t.Literal(value)));
const source = () => t.String({ maxLength: 2_000 });
const text = (maxLength = 500) => nullable(t.String({ maxLength }));
const unit = () => enumValues(["day", "week", "month", "year"]);
const date = () => nullable(t.Object({
  calendarDate: nullable(t.Object({
    year: nullable(t.Integer({ minimum: 1900, maximum: 9999 })),
    month: t.Integer({ minimum: 1, maximum: 12 }),
    day: t.Integer({ minimum: 1, maximum: 31 }),
  }, closed)),
  relative: nullable(t.Object({ unit: unit(), value: t.Integer({ minimum: -10_000, maximum: 10_000 }) }, closed)),
  weekday: nullable(t.Object({ day: t.Integer({ minimum: 1, maximum: 7 }), relation: enumValues(["last", "this", "next"]) }, closed)),
  time: nullable(t.String({ pattern: "^(?:[01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d$" })),
}, closed));

export function extractionSchema(input: QuickEntryInterpreterInput) {
  const accountIds = input.accounts.map((a) => a.id);
  const account = () => accountIds.length ? nullable(enumValues(accountIds)) : t.Null();
  const categoryIds = input.categories.filter((c) => c.kind !== "debt").map((c) => c.id);
  return t.Object({
    ...(input.document ? { hasMoreTransactions: t.Boolean() } : {}),
    transactions: t.Array(t.Object({
      location: t.String({ maxLength: 300 }),
      documentType: enumValues(["text", "receipt", "transaction_record", "transaction_history", "product_offer", "invoice", "other"]),
      status: enumValues(["completed", "pending", "canceled", "reversed", "offer", "unknown"]),
      kind: nullable(enumValues(["expense", "income", "transfer"])),
      account: t.Object({ id: account(), basis: enumValues(["selected", "user", "unresolved"]), source: text() }, closed),
      destinationAccountId: account(),
      destinationAccountSource: text(),
      amounts: t.Array(t.Object({
        value: t.String({ pattern: "^(?:[1-9]\\d{0,14}(?:\\.\\d{1,4})?|0\\.(?:[1-9]\\d{0,3}|0[1-9]\\d{0,2}|00[1-9]\\d?|000[1-9]))$" }),
        currency: nullable(t.String({ pattern: "^[A-Z]{3}$" })),
        role: enumValues(["transaction", "paid_total", "price", "conditional_price", "installment", "plan_total", "subtotal", "tendered", "change", "old_price", "reward", "other"]),
      }, closed), { maxItems: 20 }),
      selectedAmountIndex: nullable(t.Integer({ minimum: 0, maximum: 19 })),
      amountChoiceSource: text(),
      category: t.Object({
        id: categoryIds.length ? nullable(enumValues(categoryIds)) : t.Null(),
        basis: enumValues(["user", "merchant", "purpose", "source_label", "parent", "unresolved"]),
        source: text(),
      }, closed),
      counterparty: text(), note: text(2_000),
      date: date(),
      schedule: nullable(t.Object({
        source: source(),
        frequency: enumValues(["daily", "weekly", "monthly", "yearly"]),
        occurrenceCount: nullable(t.Integer({ minimum: 1, maximum: 10_000 })),
        duration: nullable(t.Object({ value: t.Integer({ minimum: 1, maximum: 10_000 }), unit: unit() }, closed)),
        endDate: date(),
        totalAmountIndex: nullable(t.Integer({ minimum: 0, maximum: 19 })),
      }, closed)),
      unresolved: t.Array(enumValues(["amount", "currency"]), { maxItems: 2 }),
    }, closed), { maxItems: quickEntryDraftLimitFor(input) }),
  }, closed);
}
