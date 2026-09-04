import type {
  Category,
  CategoryDraft,
  CategoryUpdate,
  TransactionKind,
} from "../../domain/categories/category.ts";
import type { Result } from "../../domain/shared/result.ts";

export interface CategoryRepository {
  list(kind?: TransactionKind): Promise<Category[]>;
  findById(id: string): Promise<Category | null>;
  findByIds(ids: string[]): Promise<Category[]>;
  findDuplicate(
    kind: TransactionKind,
    parentId: string | null,
    name: string,
    excludeId?: string,
  ): Promise<boolean>;
  hasChild(id: string): Promise<boolean>;
  create(values: CategoryDraft): Promise<Result<Category, "duplicate_category">>;
  update(
    id: string,
    values: CategoryUpdate,
  ): Promise<Result<Category | null, "duplicate_category">>;
  delete(id: string): Promise<void>;
}
