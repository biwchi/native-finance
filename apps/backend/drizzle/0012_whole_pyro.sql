CREATE TABLE "exchange_rate_refreshes" (
	"key" text PRIMARY KEY NOT NULL,
	"fetched_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "recurrence_exclusions" (
	"id" uuid PRIMARY KEY NOT NULL,
	"schedule_id" uuid NOT NULL,
	"scheduled_for" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sync_changes" (
	"revision" bigint NOT NULL,
	"entity" text NOT NULL,
	"key" text NOT NULL,
	"version" bigint NOT NULL,
	"data" jsonb,
	CONSTRAINT "sync_changes_revision_entity_key_pk" PRIMARY KEY("revision","entity","key")
);
--> statement-breakpoint
CREATE TABLE "sync_receipts" (
	"client_id" uuid NOT NULL,
	"mutation_id" uuid NOT NULL,
	"digest" text NOT NULL,
	"response" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "sync_receipts_client_id_mutation_id_pk" PRIMARY KEY("client_id","mutation_id")
);
--> statement-breakpoint
CREATE TABLE "sync_records" (
	"entity" text NOT NULL,
	"key" text NOT NULL,
	"version" bigint NOT NULL,
	"data" jsonb,
	CONSTRAINT "sync_records_entity_key_pk" PRIMARY KEY("entity","key")
);
--> statement-breakpoint
CREATE TABLE "sync_workspace" (
	"id" integer PRIMARY KEY DEFAULT 1 NOT NULL,
	"workspace_id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"generation" integer DEFAULT 1 NOT NULL,
	"revision" bigint DEFAULT 0 NOT NULL
);
--> statement-breakpoint
DROP INDEX "transactions_schedule_occurrence_unique";--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "scheduled_for" timestamp with time zone;--> statement-breakpoint
CREATE UNIQUE INDEX "transactions_schedule_occurrence_unique" ON "transactions" USING btree ("recurring_schedule_id","scheduled_for") WHERE "transactions"."recurring_schedule_id" is not null;--> statement-breakpoint
UPDATE transactions SET scheduled_for = occurred_at WHERE recurring_schedule_id IS NOT NULL;
--> statement-breakpoint
INSERT INTO sync_workspace (id) VALUES (1);
--> statement-breakpoint
CREATE FUNCTION finance_sync_lock() RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE current_revision bigint;
BEGIN
  -- Lock before domain rows so concurrent commits have a stable global order.
  PERFORM 1 FROM sync_workspace WHERE id = 1 FOR UPDATE;
  current_revision := nullif(current_setting('finance.sync_revision', true), '')::bigint;
  IF current_revision IS NULL THEN
    UPDATE sync_workspace SET revision = revision + 1 WHERE id = 1 RETURNING revision INTO current_revision;
    PERFORM set_config('finance.sync_revision', current_revision::text, true);
  END IF;
  RETURN current_revision;
