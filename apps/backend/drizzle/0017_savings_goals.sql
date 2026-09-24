CREATE TABLE "goals" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"account_id" uuid NOT NULL,
	"name" varchar(120) NOT NULL,
	"target_amount" numeric(19, 4) NOT NULL,
	"icon" varchar(80) NOT NULL,
	"color" varchar(20) NOT NULL,
	"deadline" date,
	"sort_order" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "goals_positive_target" CHECK ("goals"."target_amount" > 0),
	CONSTRAINT "goals_nonnegative_order" CHECK ("goals"."sort_order" >= 0)
);
--> statement-breakpoint
ALTER TABLE "goals" ADD CONSTRAINT "goals_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "goals_account_id_idx" ON "goals" USING btree ("account_id");
--> statement-breakpoint
CREATE FUNCTION finance_sync_goal_after() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM finance_sync_capture('goal', OLD.id::text, NULL);
  ELSE
    -- Money stays a decimal string on the wire, including bootstrap and cascades.
    PERFORM finance_sync_capture('goal', NEW.id::text,
      finance_sync_camel(to_jsonb(NEW)) || jsonb_build_object('targetAmount', NEW.target_amount::text));
  END IF;
  RETURN NULL;
END $$;
--> statement-breakpoint
CREATE TRIGGER finance_sync_lock BEFORE INSERT OR UPDATE OR DELETE ON goals
FOR EACH STATEMENT EXECUTE FUNCTION finance_sync_before();
--> statement-breakpoint
CREATE TRIGGER finance_sync_capture AFTER INSERT OR UPDATE OR DELETE ON goals
FOR EACH ROW EXECUTE FUNCTION finance_sync_goal_after();
