import type { Account, AccountDetails } from "../../domain/accounts/account.ts";

export interface AccountRepository {
  list(): Promise<Account[]>;
  findById(id: string): Promise<Account | null>;
  create(details: AccountDetails): Promise<Account>;
  update(id: string, details: AccountDetails): Promise<Account | null>;
  delete(id: string): Promise<boolean>;
  replaceOrder(accountIds: string[]): Promise<Account[]>;
}
