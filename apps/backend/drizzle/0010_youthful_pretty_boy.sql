ALTER TYPE "public"."transaction_kind" ADD VALUE 'debt';--> statement-breakpoint
CREATE TABLE "debts" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL
);
--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "debt_id" uuid;--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_debt_id_debts_id_fk" FOREIGN KEY ("debt_id") REFERENCES "public"."debts"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "transactions_debt_id_idx" ON "transactions" USING btree ("debt_id");