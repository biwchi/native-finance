import { boundedNextOccurrence } from "../../domain/transactions/recurrence.ts";
import {
  createTransfer,
  type TransactionDraft,
  type TransactionInput,
  type TransferInput,
  type TransactionValues,
} from "../../domain/transactions/transaction.ts";
import { error, ok, type Result } from "../../domain/shared/result.ts";
import type { AccountRepository } from "../accounts/account.repository.ts";
import type { CategoryRepository } from "../categories/category.repository.ts";
import { prepareTransaction } from "./prepare-transaction.ts";
import { scheduleTemplate } from "./recurring-values.ts";
import type { TransactionRepository } from "./transaction.repository.ts";

export type TransactionBatchItem =
  | { type: "transaction"; transaction: TransactionInput }
  | { type: "transfer"; transfer: TransferInput };

type PreparedBatchItem =
  | { type: "transaction"; draft: TransactionDraft }
  | {
    type: "transfer";
    source: TransactionValues;
    destination: TransactionValues;
  };

export async function createTransactionBatch(
  items: TransactionBatchItem[],
  dependencies: {
    accounts: AccountRepository;
    categories: CategoryRepository;
    transactions: TransactionRepository;
  },
): Promise<Result<{ created: number }, string>> {
  const prepared: PreparedBatchItem[] = [];
  for (const [index, item] of items.entries()) {
    if (item.type === "transaction") {
      const draft = await prepareTransaction(item.transaction, dependencies);
      if (!draft.ok) {
        return error(draft.error.code, `Transaction ${index + 1}: ${draft.error.message}`);
      }
      prepared.push({ type: "transaction", draft: draft.value });
      continue;
    }

    const [sourceAccount, destinationAccount] = await Promise.all([
      dependencies.accounts.findById(item.transfer.fromAccountId),
      dependencies.accounts.findById(item.transfer.toAccountId),
    ]);
    const transfer = createTransfer(item.transfer, { sourceAccount, destinationAccount });
    if (!transfer.ok) {
      return error(transfer.error.code, `Transaction ${index + 1}: ${transfer.error.message}`);
    }
    prepared.push({
      type: "transfer",
      source: transfer.value.source,
      destination: transfer.value.destination,
    });
  }

  await dependencies.transactions.atomically(async (store) => {
    for (const item of prepared) {
      if (item.type === "transfer") {
        await store.insertTransactions([item.source, item.destination]);
        continue;
      }
      const { values, recurrence } = item.draft;
      if (!recurrence) {
        await store.insertTransaction(values);
        continue;
      }
      const schedule = await store.insertSchedule({
        ...scheduleTemplate(values),
        frequency: recurrence.frequency,
        startAt: values.occurredAt,
        lastOccurrenceAt: values.occurredAt,
        nextOccurrenceAt: boundedNextOccurrence(
          values.occurredAt,
          values.occurredAt,
          recurrence.frequency,
          recurrence.endAt,
        ),
        endAt: recurrence.endAt,
      });
      await store.insertTransaction({
        ...values,
        recurringScheduleId: schedule.id,
      });
    }
  });

  return ok({ created: items.length });
}
