import {
  updateCategory as updateCategoryModel,
  type Category,
  type CategoryValidationError,
} from "../../domain/categories/category.ts";
import { error, ok, type Result } from "../../domain/shared/result.ts";
import type { CategoryRepository } from "./category.repository.ts";

type UpdateCategoryInput = {
  id: string;
  name: string;
  parentId?: string | null;
  icon?: string;
  color?: string;
};

type UpdateCategoryError =
  | "category_not_found"
  | CategoryValidationError
  | "duplicate_category";

export async function updateCategory(
  input: UpdateCategoryInput,
  dependencies: { categories: CategoryRepository },
): Promise<Result<Category, UpdateCategoryError>> {
  const existing = await dependencies.categories.findById(input.id);
  if (!existing) return error("category_not_found", "Category not found");

  const parentId = input.parentId === undefined ? existing.parentId : input.parentId;
  const [parent, hasChildren] = await Promise.all([
    parentId ? dependencies.categories.findById(parentId) : Promise.resolve(null),
    parentId && parentId !== existing.parentId
      ? dependencies.categories.hasChild(input.id)
      : Promise.resolve(false),
  ]);
  const category = updateCategoryModel(
    { ...input, parentId },
    { existing, parent, hasChildren },
  );
  if (!category.ok) return category;

  if (await dependencies.categories.findDuplicate(
    existing.kind,
    parentId,
    category.value.name,
    input.id,
  )) {
    return error("duplicate_category", "A category with this name already exists");
  }

  const saved = await dependencies.categories.update(input.id, category.value);
  if (!saved.ok) return saved;
  return saved.value
    ? ok(saved.value)
    : error("category_not_found", "Category not found");
}
