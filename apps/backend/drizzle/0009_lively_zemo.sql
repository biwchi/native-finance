CREATE TYPE "public"."recurrence_frequency" AS ENUM('daily', 'weekly', 'monthly', 'yearly');--> statement-breakpoint
CREATE TABLE "recurring_schedules" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"account_id" uuid NOT NULL,
	"kind" "transaction_kind" NOT NULL,
	"amount" numeric(19, 4) NOT NULL,
	"currency" varchar(3) NOT NULL,
	"category_id" uuid,
	"merchant" text,
	"payee" text,
	"note" text,
	"frequency" "recurrence_frequency" NOT NULL,
	"start_at" timestamp with time zone NOT NULL,
	"last_occurrence_at" timestamp with time zone NOT NULL,
	"next_occurrence_at" timestamp with time zone,
	"end_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "recurring_schedules_end_after_start" CHECK ("recurring_schedules"."end_at" is null or "recurring_schedules"."end_at" >= "recurring_schedules"."start_at")
);
--> statement-breakpoint
UPDATE "transactions"
SET "note" = COALESCE(NULLIF(BTRIM("note"), ''), NULLIF(BTRIM("description"), ''))
WHERE "description" IS NOT NULL;--> statement-breakpoint
DROP INDEX "transactions_kind_normalized_description_idx";--> statement-breakpoint
DROP INDEX "transactions_normalized_description_trgm_idx";--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "recurring_schedule_id" uuid;--> statement-breakpoint
ALTER TABLE "recurring_schedules" ADD CONSTRAINT "recurring_schedules_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recurring_schedules" ADD CONSTRAINT "recurring_schedules_category_id_categories_id_fk" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "recurring_schedules_next_occurrence_at_idx" ON "recurring_schedules" USING btree ("next_occurrence_at");--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_recurring_schedule_id_recurring_schedules_id_fk" FOREIGN KEY ("recurring_schedule_id") REFERENCES "public"."recurring_schedules"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "transactions_recurring_schedule_id_idx" ON "transactions" USING btree ("recurring_schedule_id");--> statement-breakpoint
CREATE UNIQUE INDEX "transactions_schedule_occurrence_unique" ON "transactions" USING btree ("recurring_schedule_id","occurred_at") WHERE "transactions"."recurring_schedule_id" is not null;--> statement-breakpoint
ALTER TABLE "transactions" DROP COLUMN "description";--> statement-breakpoint
ALTER TABLE "transactions" DROP COLUMN "normalized_description";
