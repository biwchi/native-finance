CREATE TABLE "budget_category_assignments" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"plan_id" uuid NOT NULL,
	"group_id" uuid,
	"category_id" uuid NOT NULL,
	"limit" numeric(19, 4),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "budget_category_assignment_has_destination" CHECK ("budget_category_assignments"."group_id" is not null or "budget_category_assignments"."limit" is not null),
	CONSTRAINT "budget_category_assignment_limit_positive" CHECK ("budget_category_assignments"."limit" is null or "budget_category_assignments"."limit" > 0)
);
--> statement-breakpoint
CREATE TABLE "budget_groups" (
	"id" uuid PRIMARY KEY NOT NULL,
	"plan_id" uuid NOT NULL,
	"name" varchar(80) NOT NULL,
	"limit" numeric(19, 4) NOT NULL,
	"sort_order" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "budget_groups_limit_positive" CHECK ("budget_groups"."limit" > 0)
);
--> statement-breakpoint
CREATE TABLE "budget_plans" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"account_id" uuid,
	"month" date NOT NULL,
	"currency" varchar(3) NOT NULL,
	"monthly_limit" numeric(19, 4),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "budget_plans_monthly_limit_positive" CHECK ("budget_plans"."monthly_limit" is null or "budget_plans"."monthly_limit" > 0)
);
--> statement-breakpoint
ALTER TABLE "budget_category_assignments" ADD CONSTRAINT "budget_category_assignments_plan_id_budget_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "public"."budget_plans"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "budget_category_assignments" ADD CONSTRAINT "budget_category_assignments_group_id_budget_groups_id_fk" FOREIGN KEY ("group_id") REFERENCES "public"."budget_groups"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "budget_category_assignments" ADD CONSTRAINT "budget_category_assignments_category_id_categories_id_fk" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "budget_groups" ADD CONSTRAINT "budget_groups_plan_id_budget_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "public"."budget_plans"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "budget_plans" ADD CONSTRAINT "budget_plans_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "budget_category_assignments_plan_category_unique" ON "budget_category_assignments" USING btree ("plan_id","category_id");--> statement-breakpoint
CREATE INDEX "budget_category_assignments_group_id_idx" ON "budget_category_assignments" USING btree ("group_id");--> statement-breakpoint
CREATE INDEX "budget_category_assignments_category_id_idx" ON "budget_category_assignments" USING btree ("category_id");--> statement-breakpoint
CREATE INDEX "budget_groups_plan_id_idx" ON "budget_groups" USING btree ("plan_id");--> statement-breakpoint
CREATE UNIQUE INDEX "budget_groups_plan_name_unique" ON "budget_groups" USING btree ("plan_id",lower("name"));--> statement-breakpoint
CREATE UNIQUE INDEX "budget_plans_account_month_unique" ON "budget_plans" USING btree ("account_id","month") WHERE "budget_plans"."account_id" is not null;--> statement-breakpoint
CREATE UNIQUE INDEX "budget_plans_all_accounts_month_unique" ON "budget_plans" USING btree ("month") WHERE "budget_plans"."account_id" is null;