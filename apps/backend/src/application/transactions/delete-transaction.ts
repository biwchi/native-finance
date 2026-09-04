import { error, ok, type Result } from "../../domain/shared/result.ts";
import {
  deleteRecurringTransaction,
  type RecurringDeletionAction,
} from "./delete-recurring-transaction.ts";
import type { TransactionRepository } from "./transaction.repository.ts";

type DeleteTransactionError =
  | "transaction_not_found"
  | "not_recurring"
  | "recurring_transaction_not_found"
  | "stale_occurrence";

export async function deleteTransaction(
  input: { id: string; action?: RecurringDeletionAction },
  dependencies: { transactions: TransactionRepository; now?: () => Date },
): Promise<Result<{ deleted: boolean; stopped?: boolean }, DeleteTransactionError>> {
  const existing = await dependencies.transactions.findRecord(input.id);
  if (!existing) return error("transaction_not_found", "Transaction not found");

  const action = input.action ?? "occurrence";
  if (existing.recurringScheduleId) {
    const result = await deleteRecurringTransaction({
      scheduleId: existing.recurringScheduleId,
      occurredAt: existing.occurredAt,
      action,
    }, dependencies);
    if (!result.ok) return result;
    return ok(action === "occurrence"
      ? { deleted: true }
      : { deleted: result.value.deleted, stopped: true });
  }
  if (action !== "occurrence") {
    return error(
      "not_recurring",
      "This transaction is no longer repeating. Refresh the list.",
    );
  }

  const deleted = await dependencies.transactions.deleteTransaction(input.id);
  return deleted
    ? ok({ deleted: true })
    : error("transaction_not_found", "Transaction not found");
}