END $$;
--> statement-breakpoint
CREATE FUNCTION finance_sync_before() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM finance_sync_lock(); RETURN NULL; END $$;
--> statement-breakpoint
CREATE FUNCTION finance_sync_camel(source jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE result jsonb := '{}'; k text; v jsonb; target text; pieces text[]; i integer;
BEGIN
  FOR k, v IN SELECT * FROM jsonb_each(source) LOOP
    pieces := string_to_array(k, '_'); target := pieces[1];
    IF array_length(pieces, 1) > 1 THEN
      FOR i IN 2..array_length(pieces, 1) LOOP target := target || initcap(pieces[i]); END LOOP;
    END IF;
    IF v <> 'null'::jsonb AND k IN ('amount', 'monthly_limit', 'limit') THEN v := to_jsonb(v #>> '{}'); END IF;
    IF v <> 'null'::jsonb AND (k LIKE '%\_at' OR k = 'scheduled_for') THEN
      v := to_jsonb(to_char((v #>> '{}')::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
    END IF;
    result := result || jsonb_build_object(target, v);
  END LOOP;
  RETURN result;
END $$;
--> statement-breakpoint
CREATE FUNCTION finance_sync_capture(kind text, record_key text, value jsonb) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r bigint; edit_version bigint; previous sync_records%ROWTYPE;
BEGIN
  r := finance_sync_lock();
  SELECT * INTO previous FROM sync_records WHERE entity = kind AND key = record_key;
  IF FOUND AND previous.data IS NOT DISTINCT FROM value THEN RETURN; END IF;
  edit_version := r;
  IF kind = 'schedule' AND previous.data IS NOT NULL AND value IS NOT NULL AND
    previous.data - ARRAY['lastOccurrenceAt','nextOccurrenceAt','updatedAt'] = value - ARRAY['lastOccurrenceAt','nextOccurrenceAt','updatedAt'] THEN
    edit_version := previous.version;
  END IF;
  INSERT INTO sync_records (entity, key, version, data) VALUES (kind, record_key, edit_version, value)
    ON CONFLICT (entity, key) DO UPDATE SET version = excluded.version, data = excluded.data;
  INSERT INTO sync_changes (revision, entity, key, version, data) VALUES (r, kind, record_key, edit_version, value)
    ON CONFLICT (revision, entity, key) DO UPDATE SET version = excluded.version, data = excluded.data;
END $$;
--> statement-breakpoint
CREATE FUNCTION finance_sync_budget(plan_id uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE plan budget_plans%ROWTYPE; value jsonb; record_key text;
BEGIN
  SELECT * INTO plan FROM budget_plans WHERE id = $1;
  IF NOT FOUND THEN RETURN; END IF;
  record_key := coalesce(plan.account_id::text, 'all') || ':' || to_char(plan.month, 'YYYY-MM');
  value := finance_sync_camel(to_jsonb(plan)) || jsonb_build_object(
    'month', to_char(plan.month, 'YYYY-MM'),
    'groups', coalesce((SELECT jsonb_agg(finance_sync_camel(to_jsonb(g)) - ARRAY['planId','createdAt','updatedAt'] ORDER BY g.sort_order, g.id) FROM budget_groups g WHERE g.plan_id = $1), '[]'),
    'categoryAssignments', coalesce((SELECT jsonb_agg(finance_sync_camel(to_jsonb(a)) - ARRAY['id','planId','createdAt','updatedAt'] ORDER BY a.category_id) FROM budget_category_assignments a WHERE a.plan_id = $1), '[]'));
  PERFORM finance_sync_capture('budget', record_key, value);
END $$;
--> statement-breakpoint
CREATE FUNCTION finance_sync_after() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE value jsonb; previous jsonb; record_key text; target_plan uuid;
BEGIN
  IF TG_OP <> 'DELETE' THEN value := finance_sync_camel(to_jsonb(NEW)); END IF;
  IF TG_OP <> 'INSERT' THEN previous := finance_sync_camel(to_jsonb(OLD)); END IF;
  IF TG_TABLE_NAME = 'budget_plans' THEN
    IF TG_OP = 'DELETE' THEN
      record_key := coalesce(OLD.account_id::text, 'all') || ':' || to_char(OLD.month, 'YYYY-MM');
      PERFORM finance_sync_capture('budget', record_key, NULL);
    ELSE
      IF TG_OP = 'UPDATE' AND (OLD.account_id IS DISTINCT FROM NEW.account_id OR OLD.month <> NEW.month) THEN
        PERFORM finance_sync_capture('budget', coalesce(OLD.account_id::text, 'all') || ':' || to_char(OLD.month, 'YYYY-MM'), NULL);
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
DO $$
DECLARE pair text[];
BEGIN
  FOREACH pair SLICE 1 IN ARRAY ARRAY[
    ['accounts','account'],['categories','category'],['debts','debt'],
    ['transactions','transaction'],['recurring_schedules','schedule'],
    ['recurrence_exclusions','exclusion'],['budget_plans','budget'],
    ['budget_groups','budget'],['budget_category_assignments','budget']
  ] LOOP
    EXECUTE format('CREATE TRIGGER finance_sync_lock BEFORE INSERT OR UPDATE OR DELETE ON %I FOR EACH STATEMENT EXECUTE FUNCTION finance_sync_before()', pair[1]);
    EXECUTE format('CREATE TRIGGER finance_sync_capture AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION finance_sync_after(%L)', pair[1], pair[2]);
  END LOOP;
END $$;
--> statement-breakpoint
DO $$
DECLARE pair text[]; row_data jsonb; plan_id uuid;
BEGIN
  FOREACH pair SLICE 1 IN ARRAY ARRAY[
    ['accounts','account'],['categories','category'],['debts','debt'],
    ['transactions','transaction'],['recurring_schedules','schedule'],['recurrence_exclusions','exclusion']
  ] LOOP
    FOR row_data IN EXECUTE format('SELECT finance_sync_camel(to_jsonb(t)) FROM %I t', pair[1]) LOOP
      PERFORM finance_sync_capture(pair[2], row_data->>'id', row_data);
    END LOOP;
  END LOOP;
  FOR plan_id IN SELECT id FROM budget_plans LOOP PERFORM finance_sync_budget(plan_id); END LOOP;
END $$;
