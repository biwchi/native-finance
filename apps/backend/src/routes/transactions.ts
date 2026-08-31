import { and, desc, eq, getTableColumns } from "drizzle-orm";
import { Elysia, t } from "elysia";

import { db } from "../db/client.ts";
import { accounts, categories, transactions } from "../db/schema.ts";
import { normalizeTransactionDescription } from "../services/category-resolution.ts";
import { transactionKindSchema } from "./categories.ts";

const amountPattern =
  "^(?=.{1,20}$)(?!0+(?:\\.0{1,4})?$)(?:0|[1-9]\\d{0,14})(?:\\.\\d{1,4})?$";

const transactionSelection = {
  ...getTableColumns(transactions),
  category: {
    id: categories.id,
    systemKey: categories.systemKey,
    name: categories.name,
    kind: categories.kind,
    isSystem: categories.isSystem,
  },
};

export const transactionsRoutes = new Elysia({ prefix: "/transactions" })
  .get(
    "/",
    async ({ query }) => {
      const filters = query.accountId
        ? and(eq(transactions.accountId, query.accountId))
        : undefined;

      const rows = await db
        .select(transactionSelection)
        .from(transactions)
        .leftJoin(categories, eq(transactions.categoryId, categories.id))
        .where(filters)
        .orderBy(desc(transactions.occurredAt), desc(transactions.createdAt));

      return rows.map(toTransactionResponse);
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
      const [account] = await db
        .select()
        .from(accounts)
        .where(eq(accounts.id, body.accountId))
        .limit(1);

      if (!account) {
        set.status = 404;
        return { message: "Account not found" };
      }

      let category: CategorySummary | null = null;
      if (body.categoryId) {
        const [selectedCategory] = await db
          .select({
            id: categories.id,
            systemKey: categories.systemKey,
            name: categories.name,
            kind: categories.kind,
            isSystem: categories.isSystem,
          })
          .from(categories)
          .where(eq(categories.id, body.categoryId))
          .limit(1);

        if (!selectedCategory) {
          set.status = 404;
          return { message: "Category not found" };
        }

        if (selectedCategory.kind !== body.kind) {
          set.status = 400;
          return { message: "Category kind must match transaction kind" };
        }

        category = selectedCategory;
      }

      const occurredAt = new Date(body.occurredAt);
      if (Number.isNaN(occurredAt.getTime())) {
        set.status = 400;
        return { message: "occurredAt must be a valid date and time" };
      }

      const description = cleanOptionalText(body.description);
      const note = cleanOptionalText(body.note);
      const [transaction] = await db
        .insert(transactions)
        .values({
          accountId: account.id,
          kind: body.kind,
          amount: body.amount,
          currency: account.currency,
          categoryId: category?.id,
          description,
          normalizedDescription: description
            ? normalizeTransactionDescription(description)
            : null,
          note,
          occurredAt,
        })
        .returning();

      if (!transaction) {
        throw new Error("Transaction insert did not return a row");
      }

      set.status = 201;
      return toTransactionResponse({ ...transaction, category });
    },
    {
      body: t.Object({
        accountId: t.String({ format: "uuid" }),
        kind: transactionKindSchema,
        amount: t.String({ pattern: amountPattern }),
        categoryId: t.Optional(t.String({ format: "uuid" })),
        description: t.Optional(t.String({ maxLength: 2_000 })),
        note: t.Optional(t.String({ maxLength: 2_000 })),
        occurredAt: t.String({ format: "date-time" }),
      }),
    },
  );

type CategorySummary = {
  id: string;
  systemKey: string | null;
  name: string;
  kind: "expense" | "income";
  isSystem: boolean;
};

type TransactionResponseRow = typeof transactions.$inferSelect & {
  category: CategorySummary | null;
};

function toTransactionResponse(row: TransactionResponseRow) {
  const { normalizedDescription: _, categoryId: __, ...transaction } = row;
  return transaction;
}

function cleanOptionalText(value: string | undefined): string | null {
  const cleaned = value?.trim();
  return cleaned ? cleaned : null;
}
