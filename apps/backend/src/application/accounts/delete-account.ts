import { error, ok, type Result } from "../../domain/shared/result.ts";
import type { AccountRepository } from "./account.repository.ts";

export async function deleteAccount(
  id: string,
  dependencies: { accounts: AccountRepository },
): Promise<Result<{ deleted: true }, "account_not_found">> {
  const deleted = await dependencies.accounts.delete(id);
  return deleted
    ? ok({ deleted: true as const })
    : error("account_not_found", "Account not found");
}
