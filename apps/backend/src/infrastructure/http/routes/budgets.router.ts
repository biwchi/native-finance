import { Elysia } from "elysia";

import type { Budget } from "../../../domain/budgets/budget.ts";
import type { Result } from "../../../domain/shared/result.ts";
import {
  budgetBodySchema,
  budgetQuerySchema,
} from "../schemas/budget.http-schema.ts";

export type BudgetController = {
  get(input: typeof budgetQuerySchema.static): Promise<Budget | null>;
  save(input: typeof budgetBodySchema.static): Promise<Result<Budget | null, string>>;
};

export function createBudgetsRouter(controller: BudgetController) {
  return new Elysia({ prefix: "/budgets" })
    .get("/monthly", async ({ query }) => {
      const budget = await controller.get(query);
      return budget ?? Response.json(null);
    }, { query: budgetQuerySchema })
    .put("/monthly", async ({ body, set }) => {
      const result = await controller.save(body);
      if (!result.ok) {
        set.status = result.error.code === "account_not_found" ||
            result.error.code === "category_not_found"
          ? 404
          : 400;
        return { message: result.error.message };
      }
      return result.value ?? Response.json(null);
    }, { body: budgetBodySchema });
}
