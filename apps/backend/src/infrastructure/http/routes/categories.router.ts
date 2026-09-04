import { Elysia } from "elysia";

import type { CategorySuggestion } from "../../../domain/categories/category-suggestion.ts";
import type { Category } from "../../../domain/categories/category.ts";
import type { Result } from "../../../domain/shared/result.ts";
import {
  categoryIdParamsSchema,
  categoryQuerySchema,
  categorySuggestionBodySchema,
  createCategoryBodySchema,
  updateCategoryBodySchema,
} from "../schemas/category.http-schema.ts";

export type CategoryController = {
  list(input: typeof categoryQuerySchema.static): Promise<Category[]>;
  create(input: typeof createCategoryBodySchema.static): Promise<Result<Category, string>>;
  update(input: {
    id: string;
    values: typeof updateCategoryBodySchema.static;
  }): Promise<Result<Category, string>>;
  delete(id: string): Promise<Result<{ id: string }, string>>;
  suggest(
    input: typeof categorySuggestionBodySchema.static,
  ): Promise<{ suggestions: CategorySuggestion[] }>;
};

export function createCategoriesRouter(controller: CategoryController) {
  return new Elysia({ prefix: "/categories" })
    .get("/", ({ query }) => controller.list(query), { query: categoryQuerySchema })
    .post("/", async ({ body, set }) => {
      const result = await controller.create(body);
      if (!result.ok) {
        set.status = categoryErrorStatus(result.error.code);
        return { message: result.error.message };
      }
      set.status = 201;
      return result.value;
    }, { body: createCategoryBodySchema })
    .patch("/:id", async ({ params, body, set }) => {
      const result = await controller.update({ id: params.id, values: body });
      if (!result.ok) {
        set.status = categoryErrorStatus(result.error.code);
        return { message: result.error.message };
      }
      return result.value;
    }, { params: categoryIdParamsSchema, body: updateCategoryBodySchema })
    .delete("/:id", async ({ params, set }) => {
      const result = await controller.delete(params.id);
      if (!result.ok) {
        set.status = categoryErrorStatus(result.error.code);
        return { message: result.error.message };
      }
      return result.value;
    }, { params: categoryIdParamsSchema })
    .post("/suggest", ({ body }) => controller.suggest(body), {
      body: categorySuggestionBodySchema,
    });
}

function categoryErrorStatus(code: string): 400 | 403 | 404 | 409 {
  if (code === "duplicate_category") return 409;
  if (code === "system_category") return 403;
  if (code === "category_not_found" || code === "parent_not_found") return 404;
  return 400;
}
