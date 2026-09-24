# Scan pricing regression

`product-financing.png` is the supplied product screenshot that exposed an ambiguous scan result. The main price is **27,756 KZT**, the conditional bonus price is **26,924 KZT**, and the financing offer is **2,313 KZT × 12**.

The default scan must produce one expense for 27,756 KZT with no recurrence. An explicit installment request may produce a monthly expense for 2,313 KZT over 12 occurrences. A source currency must never select a different account or be relabeled as that account's currency.

The deterministic backend test supplies a RUB account through local context while the server still has KZT. With fixture rates of 500 KZT and 80 RUB per USD, 27,756 KZT becomes 4,440.96 RUB and retains the original amount in conversion metadata. Those rates are test values, not current market rates.

An optional live evaluation covers the default scan, an explicit one-time purchase and explicit installments. It uploads this screenshot to the configured AI API and uses its existing credentials. Run it from `apps/backend` after obtaining approval for the image upload:

```sh
bun run eval:scan
```

The evaluation supplies synthetic accounts and categories and does not create or save transactions.
