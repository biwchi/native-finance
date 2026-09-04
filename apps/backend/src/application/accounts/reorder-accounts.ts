import {
  createAccountOrder,
  type Account,
} from "../../domain/accounts/account.ts";
import { ok, type Result } from "../../domain/shared/result.ts";
import type { AccountRepository } from "./account.repository.ts";

export async function reorderAccounts(
  accountIds: string[],
  dependencies: { accounts: AccountRepository },
): Promise<Result<Account[], "invalid_account_order">> {
  const existingAccounts = await dependencies.accounts.list();
  const order = createAccountOrder(accountIds, existingAccounts);
  if (!order.ok) return order;
  return ok(await dependencies.accounts.replaceOrder(order.value));
}
