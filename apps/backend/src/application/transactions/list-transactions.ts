import { materializeRecurringTransactions } from "./materialize-recurring-transactions.ts";
import type { TransactionRepository } from "./transaction.repository.ts";

export async function listTransactions(
  input: { accountId?: string },
  dependencies: { transactions: TransactionRepository },
) {
  await materializeRecurringTransactions({}, dependencies);
  return dependencies.transactions.listDetailed(input.accountId);
}
