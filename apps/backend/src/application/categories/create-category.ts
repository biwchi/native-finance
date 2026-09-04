import {
  createCategory as createCategoryModel,
  type Category,
  type CategoryValidationError,
  type TransactionKind,
} from "../../domain/categories/category.ts";
import { error, type Result } from "../../domain/shared/result.ts";
import type { CategoryRepository } from "./category.repository.ts";

type CreateCategoryInput = {
  name: string;
  kind: TransactionKind;
  parentId?: string;
  icon?: string;
  color?: string;
};

type CreateCategoryError =
  | CategoryValidationError
  | "duplicate_category";

export async function createCategory(
  input: CreateCategoryInput,
  dependencies: { categories: CategoryRepository },
): Promise<Result<Category, CreateCategoryError>> {
  const parent = input.parentId
    ? await dependencies.categories.findById(input.parentId)
    : null;
  const category = createCategoryModel(input, { parent });
  if (!category.ok) return category;

  if (await dependencies.categories.findDuplicate(
    category.value.kind,
    category.value.parentId,
    category.value.name,
  )) {
    return error("duplicate_category", "A category with this name already exists");
  }
  return dependencies.categories.create(category.value);
}
