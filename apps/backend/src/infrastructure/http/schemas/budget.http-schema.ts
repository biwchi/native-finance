import { t } from "elysia";

import { amountSchema } from "./finance.http-schema.ts";

const monthPattern = "^\\d{4}-(?:0[1-9]|1[0-2])$";

export const budgetQuerySchema = t.Object({
  month: t.String({ pattern: monthPattern }),
  accountId: t.Optional(t.String({ format: "uuid" })),
});

export const budgetBodySchema = t.Object({
  month: t.String({ pattern: monthPattern }),
  accountId: t.Optional(t.Nullable(t.String({ format: "uuid" }))),
  currency: t.String({ pattern: "^[A-Za-z]{3}$" }),
  monthlyLimit: t.Optional(t.Nullable(amountSchema)),
  groups: t.Array(t.Object({
    id: t.String({ format: "uuid" }),
    name: t.String({ minLength: 1, maxLength: 80 }),
    limit: amountSchema,
  }), { maxItems: 100 }),
  categoryAssignments: t.Array(t.Object({
    categoryId: t.String({ format: "uuid" }),
    groupId: t.Optional(t.Nullable(t.String({ format: "uuid" }))),
    limit: t.Optional(t.Nullable(amountSchema)),
  }), { maxItems: 500 }),
});
