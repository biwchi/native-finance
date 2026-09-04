import type { Account } from "../../domain/accounts/account.ts";
import type { AccountRepository } from "./account.repository.ts";

export function listAccounts(
  _input: undefined,
  dependencies: { accounts: AccountRepository },
): Promise<Account[]> {
  return dependencies.accounts.list();
}
