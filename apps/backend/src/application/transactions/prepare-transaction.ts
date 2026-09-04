import {
  createTransaction as createTransactionModel,
  type TransactionDraft,
  type TransactionInput,
  type TransactionValidationError,
} from "../../domain/transactions/transaction.ts";
import type { Result } from "../../domain/shared/result.ts";
import type { AccountRepository } from "../accounts/account.repository.ts";
import type { CategoryRepository } from "../categories/category.repository.ts";

export async function prepareTransaction(
  input: TransactionInput,
  dependencies: {
    accounts: AccountRepository;
    categories: CategoryRepository;
  },
): Promise<Result<TransactionDraft, TransactionValidationError>> {
  const [account, category] = await Promise.all([
    dependencies.accounts.findById(input.accountId),
    input.categoryId
      ? dependencies.categories.findById(input.categoryId)
      : Promise.resolve(null),
  ]);
  return createTransactionModel(input, { account, category });
}
