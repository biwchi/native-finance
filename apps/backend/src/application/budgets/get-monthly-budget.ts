import type { BudgetRepository } from "./budget.repository.ts";

export function getMonthlyBudget(
  input: { accountId?: string },
  dependencies: { budgets: BudgetRepository },
) {
  return dependencies.budgets.find(input.accountId?.toLowerCase() ?? null);
}
