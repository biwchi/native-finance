import type { BudgetRepository } from "./budget.repository.ts";

export function getMonthlyBudget(
  input: { month: string; accountId?: string },
  dependencies: { budgets: BudgetRepository },
) {
  return dependencies.budgets.find(`${input.month}-01`, input.accountId ?? null);
}
