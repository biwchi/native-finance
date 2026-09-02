import { asc, eq, sql } from "drizzle-orm";
import { Elysia, t } from "elysia";

import { db } from "../db/client.ts";
import { accounts } from "../db/schema.ts";

const accountTypeSchema = t.Union([
  t.Literal("cash"),
  t.Literal("checking"),
  t.Literal("savings"),
  t.Literal("credit"),
  t.Literal("investment"),
]);

const accountIconColorSchema = t.Union([
  t.Literal("blue"),
  t.Literal("indigo"),
  t.Literal("purple"),
  t.Literal("pink"),
  t.Literal("red"),
  t.Literal("orange"),
  t.Literal("green"),
  t.Literal("teal"),
  t.Literal("gray"),
]);

const accountBodySchema = t.Object({
  name: t.String({ minLength: 1, maxLength: 120 }),
  type: accountTypeSchema,
  currency: t.String({ pattern: "^[A-Za-z]{3}$" }),
  icon: t.String({ minLength: 1, maxLength: 80 }),
  iconColor: accountIconColorSchema,
});

export const accountsRoutes = new Elysia({ prefix: "/accounts" })
  .get("/", () =>
    db
      .select()
      .from(accounts)
      .orderBy(
        asc(accounts.sortOrder),
        asc(accounts.name),
        asc(accounts.createdAt),
      ),
  )
  .post(
    "/",
    async ({ body, set }) => {
      const [sortOrderResult] = await db
        .select({
          nextSortOrder: sql<number>`coalesce(max(${accounts.sortOrder}), -1) + 1`,
        })
        .from(accounts);
      const [account] = await db
        .insert(accounts)
        .values({
          ...body,
          currency: body.currency.toUpperCase(),
          sortOrder: sortOrderResult?.nextSortOrder ?? 0,
        })
        .returning();

      set.status = 201;
      return account;
    },
    {
      body: accountBodySchema,
    },
  )
  .patch(
    "/order",
    async ({ body, set }) => {
      const existingAccounts = await db.select({ id: accounts.id }).from(accounts);
      const existingIDs = new Set(existingAccounts.map((account) => account.id));
      const submittedIDs = new Set(body.accountIds);

      if (
        submittedIDs.size !== body.accountIds.length ||
        submittedIDs.size !== existingIDs.size ||
        body.accountIds.some((id) => !existingIDs.has(id))
      ) {
        set.status = 400;
        return { message: "Account order must include every account exactly once" };
      }

      await db.transaction(async (transaction) => {
        for (const [sortOrder, id] of body.accountIds.entries()) {
          await transaction
            .update(accounts)
            .set({ sortOrder })
            .where(eq(accounts.id, id));
        }
      });

      return db
        .select()
        .from(accounts)
        .orderBy(
          asc(accounts.sortOrder),
          asc(accounts.name),
          asc(accounts.createdAt),
        );
    },
    {
      body: t.Object({
        accountIds: t.Array(t.String({ format: "uuid" }), {
          uniqueItems: true,
        }),
      }),
    },
  )
  .patch(
    "/:id",
    async ({ params, body, set }) => {
      const [account] = await db
        .update(accounts)
        .set({
          ...body,
          currency: body.currency.toUpperCase(),
          updatedAt: new Date(),
        })
        .where(eq(accounts.id, params.id))
        .returning();

      if (!account) {
        set.status = 404;
        return { message: "Account not found" };
      }

      return account;
    },
    {
      params: t.Object({
        id: t.String({ format: "uuid" }),
      }),
      body: accountBodySchema,
    },
  )
  .delete(
    "/:id",
    async ({ params, set }) => {
      const [deletedAccount] = await db
        .delete(accounts)
        .where(eq(accounts.id, params.id))
        .returning({ id: accounts.id });

      if (!deletedAccount) {
        set.status = 404;
        return { message: "Account not found" };
      }

      return { deleted: true };
    },
    {
      params: t.Object({
        id: t.String({ format: "uuid" }),
      }),
    },
  );
