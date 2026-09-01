import { and, asc, desc, eq, isNull, ne, sql } from "drizzle-orm";
import { Elysia, t } from "elysia";

import { db } from "../db/client.ts";
import { categories, transactions } from "../db/schema.ts";
import {
  normalizeTransactionDescription,
  rankHistoryMatches,
  type HistoryMatch,
} from "../services/category-resolution.ts";

export const transactionKindSchema = t.Union([
  t.Literal("expense"),
  t.Literal("income"),
]);

const categoryColorSchema = t.Union([
  t.Literal("red"),
  t.Literal("coral"),
  t.Literal("orange"),
  t.Literal("amber"),
  t.Literal("yellow"),
  t.Literal("lime"),
  t.Literal("green"),
  t.Literal("mint"),
  t.Literal("teal"),
  t.Literal("turquoise"),
  t.Literal("cyan"),
  t.Literal("sky"),
  t.Literal("blue"),
  t.Literal("navy"),
  t.Literal("indigo"),
  t.Literal("violet"),
  t.Literal("purple"),
  t.Literal("lavender"),
  t.Literal("pink"),
  t.Literal("rose"),
  t.Literal("brown"),
  t.Literal("slate"),
  t.Literal("gray"),
]);

type FuzzyHistoryRow = {
  categoryId: string;
  similarity: number;
  createdAt: Date | string;
};

