ALTER TABLE "recurring_schedules" ADD COLUMN "next_scheduled_for" timestamp with time zone;
--> statement-breakpoint
CREATE OR REPLACE FUNCTION finance_sync_camel(source jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE result jsonb := '{}'; k text; v jsonb; target text; pieces text[]; i integer;
BEGIN
  FOR k, v IN SELECT * FROM jsonb_each(source) LOOP
    pieces := string_to_array(k, '_'); target := pieces[1];
    IF array_length(pieces, 1) > 1 THEN
      FOR i IN 2..array_length(pieces, 1) LOOP target := target || initcap(pieces[i]); END LOOP;
    END IF;
    IF v <> 'null'::jsonb AND k IN ('amount', 'monthly_limit', 'limit') THEN v := to_jsonb(v #>> '{}'); END IF;
    IF v <> 'null'::jsonb AND (k LIKE '%\_at' OR k IN ('scheduled_for', 'next_scheduled_for')) THEN
      v := to_jsonb(to_char((v #>> '{}')::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
    END IF;
    result := result || jsonb_build_object(target, v);
  END LOOP;
  RETURN result;
END $$;
--> statement-breakpoint
CREATE OR REPLACE FUNCTION finance_sync_capture(kind text, record_key text, value jsonb) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r bigint; edit_version bigint; previous sync_records%ROWTYPE;
BEGIN
  r := finance_sync_lock();
  SELECT * INTO previous FROM sync_records WHERE entity = kind AND key = record_key;
  IF FOUND AND previous.data IS NOT DISTINCT FROM value THEN RETURN; END IF;
  edit_version := r;
  IF kind = 'schedule' AND previous.data IS NOT NULL AND value IS NOT NULL AND
    previous.data - ARRAY['lastOccurrenceAt','nextOccurrenceAt','nextScheduledFor','updatedAt'] = value - ARRAY['lastOccurrenceAt','nextOccurrenceAt','nextScheduledFor','updatedAt'] THEN
    edit_version := previous.version;
  END IF;
  INSERT INTO sync_records (entity, key, version, data) VALUES (kind, record_key, edit_version, value)
    ON CONFLICT (entity, key) DO UPDATE SET version = excluded.version, data = excluded.data;
  INSERT INTO sync_changes (revision, entity, key, version, data) VALUES (r, kind, record_key, edit_version, value)
    ON CONFLICT (revision, entity, key) DO UPDATE SET version = excluded.version, data = excluded.data;
END $$;
--> statement-breakpoint
UPDATE recurring_schedules SET next_scheduled_for = NULL;
