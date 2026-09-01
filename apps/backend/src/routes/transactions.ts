import { and, desc, eq, getTableColumns, inArray } from "drizzle-orm";
import { Elysia, t } from "elysia";

import { db } from "../db/client.ts";
import { accounts, categories, transactions } from "../db/schema.ts";
import { normalizeTransactionDescription } from "../services/category-resolution.ts";
import { transactionKindSchema } from "./categories.ts";

const amountPattern =
  "^(?=.{1,20}$)(?!0+(?:\\.0{1,4})?$)(?:0|[1-9]\\d{0,14})(?:\\.\\d{1,4})?$";

const transactionBody = t.Object({
  accountId: t.String({ format: "uuid" }),
  kind: transactionKindSchema,
  amount: t.String({ pattern: amountPattern }),
  categoryId: t.Optional(t.Nullable(t.String({ format: "uuid" }))),
  merchant: t.Optional(t.Nullable(t.String({ maxLength: 500 }))),
  payee: t.Optional(t.Nullable(t.String({ maxLength: 500 }))),
  description: t.Optional(t.Nullable(t.String({ maxLength: 2_000 }))),
  note: t.Optional(t.Nullable(t.String({ maxLength: 2_000 }))),
  occurredAt: t.String({ format: "date-time" }),
});

const transferBody = t.Object({
  fromAccountId: t.String({ format: "uuid" }),
  toAccountId: t.String({ format: "uuid" }),
  amount: t.String({ pattern: amountPattern }),
  merchant: t.Optional(t.Nullable(t.String({ maxLength: 500 }))),
  payee: t.Optional(t.Nullable(t.String({ maxLength: 500 }))),
  description: t.Optional(t.Nullable(t.String({ maxLength: 2_000 }))),
  note: t.Optional(t.Nullable(t.String({ maxLength: 2_000 }))),
  occurredAt: t.String({ format: "date-time" }),
});

const transactionSelection = {
  ...getTableColumns(transactions),
  category: {
    id: categories.id,
    systemKey: categories.systemKey,
    name: categories.name,
    kind: categories.kind,
    parentId: categories.parentId,
    icon: categories.icon,
    color: categories.color,
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
      const prepared = await prepareTransaction(body);
      if ("error" in prepared) {
        set.status = prepared.status;
        return { message: prepared.error };
      }

      const [transaction] = await db
        .insert(transactions)
        .values(prepared.values)
        .returning();

      if (!transaction) {
        throw new Error("Transaction insert did not return a row");
      }

      set.status = 201;
      return toTransactionResponse({ ...transaction, category: prepared.category });
    },
    { body: transactionBody },
  )
  .post(
    "/transfer",
    async ({ body, set }) => {
      if (body.fromAccountId === body.toAccountId) {
        set.status = 400;
        return { message: "Transfer accounts must be different" };
      }

      const transferAccounts = await db
        .select()
        .from(accounts)
        .where(inArray(accounts.id, [body.fromAccountId, body.toAccountId]));

      const sourceAccount = transferAccounts.find((account) => account.id === body.fromAccountId);
      const destinationAccount = transferAccounts.find((account) => account.id === body.toAccountId);
      if (!sourceAccount || !destinationAccount) {
        set.status = 404;
        return { message: "Transfer account not found" };
      }
      if (sourceAccount.currency !== destinationAccount.currency) {
        set.status = 400;
        return { message: "Transfer accounts must use the same currency" };
      }

      const occurredAt = new Date(body.occurredAt);
      if (Number.isNaN(occurredAt.getTime())) {
        set.status = 400;
        return { message: "occurredAt must be a valid date and time" };
      }

      const description = cleanOptionalText(body.description);
      const sharedValues = {
        amount: body.amount,
        currency: sourceAccount.currency,
        categoryId: null,
        merchant: cleanOptionalText(body.merchant),
        payee: cleanOptionalText(body.payee),
        description,
        normalizedDescription: description ? normalizeTransactionDescription(description) : null,
        note: cleanOptionalText(body.note),
        occurredAt,
      };

      const [source, destination] = await db.transaction(async (transaction) =>
        transaction
          .insert(transactions)
          .values([
            { ...sharedValues, accountId: sourceAccount.id, kind: "expense" },
            { ...sharedValues, accountId: destinationAccount.id, kind: "income" },
          ])
          .returning(),
      );

      if (!source || !destination) {
        throw new Error("Transfer insert did not return both rows");
      }

      set.status = 201;
      return {
        source: toTransactionResponse({ ...source, category: null }),
        destination: toTransactionResponse({ ...destination, category: null }),
      };
    },
    { body: transferBody },
  )
  .put(
    "/:id",
    async ({ params, body, set }) => {
      const [existing] = await db
        .select({ accountId: transactions.accountId, currency: transactions.currency })
        .from(transactions)
        .where(eq(transactions.id, params.id))
        .limit(1);

      if (!existing) {
        set.status = 404;
        return { message: "Transaction not found" };
      }

      const prepared = await prepareTransaction(body);
      if ("error" in prepared) {
        set.status = prepared.status;
        return { message: prepared.error };
      }

      const [transaction] = await db
        .update(transactions)
        .set({
          ...prepared.values,
          // Keep the historical currency unless the transaction moves to another account.
          currency: existing.accountId === body.accountId
            ? existing.currency
            : prepared.values.currency,
          updatedAt: new Date(),
        })
        .where(eq(transactions.id, params.id))
        .returning();

      if (!transaction) {
        set.status = 404;
        return { message: "Transaction not found" };
      }

      return toTransactionResponse({ ...transaction, category: prepared.category });
    },
    {
      params: t.Object({ id: t.String({ format: "uuid" }) }),
      body: transactionBody,
    },
  );

