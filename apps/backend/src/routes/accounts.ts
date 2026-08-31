import { asc, eq } from "drizzle-orm";
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
  .get("/", () => db.select().from(accounts).orderBy(asc(accounts.name)))
  .post(
    "/",
    async ({ body, set }) => {
      const [account] = await db
        .insert(accounts)
        .values({
          ...body,
          currency: body.currency.toUpperCase(),
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
  );
