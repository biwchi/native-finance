import {
  createBudget,
  hasBudgetValues,
  type Budget,
  type BudgetInput,
  type BudgetValidationError,
} from "../../domain/budgets/budget.ts";
import { ok, type Result } from "../../domain/shared/result.ts";
import type { AccountRepository } from "../accounts/account.repository.ts";
import type { CategoryRepository } from "../categories/category.repository.ts";
import type { BudgetRepository } from "./budget.repository.ts";

export type SaveMonthlyBudgetInput = BudgetInput;

export async function saveMonthlyBudget(
  input: SaveMonthlyBudgetInput,
  dependencies: {
    accounts: AccountRepository;
    budgets: BudgetRepository;
    categories: CategoryRepository;
  },
): Promise<Result<Budget | null, BudgetValidationError>> {
  const accountId = input.accountId ?? null;
  const categoryIds = input.categoryAssignments.map(
    (assignment) => assignment.categoryId,
  );
  const [account, categories] = await Promise.all([
    accountId
      ? dependencies.accounts.findById(accountId)
      : Promise.resolve(null),
    dependencies.categories.findByIds(categoryIds),
  ]);

  const budget = createBudget(input, { account, categories });
  if (!budget.ok) return budget;

  if (!hasBudgetValues(budget.value)) {
    await dependencies.budgets.delete(budget.value.month, budget.value.accountId);
    return ok(null);
  }
  return ok(await dependencies.budgets.save(budget.value));
}
