-- Keep the most recently edited setup for each account, including All Accounts.
-- Pool and assignment cascades remove only the superseded setups.
WITH ranked AS (
  SELECT id, row_number() OVER (PARTITION BY account_id ORDER BY updated_at DESC, id DESC) AS position
  FROM budget_plans
)
DELETE FROM budget_plans WHERE id IN (SELECT id FROM ranked WHERE position > 1);
--> statement-breakpoint
-- Retire old identities so existing devices can advance their cursors safely.
DO $$
DECLARE old_key text;
BEGIN
  FOR old_key IN SELECT key FROM sync_records WHERE entity = 'budget' AND key LIKE '%:%' AND data IS NOT NULL LOOP
    PERFORM finance_sync_capture('budget', old_key, NULL);
  END LOOP;
END $$;
--> statement-breakpoint
CREATE OR REPLACE FUNCTION finance_sync_budget(plan_id uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE plan budget_plans%ROWTYPE; value jsonb; record_key text;
BEGIN
  SELECT * INTO plan FROM budget_plans WHERE id = $1;
  IF NOT FOUND THEN RETURN; END IF;
  record_key := coalesce(plan.account_id::text, 'all');
  value := finance_sync_camel(to_jsonb(plan)) || jsonb_build_object(
    'groups', coalesce((SELECT jsonb_agg(finance_sync_camel(to_jsonb(g)) - ARRAY['planId','createdAt','updatedAt'] ORDER BY g.sort_order, g.id) FROM budget_groups g WHERE g.plan_id = $1), '[]'),
    'categoryAssignments', coalesce((SELECT jsonb_agg(finance_sync_camel(to_jsonb(a)) - ARRAY['id','planId','createdAt','updatedAt'] ORDER BY a.category_id) FROM budget_category_assignments a WHERE a.plan_id = $1), '[]'));
  PERFORM finance_sync_capture('budget', record_key, value);
END $$;
--> statement-breakpoint
CREATE OR REPLACE FUNCTION finance_sync_after() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE value jsonb; previous jsonb; record_key text; target_plan uuid;
BEGIN
  IF TG_OP <> 'DELETE' THEN value := finance_sync_camel(to_jsonb(NEW)); END IF;
  IF TG_OP <> 'INSERT' THEN previous := finance_sync_camel(to_jsonb(OLD)); END IF;
  IF TG_TABLE_NAME = 'budget_plans' THEN
    IF TG_OP = 'DELETE' THEN
      record_key := coalesce(OLD.account_id::text, 'all');
      PERFORM finance_sync_capture('budget', record_key, NULL);
    ELSE
      IF TG_OP = 'UPDATE' AND OLD.account_id IS DISTINCT FROM NEW.account_id THEN
        PERFORM finance_sync_capture('budget', coalesce(OLD.account_id::text, 'all'), NULL);
      END IF;
      PERFORM finance_sync_budget(NEW.id);
    END IF;
  ELSIF TG_TABLE_NAME IN ('budget_groups','budget_category_assignments') THEN
    IF TG_OP <> 'INSERT' THEN PERFORM finance_sync_budget(OLD.plan_id); END IF;
    IF TG_OP <> 'DELETE' THEN PERFORM finance_sync_budget(NEW.plan_id); END IF;
  ELSE
    record_key := coalesce(value->>'id', previous->>'id');
    PERFORM finance_sync_capture(TG_ARGV[0], record_key, value);
  END IF;
  RETURN NULL;
END $$;
--> statement-breakpoint
DROP INDEX "budget_plans_account_month_unique";--> statement-breakpoint
DROP INDEX "budget_plans_all_accounts_month_unique";--> statement-breakpoint
CREATE UNIQUE INDEX "budget_plans_account_unique" ON "budget_plans" USING btree ("account_id") WHERE "budget_plans"."account_id" is not null;--> statement-breakpoint
CREATE UNIQUE INDEX "budget_plans_all_accounts_unique" ON "budget_plans" USING btree ((true)) WHERE "budget_plans"."account_id" is null;--> statement-breakpoint
ALTER TABLE "budget_plans" DROP COLUMN "month";
--> statement-breakpoint
DO $$
DECLARE plan_id uuid;
BEGIN
  FOR plan_id IN SELECT id FROM budget_plans LOOP PERFORM finance_sync_budget(plan_id); END LOOP;
END $$;
