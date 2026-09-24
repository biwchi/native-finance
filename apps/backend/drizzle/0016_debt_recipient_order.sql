ALTER TABLE "debts" ADD COLUMN "sort_order" integer DEFAULT 0 NOT NULL;
--> statement-breakpoint
-- Preserve the existing alphabetical list and publish positions through sync.
WITH positions AS (
    SELECT id, (row_number() OVER (ORDER BY lower(name), id) - 1)::integer AS position
    FROM debts
)
UPDATE debts SET sort_order = positions.position
FROM positions WHERE debts.id = positions.id;
