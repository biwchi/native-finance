ALTER TABLE "accounts" ADD COLUMN "initial_balance" numeric(19, 4) DEFAULT '0' NOT NULL;--> statement-breakpoint
ALTER TABLE "accounts" DROP COLUMN "type";--> statement-breakpoint
DROP TYPE "public"."account_type";
--> statement-breakpoint
CREATE OR REPLACE FUNCTION finance_sync_camel(source jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE result jsonb := '{}'; k text; v jsonb; target text; pieces text[]; i integer;
BEGIN
  FOR k, v IN SELECT * FROM jsonb_each(source) LOOP
    pieces := string_to_array(k, '_'); target := pieces[1];
    IF array_length(pieces, 1) > 1 THEN
      FOR i IN 2..array_length(pieces, 1) LOOP target := target || initcap(pieces[i]); END LOOP;
    END IF;
    IF v <> 'null'::jsonb AND k IN ('amount', 'monthly_limit', 'limit', 'initial_balance') THEN v := to_jsonb(v #>> '{}'); END IF;
    IF v <> 'null'::jsonb AND (k LIKE '%\_at' OR k = 'scheduled_for') THEN
      v := to_jsonb(to_char((v #>> '{}')::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
    END IF;
    result := result || jsonb_build_object(target, v);
  END LOOP;
  RETURN result;
END $$;
--> statement-breakpoint
-- Refresh account snapshots and the change feed with the new decimal string field.
-- Existing account balances start at zero; transaction amounts stay unchanged.
UPDATE accounts SET updated_at = updated_at;
