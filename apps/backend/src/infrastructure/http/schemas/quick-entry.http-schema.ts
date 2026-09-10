import { t } from "elysia";
import { accountBodySchema } from "./account.http-schema.ts";
import { categoryColorSchema } from "./category.http-schema.ts";
import { transactionKindSchema } from "./finance.http-schema.ts";

export const quickEntryBodySchema = t.Object({
  text: t.String({ minLength: 1, maxLength: 20_000 }),
  defaultAccountId: t.String({ format: "uuid" }),
  locale: t.String({ minLength: 2, maxLength: 100 }),
  timeZone: t.String({ minLength: 1, maxLength: 100 }),
  // This is parser context only. Finance writes still pass through validated mutations.
  context: t.Optional(t.Object({
    accounts: t.Array(t.Object({ id: t.String({ format: "uuid" }), ...accountBodySchema.properties }), { maxItems: 1000 }),
    categories: t.Array(t.Object({
      id: t.String({ format: "uuid" }), name: t.String({ minLength: 1, maxLength: 80 }), kind: transactionKindSchema,
      parentId: t.Optional(t.Nullable(t.String({ format: "uuid" }))),
      icon: t.Optional(t.Nullable(t.String({ maxLength: 80 }))), color: t.Optional(t.Nullable(categoryColorSchema)),
      examples: t.Optional(t.Array(t.String({ maxLength: 200 }), { maxItems: 100 })),
    }), { maxItems: 5000 }),
  })),
});
