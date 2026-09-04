import { and, asc, eq, inArray, isNull, ne, sql } from "drizzle-orm";

import type { CategoryRepository } from "../../../application/categories/category.repository.ts";
import { ok, tryCatch } from "../../../domain/shared/result.ts";
import type { Database } from "../client.ts";
import { categories } from "../schema/category.schema.ts";

export function createDrizzleCategoryRepository(
  database: Database,
): CategoryRepository {
  return {
    list(kind) {
      return database
        .select()
        .from(categories)
        .where(kind ? eq(categories.kind, kind) : undefined)
        .orderBy(asc(categories.kind), asc(categories.sortOrder), asc(categories.name));
    },

    async findById(id) {
      const [category] = await database
        .select()
        .from(categories)
        .where(eq(categories.id, id))
        .limit(1);
      return category ?? null;
    },

    findByIds(ids) {
      if (ids.length === 0) return Promise.resolve([]);
      return database.select().from(categories).where(inArray(categories.id, ids));
    },

    async findDuplicate(kind, parentId, name, excludeId) {
      const [duplicate] = await database
        .select({ id: categories.id })
        .from(categories)
        .where(and(
          eq(categories.kind, kind),
          parentId ? eq(categories.parentId, parentId) : isNull(categories.parentId),
          excludeId ? ne(categories.id, excludeId) : undefined,
          sql`lower(${categories.name}) = ${name.toLocaleLowerCase("en-US")}`,
        ))
        .limit(1);
      return Boolean(duplicate);
    },

    async hasChild(id) {
      const [child] = await database
        .select({ id: categories.id })
        .from(categories)
        .where(eq(categories.parentId, id))
        .limit(1);
      return Boolean(child);
    },

    async create(values) {
      const result = await writeCategory(() => database
        .insert(categories)
        .values({ ...values, isSystem: false, examples: [], sortOrder: 1_000 })
        .returning());
      if (!result.ok) return result;
      if (!result.value) throw new Error("Category insert did not return a row");
      return ok(result.value);
    },

    async update(id, values) {
      return writeCategory(() => database
        .update(categories)
        .set({ ...values, updatedAt: new Date() })
        .where(eq(categories.id, id))
        .returning());
    },

    async delete(id) {
      await database.delete(categories).where(eq(categories.id, id));
    },
  };
}

async function writeCategory(
  write: () => PromiseLike<Array<typeof categories.$inferSelect>>,
) {
  return tryCatch(async () => {
    const [category] = await write();
    return category ?? null;
  }, (cause) => isUniqueViolation(cause)
    ? {
        code: "duplicate_category" as const,
        message: "A category with this name already exists",
      }
    : null);
}

function isUniqueViolation(error: unknown): boolean {
  return typeof error === "object" && error !== null &&
    "code" in error && error.code === "23505";
}
