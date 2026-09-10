import { describe, expect, it } from "bun:test";
import postgres from "postgres";

const migrationDescribe =
  Bun.env.RUN_MIGRATION_TESTS === "1" ? describe : describe.skip;

migrationDescribe("finance migration preservation", () => {
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

      await runMigration(client, "0010_youthful_pretty_boy.sql");
      await runMigration(client, "0011_woozy_leo.sql");
      const scheduleId = "30000000-0000-0000-0000-000000000001";
      const budgetId = "40000000-0000-0000-0000-000000000001";
      const groupId = "50000000-0000-0000-0000-000000000001";
      await client`insert into recurring_schedules(id,account_id,kind,amount,currency,frequency,start_at,last_occurrence_at,next_occurrence_at)
        values (${scheduleId},${accountId},'expense',12.50,'USD','monthly','2024-02-03T12:00:00Z','2024-02-03T12:00:00Z','2024-03-03T12:00:00Z')`;
      await client`update transactions set recurring_schedule_id=${scheduleId} where id=${transactionId}`;
      await client`insert into budget_plans(id,account_id,month,currency,monthly_limit) values (${budgetId},${accountId},'2024-02-01','USD',500.1250)`;
      await client`insert into budget_groups(id,plan_id,name,"limit") values (${groupId},${budgetId},'Essentials',200)`;
      await runMigration(client, "0012_whole_pyro.sql");
      await runMigration(client, "0013_curious_wrecker.sql");
      const imported = await client`select entity,key,data from sync_records where data is not null`;
      expect(imported.find(r => r.key === transactionId)?.data).toMatchObject({ id: transactionId, amount: "12.5000", scheduledFor: "2024-02-03T12:00:00.000Z", note: "legacy description" });
      expect(imported.find(r => r.key === scheduleId)?.data).toMatchObject({ id: scheduleId, nextOccurrenceAt: "2024-03-03T12:00:00.000Z", frequency: "monthly" });
      expect(imported.find(r => r.entity === "budget")?.data).toMatchObject({ id: budgetId, month: "2024-02", monthlyLimit: "500.1250", groups: [{ id: groupId, name: "Essentials", limit: "200.0000", sortOrder: 0 }] });
      // The most recently edited setup wins even when it was saved for an older month.
      const newerBudgetId = "40000000-0000-0000-0000-000000000002";
      const globalId = "40000000-0000-0000-0000-000000000003";
      const supersededGlobalId = "40000000-0000-0000-0000-000000000004";
      const categoryId = imported.find(r => r.entity === "category")!.data.id;
      await client`update budget_plans set updated_at='2026-01-01T00:00:00Z' where id=${budgetId}`;
      await client`insert into budget_plans(id,account_id,month,currency,monthly_limit,updated_at) values
        (${newerBudgetId},${accountId},'2024-01-01','USD',750,'2026-02-01T00:00:00Z'),
        (${globalId},null,'2024-01-01','USD',2000,'2026-02-01T00:00:00Z'),
        (${supersededGlobalId},null,'2024-02-01','USD',1000,'2026-01-01T00:00:00Z')`;
      await client`update budget_groups set plan_id=${newerBudgetId} where id=${groupId}`;
      await client`insert into budget_category_assignments(plan_id,category_id,group_id,"limit") values (${newerBudgetId},${categoryId},${groupId},75)`;
      const [beforeGlobal] = await client`select revision from sync_workspace where id=1`;
      await runMigration(client, "0014_global_budget.sql");
      const plans = await client`select * from budget_plans`;
      expect(plans).toHaveLength(2);
      expect(plans.find(r => r.id === newerBudgetId)?.monthly_limit).toBe("750.0000");
      expect(plans.every(r => !("month" in r))).toBe(true);
      const globalRecords = await client`select key,data from sync_records where entity='budget' and data is not null`;
      expect(globalRecords.map(r => r.key).sort()).toEqual([accountId, "all"].sort());
      expect(globalRecords.find(r => r.key === accountId)?.data).toMatchObject({ id: newerBudgetId, groups: [{ id: groupId, limit: "200.0000" }], categoryAssignments: [{ categoryId, groupId, limit: "75.0000" }] });
      expect(globalRecords.every(r => !("month" in r.data))).toBe(true);
      const retired = await client`select data from sync_records where entity='budget' and key like '%:%'`;
      expect(retired.length).toBeGreaterThan(0);
      expect(retired.every(r => r.data === null)).toBe(true);
      const migrationChanges = await client`select key,data from sync_changes where entity='budget' and revision > ${beforeGlobal!.revision}`;
      expect(migrationChanges.some(r => r.key === accountId && r.data?.id === newerBudgetId)).toBe(true);
      // Both account-specific and All Accounts uniqueness are enforced by storage.
      await expect((async () => { await client`insert into budget_plans(account_id,currency) values (${accountId},'USD')`; })()).rejects.toThrow();
      await expect((async () => { await client`insert into budget_plans(currency) values ('USD')`; })()).rejects.toThrow();
      const [ledger] = await client`select count(*)::int as count from transactions where id=${transactionId}`;
      expect(ledger?.count).toBe(1);

    } finally {
      await client.end();
    }
  }, 30_000);
});

async function runMigration(
  client: postgres.Sql,
  filename: string,
): Promise<void> {
  const url = new URL(`../../drizzle/${filename}`, import.meta.url);
  const sql = await Bun.file(url).text();

  await client.begin(async (transaction) => {
    for (const statement of sql.split("--> statement-breakpoint")) {
      const trimmed = statement.trim();
      if (trimmed) await transaction.unsafe(trimmed);
    }
  });
}
