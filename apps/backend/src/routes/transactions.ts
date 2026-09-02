import { and, desc, eq, getTableColumns, inArray } from "drizzle-orm";
import { Elysia, t } from "elysia";

import { db } from "../db/client.ts";
import {
  accounts,
  categories,
  recurringSchedules,
  transactions,
} from "../db/schema.ts";
import {
  materializeRecurringSchedule,
  materializeRecurringTransactions,
  nextRecurrenceDate,
} from "../services/recurring-transactions.ts";
import { transactionKindSchema } from "./categories.ts";

const amountPattern =
  "^(?=.{1,20}$)(?!0+(?:\\.0{1,4})?$)(?:0|[1-9]\\d{0,14})(?:\\.\\d{1,4})?$";

const recurrenceFrequencySchema = t.Union([
  t.Literal("daily"),
  t.Literal("weekly"),
  t.Literal("monthly"),
  t.Literal("yearly"),
]);

const recurrenceBody = t.Object({
  frequency: recurrenceFrequencySchema,
  endAt: t.Optional(t.Nullable(t.String({ format: "date-time" }))),
});

const transactionBody = t.Object({
  accountId: t.String({ format: "uuid" }),
  kind: transactionKindSchema,
  amount: t.String({ pattern: amountPattern }),
  categoryId: t.Optional(t.Nullable(t.String({ format: "uuid" }))),
  merchant: t.Optional(t.Nullable(t.String({ maxLength: 500 }))),
  payee: t.Optional(t.Nullable(t.String({ maxLength: 500 }))),
  note: t.Optional(t.Nullable(t.String({ maxLength: 2_000 }))),
  recurrence: t.Optional(t.Nullable(recurrenceBody)),
  occurredAt: t.String({ format: "date-time" }),
});

