ALTER TABLE "accounts" ADD COLUMN "icon" varchar(80) DEFAULT 'creditcard.fill' NOT NULL;--> statement-breakpoint
ALTER TABLE "accounts" ADD COLUMN "icon_color" varchar(20) DEFAULT 'blue' NOT NULL;