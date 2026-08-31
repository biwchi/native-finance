import { and, desc, eq } from "drizzle-orm";
import { Elysia, t } from "elysia";

import { db } from "../db/client.ts";
import { transactions } from "../db/schema.ts";

const transactionKindSchema = t.Union([
  t.Literal("expense"),
  t.Literal("income"),
]);

export const transactionsRoutes = new Elysia({ prefix: "/transactions" })
  .get(
    "/",
    ({ query }) => {
      const filters = query.accountId
        ? and(eq(transactions.accountId, query.accountId))
        : undefined;

      return db
        .select()
        .from(transactions)
        .where(filters)
        .orderBy(desc(transactions.occurredOn), desc(transactions.createdAt));
    },
    {
      query: t.Object({
        accountId: t.Optional(t.String({ format: "uuid" })),
      }),
    },
  )
  .post(
    "/",
    async ({ body, set }) => {
      const [transaction] = await db
        .insert(transactions)
        .values({
          ...body,
          currency: body.currency.toUpperCase(),
        })
        .returning();

      set.status = 201;
      return transaction;
    },
    {
      body: t.Object({
        accountId: t.String({ format: "uuid" }),
        kind: transactionKindSchema,
        amount: t.String({ pattern: "^(0|[1-9]\\d*)(\\.\\d{1,4})?$" }),
        currency: t.String({ pattern: "^[A-Za-z]{3}$" }),
        category: t.Optional(t.String({ maxLength: 80 })),
        note: t.Optional(t.String({ maxLength: 2_000 })),
        occurredOn: t.String({ format: "date" }),
      }),
    },
  );

