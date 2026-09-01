DROP INDEX "categories_kind_name_unique";--> statement-breakpoint
ALTER TABLE "categories" ADD COLUMN "parent_id" uuid;--> statement-breakpoint
ALTER TABLE "categories" ADD CONSTRAINT "categories_parent_id_categories_id_fk" FOREIGN KEY ("parent_id") REFERENCES "public"."categories"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "categories_root_kind_name_unique" ON "categories" USING btree ("kind",lower("name")) WHERE "categories"."parent_id" is null;--> statement-breakpoint
CREATE UNIQUE INDEX "categories_parent_name_unique" ON "categories" USING btree ("parent_id",lower("name")) WHERE "categories"."parent_id" is not null;--> statement-breakpoint
CREATE INDEX "categories_parent_id_idx" ON "categories" USING btree ("parent_id");