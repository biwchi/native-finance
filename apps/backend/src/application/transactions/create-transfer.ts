import {
  createTransfer as createTransferModel,
  type TransferInput,
  type TransferValidationError,
  type TransactionRecord,
  type TransactionResponse,
} from "../../domain/transactions/transaction.ts";
import { ok, type Result } from "../../domain/shared/result.ts";
import type { AccountRepository } from "../accounts/account.repository.ts";
import type { TransactionRepository } from "./transaction.repository.ts";

export async function createTransfer(
  input: TransferInput,
  dependencies: {
    accounts: AccountRepository;
    transactions: TransactionRepository;
  },
): Promise<Result<
  { source: TransactionResponse; destination: TransactionResponse },
  TransferValidationError
>> {
  const [sourceAccount, destinationAccount] = await Promise.all([
    dependencies.accounts.findById(input.fromAccountId),
    dependencies.accounts.findById(input.toAccountId),
  ]);
  const transfer = createTransferModel(input, { sourceAccount, destinationAccount });
  if (!transfer.ok) return transfer;

  const [source, destination] = await dependencies.transactions.atomically((store) =>
    store.insertTransactions([
      transfer.value.source,
      transfer.value.destination,
    ])
  );
  if (!source || !destination) throw new Error("Transfer insert did not return both rows");
  return ok({
    source: withoutRelations(source),
    destination: withoutRelations(destination),
  });
}

function withoutRelations(
  transaction: TransactionRecord,
): TransactionResponse {
  const { categoryId: _, recurringScheduleId: __, ...values } = transaction;
  return { ...values, category: null, recurrence: null };
}
