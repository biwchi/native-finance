import { error, ok, type Result } from "../shared/result.ts";

export type Account = {
  id: string;
  name: string;
  initialBalance: string;
  currency: string;
  icon: string;
  iconColor: string;
  sortOrder: number;
  createdAt: Date;
  updatedAt: Date;
};

export type AccountDetails = Pick<
  Account,
  "name" | "currency" | "icon" | "iconColor"
> & { initialBalance?: string };

export function createAccount(input: AccountDetails): AccountDetails {
  return { ...input, currency: input.currency.toUpperCase() };
}

export function createAccountOrder(
  accountIds: string[],
  existingAccounts: Account[],
): Result<string[], "invalid_account_order"> {
  const existingIds = new Set(existingAccounts.map((account) => account.id));
  const submittedIds = new Set(accountIds);
  if (
    submittedIds.size !== accountIds.length ||
    submittedIds.size !== existingIds.size ||
    accountIds.some((id) => !existingIds.has(id))
  ) {
    return error(
      "invalid_account_order",
      "Account order must include every account exactly once",
    );
  }
  return ok(accountIds);
}
