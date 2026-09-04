import {
  createAccount as createAccountModel,
  type Account,
  type AccountDetails,
} from "../../domain/accounts/account.ts";
import { error, ok, type Result } from "../../domain/shared/result.ts";
import type { AccountRepository } from "./account.repository.ts";

export async function updateAccount(
  input: { id: string; details: AccountDetails },
  dependencies: { accounts: AccountRepository },
): Promise<Result<Account, "account_not_found">> {
  const account = await dependencies.accounts.update(
    input.id,
    createAccountModel(input.details),
  );

  return account
    ? ok(account)
    : error("account_not_found", "Account not found");
}
