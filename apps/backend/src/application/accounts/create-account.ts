import {
  createAccount as createAccountModel,
  type Account,
  type AccountDetails,
} from "../../domain/accounts/account.ts";
import type { AccountRepository } from "./account.repository.ts";

export function createAccount(
  input: AccountDetails,
  dependencies: { accounts: AccountRepository },
): Promise<Account> {
  return dependencies.accounts.create(createAccountModel(input));
}