export const categoriesRoutes = new Elysia({ prefix: "/categories" })
  .get(
    "/",
    ({ query }) => {
      const filters = query.kind
        ? eq(categories.kind, query.kind)
        : undefined;

      return db
        .select()
        .from(categories)
        .where(filters)
        .orderBy(
          asc(categories.kind),
          asc(categories.sortOrder),
          asc(categories.name),
        );
    },
    {
      query: t.Object({
        kind: t.Optional(transactionKindSchema),
      }),
    },
  )
  .post(
    "/",
    async ({ body, set }) => {
      const name = body.name.trim();

      if (!name) {
        set.status = 400;
        return { message: "Category name cannot be empty" };
      }

      let parent: { id: string; kind: "expense" | "income"; parentId: string | null } | undefined;
      if (body.parentId) {
        [parent] = await db
          .select({
            id: categories.id,
            kind: categories.kind,
            parentId: categories.parentId,
          })
          .from(categories)
          .where(eq(categories.id, body.parentId))
          .limit(1);

        if (!parent) {
          set.status = 404;
          return { message: "Parent category not found" };
        }
        if (parent.parentId) {
          set.status = 400;
          return { message: "Subcategories can only be one level deep" };
        }
        if (parent.kind !== body.kind) {
          set.status = 400;
          return { message: "Subcategory type must match its parent" };
        }
      }

      const parentFilter = body.parentId
        ? eq(categories.parentId, body.parentId)
        : isNull(categories.parentId);
      const [duplicate] = await db
        .select({ id: categories.id })
        .from(categories)
        .where(
          and(
            eq(categories.kind, body.kind),
            parentFilter,
            sql`lower(${categories.name}) = ${name.toLocaleLowerCase("en-US")}`,
          ),
        )
        .limit(1);

      if (duplicate) {
        set.status = 409;
        return { message: "A category with this name already exists" };
      }

      try {
        const [category] = await db
          .insert(categories)
          .values({
            name,
            kind: body.kind,
            parentId: parent?.id,
            icon: body.icon ?? "tag.fill",
            color: body.color ?? "gray",
            isSystem: false,
            examples: [],
            sortOrder: 1_000,
          })
          .returning();

        set.status = 201;
        return category;
      } catch (error) {
        if (isUniqueViolation(error)) {
          set.status = 409;
          return { message: "A category with this name already exists" };
        }

        throw error;
      }
    },
    {
      body: t.Object({
        name: t.String({ minLength: 1, maxLength: 80 }),
        kind: transactionKindSchema,
        parentId: t.Optional(t.String({ format: "uuid" })),
        icon: t.Optional(t.String({ minLength: 1, maxLength: 80 })),
        color: t.Optional(categoryColorSchema),
      }),
    },
  )
  .patch(
    "/:id",
    async ({ params, body, set }) => {
      const name = body.name.trim();

      if (!name) {
        set.status = 400;
        return { message: "Category name cannot be empty" };
      }

      const [existing] = await db
        .select({
          kind: categories.kind,
          parentId: categories.parentId,
          icon: categories.icon,
          color: categories.color,
        })
        .from(categories)
        .where(eq(categories.id, params.id))
        .limit(1);

      if (!existing) {
        set.status = 404;
        return { message: "Category not found" };
      }

      const parentId =
        body.parentId === undefined ? existing.parentId : body.parentId;

      if (parentId === params.id) {
        set.status = 400;
        return { message: "A category cannot be its own parent" };
      }

      if (parentId) {
        const [parent] = await db
          .select({
            kind: categories.kind,
            parentId: categories.parentId,
          })
          .from(categories)
          .where(eq(categories.id, parentId))
          .limit(1);

        if (!parent) {
          set.status = 404;
          return { message: "Parent category not found" };
        }
        if (parent.parentId) {
          set.status = 400;
          return { message: "Subcategories can only be one level deep" };
        }
        if (parent.kind !== existing.kind) {
          set.status = 400;
          return { message: "Subcategory type must match its parent" };
        }

        if (parentId !== existing.parentId) {
          const [child] = await db
            .select({ id: categories.id })
            .from(categories)
            .where(eq(categories.parentId, params.id))
            .limit(1);

          if (child) {
            set.status = 400;
            return {
              message: "Move or delete this category's subcategories first",
            };
          }
        }
      }

      const [duplicate] = await db
        .select({ id: categories.id })
        .from(categories)
        .where(
          and(
            eq(categories.kind, existing.kind),
            parentId
              ? eq(categories.parentId, parentId)
              : isNull(categories.parentId),
            ne(categories.id, params.id),
            sql`lower(${categories.name}) = ${name.toLocaleLowerCase("en-US")}`,
          ),
        )
        .limit(1);

      if (duplicate) {
        set.status = 409;
        return { message: "A category with this name already exists" };
      }

      try {
        const [category] = await db
          .update(categories)
          .set({
            name,
            parentId,
            icon: body.icon ?? existing.icon,
            color: body.color ?? existing.color,
            updatedAt: new Date(),
          })
          .where(eq(categories.id, params.id))
          .returning();

        return category;
      } catch (error) {
        if (isUniqueViolation(error)) {
          set.status = 409;
          return { message: "A category with this name already exists" };
        }
        throw error;
      }
    },
    {
      params: t.Object({ id: t.String({ format: "uuid" }) }),
      body: t.Object({
        name: t.String({ minLength: 1, maxLength: 80 }),
        parentId: t.Optional(
          t.Union([t.String({ format: "uuid" }), t.Null()]),
        ),
        icon: t.Optional(t.String({ minLength: 1, maxLength: 80 })),
        color: t.Optional(categoryColorSchema),
      }),
    },
  )
  .delete(
    "/:id",
    async ({ params, set }) => {
      const [existing] = await db
        .select({ isSystem: categories.isSystem })
        .from(categories)
        .where(eq(categories.id, params.id))
        .limit(1);

      if (!existing) {
        set.status = 404;
        return { message: "Category not found" };
      }

      if (existing.isSystem) {
        set.status = 403;
        return { message: "Built-in categories cannot be deleted" };
      }

      await db.delete(categories).where(eq(categories.id, params.id));
      return { id: params.id };
    },
    {
      params: t.Object({ id: t.String({ format: "uuid" }) }),
    },
  )
  .post(
    "/suggest",
    async ({ body }) => {
      const normalizedDescription = normalizeTransactionDescription(
        body.description,
      );

      if (!normalizedDescription) {
        return { suggestions: [] };
      }

      const [exact] = await db
        .select({
          categoryId: transactions.categoryId,
        })
        .from(transactions)
        .where(
          and(
            eq(transactions.kind, body.kind),
            eq(transactions.normalizedDescription, normalizedDescription),
            sql`${transactions.categoryId} is not null`,
          ),
        )
        .orderBy(desc(transactions.createdAt))
        .limit(1);

      if (exact?.categoryId) {
        return {
          suggestions: [
            {
              categoryId: exact.categoryId,
              score: 1,
              source: "exact_history" as const,
            },
          ],
        };
      }

      const result = await db.execute(sql<FuzzyHistoryRow>`
        select
          ${transactions.categoryId} as "categoryId",
          greatest(
            similarity(${transactions.normalizedDescription}, ${normalizedDescription}),
            strict_word_similarity(${normalizedDescription}, ${transactions.normalizedDescription})
          )::double precision as "similarity",
          ${transactions.createdAt} as "createdAt"
        from ${transactions}
        where ${transactions.kind} = ${body.kind}
          and ${transactions.categoryId} is not null
          and ${transactions.normalizedDescription} is not null
          and (
            ${transactions.normalizedDescription} % ${normalizedDescription}
            or ${normalizedDescription} <<% ${transactions.normalizedDescription}
          )
        order by "similarity" desc, ${transactions.createdAt} desc
        limit 50
      `);

      const rows = [...result] as unknown as FuzzyHistoryRow[];
      const matches: HistoryMatch[] = rows.map((row) => ({
        categoryId: row.categoryId,
        similarity: Number(row.similarity),
        createdAt:
          row.createdAt instanceof Date
            ? row.createdAt
            : new Date(row.createdAt),
      }));

      return { suggestions: rankHistoryMatches(matches) };
    },
    {
      body: t.Object({
        description: t.String({ minLength: 1, maxLength: 2_000 }),
        kind: transactionKindSchema,
      }),
    },
  );

function isUniqueViolation(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "23505"
  );
}