type CategorySummary = {
  id: string;
  systemKey: string | null;
  name: string;
  kind: "expense" | "income";
  parentId: string | null;
  icon: string | null;
  color: string | null;
  isSystem: boolean;
};

type TransactionResponseRow = typeof transactions.$inferSelect & {
  category: CategorySummary | null;
};

function toTransactionResponse(row: TransactionResponseRow) {
  const { normalizedDescription: _, categoryId: __, ...transaction } = row;
  return transaction;
}

function cleanOptionalText(value: string | null | undefined): string | null {
  const cleaned = value?.trim();
  return cleaned ? cleaned : null;
}

async function prepareTransaction(body: typeof transactionBody.static) {
  const [account] = await db
    .select()
    .from(accounts)
    .where(eq(accounts.id, body.accountId))
    .limit(1);

  if (!account) {
    return { error: "Account not found", status: 404 as const };
  }

  let category: CategorySummary | null = null;
  if (body.categoryId) {
    const [selectedCategory] = await db
      .select(transactionSelection.category)
      .from(categories)
      .where(eq(categories.id, body.categoryId))
      .limit(1);

    if (!selectedCategory) {
      return { error: "Category not found", status: 404 as const };
    }
    if (selectedCategory.kind !== body.kind) {
      return { error: "Category kind must match transaction kind", status: 400 as const };
    }
    category = selectedCategory;
  }

  const occurredAt = new Date(body.occurredAt);
  if (Number.isNaN(occurredAt.getTime())) {
    return { error: "occurredAt must be a valid date and time", status: 400 as const };
  }

  const description = cleanOptionalText(body.description);
  return {
    category,
    values: {
      accountId: account.id,
      kind: body.kind,
      amount: body.amount,
      currency: account.currency,
      // PUT replaces all editable fields, so missing optionals clear their stored values.
      categoryId: category?.id ?? null,
      merchant: cleanOptionalText(body.merchant),
      payee: cleanOptionalText(body.payee),
      description,
      normalizedDescription: description ? normalizeTransactionDescription(description) : null,
      note: cleanOptionalText(body.note),
      occurredAt,
    },
  };
}