const transferBody = t.Object({
  fromAccountId: t.String({ format: "uuid" }),
  toAccountId: t.String({ format: "uuid" }),
  amount: t.String({ pattern: amountPattern }),
  merchant: t.Optional(t.Nullable(t.String({ maxLength: 500 }))),
  payee: t.Optional(t.Nullable(t.String({ maxLength: 500 }))),
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
  recurrence: {
    id: recurringSchedules.id,
    frequency: recurringSchedules.frequency,
    endAt: recurringSchedules.endAt,
  },
};

export const transactionsRoutes = new Elysia({ prefix: "/transactions" })
  .get(
    "/",
    async ({ query }) => {
      await materializeRecurringTransactions();

      const filters = query.accountId
        ? and(eq(transactions.accountId, query.accountId))
        : undefined;

      const rows = await db
        .select(transactionSelection)
        .from(transactions)
        .leftJoin(categories, eq(transactions.categoryId, categories.id))
        .leftJoin(
          recurringSchedules,
          eq(transactions.recurringScheduleId, recurringSchedules.id),
        )
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

      const recurrence = parseRecurrence(body.recurrence, prepared.values.occurredAt);
      if ("error" in recurrence) {
        set.status = 400;
        return { message: recurrence.error };
      }

      const created = await db.transaction(async (databaseTransaction) => {
        if (!recurrence.value) {
          const [transaction] = await databaseTransaction
            .insert(transactions)
            .values(prepared.values)
            .returning();
          return { transaction, scheduleId: null };
        }

        const [schedule] = await databaseTransaction
          .insert(recurringSchedules)
          .values({
            ...scheduleTemplate(prepared.values),
            frequency: recurrence.value.frequency,
            startAt: prepared.values.occurredAt,
            lastOccurrenceAt: prepared.values.occurredAt,
            nextOccurrenceAt: boundedNextOccurrence(
              prepared.values.occurredAt,
              prepared.values.occurredAt,
              recurrence.value.frequency,
              recurrence.value.endAt,
            ),
            endAt: recurrence.value.endAt,
          })
          .returning({ id: recurringSchedules.id });

        if (!schedule) {
          throw new Error("Recurring schedule insert did not return a row");
        }

        const [transaction] = await databaseTransaction
          .insert(transactions)
          .values({
            ...prepared.values,
            recurringScheduleId: schedule.id,
          })
          .returning();
        return { transaction, scheduleId: schedule.id };
      });

      if (!created.transaction) {
        throw new Error("Transaction insert did not return a row");
      }

      if (created.scheduleId) {
        await materializeRecurringSchedule(created.scheduleId);
      }

      set.status = 201;
      return await findTransactionResponse(created.transaction.id);
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

      const sharedValues = {
        amount: body.amount,
        currency: sourceAccount.currency,
        categoryId: null,
        merchant: cleanOptionalText(body.merchant),
        payee: cleanOptionalText(body.payee),
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
        source: toTransactionResponse({ ...source, category: null, recurrence: null }),
        destination: toTransactionResponse({ ...destination, category: null, recurrence: null }),
      };
    },
    { body: transferBody },
  )
  .put(
    "/:id",
    async ({ params, body, set }) => {
      const [existing] = await db
        .select({
          accountId: transactions.accountId,
          currency: transactions.currency,
          recurringScheduleId: transactions.recurringScheduleId,
        })
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

      const recurrence = parseRecurrence(body.recurrence, prepared.values.occurredAt);
      if ("error" in recurrence) {
        set.status = 400;
        return { message: recurrence.error };
      }

      const values = {
        ...prepared.values,
        // Keep the historical currency unless the transaction moves to another account.
        currency: existing.accountId === body.accountId
          ? existing.currency
          : prepared.values.currency,
        updatedAt: new Date(),
      };

      const scheduleId = await db.transaction(async (databaseTransaction) => {
        if (!recurrence.value) {
          const [transaction] = await databaseTransaction
            .update(transactions)
            .set(values)
            .where(eq(transactions.id, params.id))
            .returning({ id: transactions.id });

          if (existing.recurringScheduleId) {
            await databaseTransaction
              .delete(recurringSchedules)
              .where(eq(recurringSchedules.id, existing.recurringScheduleId));
          }
          return transaction ? null : undefined;
        }

        if (existing.recurringScheduleId) {
          const [schedule] = await databaseTransaction
            .select()
            .from(recurringSchedules)
            .where(eq(recurringSchedules.id, existing.recurringScheduleId))
            .limit(1);

          if (!schedule) {
            throw new Error("Recurring schedule not found");
          }

          const frequencyChanged = schedule.frequency !== recurrence.value.frequency;
          const nextOccurrenceAt = frequencyChanged || !schedule.nextOccurrenceAt
            ? boundedNextOccurrence(
                schedule.lastOccurrenceAt,
                schedule.startAt,
                recurrence.value.frequency,
                recurrence.value.endAt,
              )
            : boundExistingNext(schedule.nextOccurrenceAt, recurrence.value.endAt);

          await databaseTransaction
            .update(recurringSchedules)
            .set({
              ...scheduleTemplate(values),
              frequency: recurrence.value.frequency,
              nextOccurrenceAt,
              endAt: recurrence.value.endAt,
              updatedAt: new Date(),
            })
            .where(eq(recurringSchedules.id, schedule.id));

          const [transaction] = await databaseTransaction
            .update(transactions)
            .set(values)
            .where(eq(transactions.id, params.id))
            .returning({ id: transactions.id });
          return transaction ? schedule.id : undefined;
        }

        const [schedule] = await databaseTransaction
          .insert(recurringSchedules)
          .values({
            ...scheduleTemplate(values),
            frequency: recurrence.value.frequency,
            startAt: values.occurredAt,
            lastOccurrenceAt: values.occurredAt,
            nextOccurrenceAt: boundedNextOccurrence(
              values.occurredAt,
              values.occurredAt,
              recurrence.value.frequency,
              recurrence.value.endAt,
            ),
            endAt: recurrence.value.endAt,
          })
          .returning({ id: recurringSchedules.id });

        if (!schedule) {
          throw new Error("Recurring schedule insert did not return a row");
        }

        const [transaction] = await databaseTransaction
          .update(transactions)
          .set({ ...values, recurringScheduleId: schedule.id })
          .where(eq(transactions.id, params.id))
          .returning({ id: transactions.id });
        return transaction ? schedule.id : undefined;
      });

      if (scheduleId === undefined) {
        set.status = 404;
        return { message: "Transaction not found" };
      }

      if (scheduleId) {
        await materializeRecurringSchedule(scheduleId);
      }

      return await findTransactionResponse(params.id);
    },
    {
      params: t.Object({ id: t.String({ format: "uuid" }) }),
      body: transactionBody,
    },
  )
  .delete(
    "/:id",
    async ({ params, set }) => {
      const [deletedTransaction] = await db
        .delete(transactions)
        .where(eq(transactions.id, params.id))
        .returning({ id: transactions.id });

      if (!deletedTransaction) {
        set.status = 404;
        return { message: "Transaction not found" };
      }

      return { deleted: true };
    },
    {
      params: t.Object({ id: t.String({ format: "uuid" }) }),
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
  recurrence: {
    id: string;
    frequency: "daily" | "weekly" | "monthly" | "yearly";
    endAt: Date | null;
  } | null;
};

function toTransactionResponse(row: TransactionResponseRow) {
  const { categoryId: _, recurringScheduleId: __, ...transaction } = row;
  return transaction;
}

async function findTransactionResponse(id: string) {
  const [transaction] = await db
    .select(transactionSelection)
    .from(transactions)
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .leftJoin(
      recurringSchedules,
      eq(transactions.recurringScheduleId, recurringSchedules.id),
    )
    .where(eq(transactions.id, id))
    .limit(1);

  if (!transaction) {
    throw new Error("Transaction not found after save");
  }
  return toTransactionResponse(transaction);
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
      note: cleanOptionalText(body.note),
      occurredAt,
    },
  };
}

function parseRecurrence(
  recurrence: typeof recurrenceBody.static | null | undefined,
  occurredAt: Date,
) {
  if (!recurrence) {
    return { value: null } as const;
  }

  const endAt = recurrence.endAt ? new Date(recurrence.endAt) : null;
  if (endAt && (Number.isNaN(endAt.getTime()) || endAt < occurredAt)) {
    return {
      error: "Recurrence end date must be on or after the transaction date",
    } as const;
  }

  return {
    value: {
      frequency: recurrence.frequency,
      endAt,
    },
  } as const;
}

function scheduleTemplate(values: {
  accountId: string;
  kind: "expense" | "income";
  amount: string;
  currency: string;
  categoryId: string | null;
  merchant: string | null;
  payee: string | null;
  note: string | null;
}) {
  return {
    accountId: values.accountId,
    kind: values.kind,
    amount: values.amount,
    currency: values.currency,
    categoryId: values.categoryId,
    merchant: values.merchant,
    payee: values.payee,
    note: values.note,
  };
}

function boundedNextOccurrence(
  after: Date,
  startAt: Date,
  frequency: "daily" | "weekly" | "monthly" | "yearly",
  endAt: Date | null,
): Date | null {
  const next = nextRecurrenceDate(after, startAt, frequency);
  return boundExistingNext(next, endAt);
}

function boundExistingNext(next: Date, endAt: Date | null): Date | null {
  return endAt && next > endAt ? null : next;
}
