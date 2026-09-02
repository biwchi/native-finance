CREATE TABLE "exchange_rates" (
	"base_currency" varchar(3) NOT NULL,
	"quote_currency" varchar(3) NOT NULL,
	"rate" numeric(30, 15) NOT NULL,
	"effective_date" date NOT NULL,
	"provider" varchar(40) DEFAULT 'frankfurter' NOT NULL,
	"fetched_at" timestamp with time zone NOT NULL,
	CONSTRAINT "exchange_rates_base_quote_date_provider_pk" PRIMARY KEY("base_currency","quote_currency","effective_date","provider"),
	CONSTRAINT "exchange_rates_rate_positive" CHECK ("exchange_rates"."rate" > 0)
);
--> statement-breakpoint
CREATE INDEX "exchange_rates_latest_idx" ON "exchange_rates" USING btree ("base_currency","quote_currency","effective_date");