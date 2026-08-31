CREATE EXTENSION IF NOT EXISTS "pg_trgm";
--> statement-breakpoint
CREATE TABLE "categories" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"system_key" varchar(80),
	"name" varchar(80) NOT NULL,
	"kind" "transaction_kind" NOT NULL,
	"is_system" boolean DEFAULT false NOT NULL,
	"examples" text[] DEFAULT '{}'::text[] NOT NULL,
	"sort_order" integer DEFAULT 1000 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX "categories_system_key_unique" ON "categories" USING btree ("system_key");
--> statement-breakpoint
CREATE UNIQUE INDEX "categories_kind_name_unique" ON "categories" USING btree ("kind", lower("name"));
--> statement-breakpoint
CREATE INDEX "categories_kind_sort_order_idx" ON "categories" USING btree ("kind", "sort_order");
--> statement-breakpoint
INSERT INTO "categories" ("system_key", "name", "kind", "is_system", "examples", "sort_order") VALUES
('expense.food-drink', 'Food & Drink', 'expense', true, ARRAY['coffee','cafe','restaurant','lunch','dinner','takeaway','fast food','bakery'], 10),
('expense.groceries', 'Groceries', 'expense', true, ARRAY['supermarket','grocery store','vegetables','food market','food shopping','butcher','produce','pantry'], 20),
('expense.fuel', 'Fuel', 'expense', true, ARRAY['gas','gasoline','petrol','diesel','fuel station','service station','charging station','car fuel'], 30),
('expense.transport', 'Transport', 'expense', true, ARRAY['taxi','bus','train','subway','ride share','parking','toll road','public transit'], 40),
('expense.housing', 'Housing', 'expense', true, ARRAY['rent','mortgage','property maintenance','home repair','apartment','homeowners association','landlord','property fee'], 50),
('expense.utilities', 'Utilities', 'expense', true, ARRAY['electricity','water bill','heating','natural gas bill','internet bill','phone bill','waste collection','utility bill'], 60),
('expense.shopping', 'Shopping', 'expense', true, ARRAY['clothes','electronics','online order','department store','shoes','household goods','retail','purchase'], 70),
('expense.health', 'Health', 'expense', true, ARRAY['pharmacy','doctor','dentist','hospital','clinic','medicine','therapy','optician'], 80),
('expense.insurance', 'Insurance', 'expense', true, ARRAY['car insurance','health insurance','home insurance','life insurance','insurance premium','policy payment','insurer','coverage'], 90),
('expense.entertainment', 'Entertainment', 'expense', true, ARRAY['cinema','movie','concert','video game','museum','streaming rental','nightclub','event ticket'], 100),
('expense.education', 'Education', 'expense', true, ARRAY['school','tuition','course','textbooks','training','university','class','exam fee'], 110),
('expense.travel', 'Travel', 'expense', true, ARRAY['hotel','flight','vacation','luggage','travel booking','hostel','resort','sightseeing'], 120),
('expense.subscriptions', 'Subscriptions', 'expense', true, ARRAY['video subscription','music subscription','membership','software subscription','monthly plan','cloud storage','newspaper subscription','app subscription'], 130),
('expense.fees-charges', 'Fees & Charges', 'expense', true, ARRAY['bank fee','service charge','commission','late fee','atm fee','interest charge','penalty','transaction fee'], 140),
('expense.gifts-donations', 'Gifts & Donations', 'expense', true, ARRAY['charity','donation','present','birthday gift','fundraiser','nonprofit','church donation','gift for friend'], 150),
('expense.other', 'Other', 'expense', true, ARRAY['miscellaneous','uncategorized','unknown expense','cash expense'], 160),
('income.salary', 'Salary', 'income', true, ARRAY['salary','paycheck','wages','payroll','bonus','employer payment','monthly pay','compensation'], 10),
('income.business-freelance', 'Business & Freelance', 'income', true, ARRAY['freelance','client payment','invoice paid','consulting','side job','business income','contract work','sales revenue'], 20),
('income.investments', 'Investments', 'income', true, ARRAY['dividend','interest income','capital gain','investment return','bond interest','stock income','portfolio payout','savings interest'], 30),
('income.refunds', 'Refunds', 'income', true, ARRAY['refund','reimbursement','cashback','returned purchase','chargeback','rebate','tax refund','repayment'], 40),
('income.gifts-received', 'Gifts Received', 'income', true, ARRAY['gift received','birthday money','family gift','cash gift','present money','donation received','inheritance','prize'], 50),
('income.other', 'Other', 'income', true, ARRAY['other income','cash income','deposit','credit received','money received','incoming payment','windfall','unknown income'], 60)
ON CONFLICT DO NOTHING;
--> statement-breakpoint
INSERT INTO "categories" ("name", "kind", "is_system", "examples", "sort_order")
SELECT DISTINCT trim("category"), "kind", false, '{}'::text[], 1000
FROM "transactions"
WHERE "category" IS NOT NULL AND trim("category") <> ''
ON CONFLICT DO NOTHING;
--> statement-breakpoint
DROP INDEX "transactions_occurred_on_idx";
--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "category_id" uuid;
--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "description" text;
--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "normalized_description" text;
--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "occurred_at" timestamp with time zone;
--> statement-breakpoint
UPDATE "transactions" AS "transaction"
SET "category_id" = "category"."id"
FROM "categories" AS "category"
WHERE "transaction"."category" IS NOT NULL
  AND trim("transaction"."category") <> ''
  AND "category"."kind" = "transaction"."kind"
  AND lower("category"."name") = lower(trim("transaction"."category"));
--> statement-breakpoint
UPDATE "transactions"
SET "occurred_at" = ("occurred_on"::timestamp + interval '12 hours') AT TIME ZONE 'UTC';
--> statement-breakpoint
ALTER TABLE "transactions" ALTER COLUMN "occurred_at" SET NOT NULL;
--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_category_id_categories_id_fk" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE set null ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "transactions_category_id_idx" ON "transactions" USING btree ("category_id");
--> statement-breakpoint
CREATE INDEX "transactions_occurred_at_idx" ON "transactions" USING btree ("occurred_at");
--> statement-breakpoint
CREATE INDEX "transactions_kind_normalized_description_idx" ON "transactions" USING btree ("kind", "normalized_description");
--> statement-breakpoint
CREATE INDEX "transactions_normalized_description_trgm_idx" ON "transactions" USING gist ("normalized_description" gist_trgm_ops) WHERE "transactions"."normalized_description" is not null;
--> statement-breakpoint
ALTER TABLE "transactions" DROP COLUMN "category";
--> statement-breakpoint
ALTER TABLE "transactions" DROP COLUMN "occurred_on";
