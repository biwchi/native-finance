import type { Budget, BudgetDraft } from "../../domain/budgets/budget.ts";

export interface BudgetRepository {
  find(month: string, accountId: string | null): Promise<Budget | null>;
  save(snapshot: BudgetDraft): Promise<Budget>;
  delete(month: string, accountId: string | null): Promise<void>;
}
