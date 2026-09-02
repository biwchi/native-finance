import { describe, expect, it } from "bun:test";
import postgres from "postgres";

const migrationDescribe =
  Bun.env.RUN_MIGRATION_TESTS === "1" ? describe : describe.skip;

migrationDescribe("smart-entry migration preservation", () => {
  it("converts legacy categories and date-only timestamps without data loss", async () => {
    const databaseUrl = Bun.env.MIGRATION_TEST_DATABASE_URL;
    if (!databaseUrl) {
      throw new Error("MIGRATION_TEST_DATABASE_URL is required");
    }

    const databaseName = new URL(databaseUrl).pathname.slice(1);
    if (!databaseName.endsWith("_migration_test")) {
      throw new Error(
        "Refusing to reset a database whose name does not end in _migration_test",
      );
    }

    const client = postgres(databaseUrl, { max: 1, prepare: false });
    const accountId = "10000000-0000-0000-0000-000000000001";
    const transactionId = "20000000-0000-0000-0000-000000000001";

    try {
      await client.unsafe("drop schema public cascade");
      await client.unsafe("create schema public");
      await runMigration(client, "0000_slimy_thor.sql");
      await runMigration(client, "0001_aberrant_warbound.sql");

      await client`
        insert into accounts (id, name, type, currency)
        values (${accountId}, 'Legacy cash', 'cash', 'USD')
      `;
      await client`
        insert into transactions (
          id,
          account_id,
          kind,
          amount,
          currency,
          category,
          note,
          occurred_on
        ) values (
          ${transactionId},
          ${accountId},
          'expense',
          12.50,
          'USD',
          'Legacy Coffee',
          'old note',
          '2024-02-03'
        )
      `;

      await runMigration(client, "0002_careless_doctor_spectrum.sql");

      const [preserved] = await client<
        Array<{
          amount: string;
          categoryName: string;
          isSystem: boolean;
          note: string;
          occurredAt: Date;
        }>
      >`
        select
          transaction.amount,
          category.name as "categoryName",
          category.is_system as "isSystem",
          transaction.note,
          transaction.occurred_at as "occurredAt"
        from transactions as transaction
        left join categories as category
          on category.id = transaction.category_id
        where transaction.id = ${transactionId}
      `;
      const [counts] = await client<Array<{ systemCategories: number }>>`
        select count(*)::integer as "systemCategories"
        from categories
        where is_system = true
      `;
      const legacyColumns = await client<Array<{ columnName: string }>>`
        select column_name as "columnName"
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'transactions'
          and column_name in ('category', 'occurred_on')
      `;

      expect(preserved).toMatchObject({
        amount: "12.5000",
        categoryName: "Legacy Coffee",
        isSystem: false,
        note: "old note",
      });
      expect(preserved?.occurredAt.toISOString()).toBe(
        "2024-02-03T12:00:00.000Z",
      );
      expect(counts?.systemCategories).toBe(22);
      expect(legacyColumns.length).toBe(0);

      await client`
        update transactions
        set note = null, description = 'legacy description'
        where id = ${transactionId}
      `;
      for (const migration of [
        "0003_colorful_war_machine.sql",
        "0004_flaky_patriot.sql",
        "0005_late_doctor_faustus.sql",
        "0006_known_sabretooth.sql",
        "0007_whole_slapstick.sql",
        "0008_awesome_absorbing_man.sql",
        "0009_lively_zemo.sql",
      ]) {
        await runMigration(client, migration);
      }

      const [current] = await client<Array<{ note: string }>>`
        select note
        from transactions
        where id = ${transactionId}
      `;
      const removedDescriptionColumns = await client<
        Array<{ columnName: string }>
      >`
        select column_name as "columnName"
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'transactions'
          and column_name in ('description', 'normalized_description')
      `;

      expect(current?.note).toBe("legacy description");
      expect(removedDescriptionColumns).toHaveLength(0);
    } finally {
      await client.end();
    }
  });
});

async function runMigration(
  client: postgres.Sql,
  filename: string,
): Promise<void> {
  const url = new URL(`../../drizzle/${filename}`, import.meta.url);
  const sql = await Bun.file(url).text();

  for (const statement of sql.split("--> statement-breakpoint")) {
    const trimmed = statement.trim();
    if (trimmed) {
      await client.unsafe(trimmed);
    }
  }
}
