export type StoredExchangeRate = {
  baseCurrency: string;
  quoteCurrency: string;
  rate: string;
  effectiveDate: string;
  provider: string;
  fetchedAt: Date;
};

export type ProviderExchangeRate = Pick<
  StoredExchangeRate,
  "quoteCurrency" | "rate" | "effectiveDate"
>;

export type ExchangeRateResponse = {
  baseCurrency: string;
  reportingCurrency: string;
  quotes: Array<{
    currency: string;
    rate: string;
    effectiveDate: string;
  }>;
  fetchedAt: Date;
  stale: boolean;
};

export function normalizeCurrency(currency: string): string {
  return currency.trim().toUpperCase();
}

export function uniqueCurrencies(currencies: string[]): string[] {
  return [...new Set(currencies.map(normalizeCurrency))].sort();
}

export function latestRatesByCurrency(
  rates: StoredExchangeRate[],
): Map<string, StoredExchangeRate> {
  const latest = new Map<string, StoredExchangeRate>();
  for (const rate of rates) {
    const existing = latest.get(rate.quoteCurrency);
    if (
      !existing ||
      rate.effectiveDate > existing.effectiveDate ||
      rate.effectiveDate === existing.effectiveDate && rate.fetchedAt > existing.fetchedAt
    ) {
      latest.set(rate.quoteCurrency, rate);
    }
  }
  return latest;
}

export function createUsdRate(date: Date) {
  return {
    currency: "USD" as const,
    rate: "1",
    effectiveDate: date.toISOString().slice(0, 10),
  };
}

export function convertExchangeAmount(
  amount: string,
  sourceCurrency: string,
  targetCurrency: string,
  snapshot: ExchangeRateResponse,
): { amount: string; rate: string; effectiveDate: string } | null {
  const source = snapshot.quotes.find(
    (quote) => quote.currency === normalizeCurrency(sourceCurrency),
  );
  const target = snapshot.quotes.find(
    (quote) => quote.currency === normalizeCurrency(targetCurrency),
  );
  const parsedAmount = parseDecimal(amount);
  const sourceRate = source && parseDecimal(source.rate);
  const targetRate = target && parseDecimal(target.rate);
  if (!source || !target || !parsedAmount || !sourceRate || !targetRate) return null;
  if (sourceRate.numerator <= 0n || targetRate.numerator <= 0n) return null;

  const resultNumerator = parsedAmount.numerator * targetRate.numerator * sourceRate.denominator;
  const resultDenominator = parsedAmount.denominator * targetRate.denominator * sourceRate.numerator;
  const rateNumerator = targetRate.numerator * sourceRate.denominator;
  const rateDenominator = targetRate.denominator * sourceRate.numerator;

  return {
    amount: formatRatio(resultNumerator, resultDenominator, 4),
    rate: formatRatio(rateNumerator, rateDenominator, 8),
    effectiveDate: source.effectiveDate < target.effectiveDate
      ? source.effectiveDate
      : target.effectiveDate,
  };
}

function parseDecimal(value: string): { numerator: bigint; denominator: bigint } | null {
  const normalized = value.trim().replaceAll(",", "");
  if (!/^-?\d+(?:\.\d+)?$/.test(normalized)) return null;
  const negative = normalized.startsWith("-");
  const [whole = "0", fraction = ""] = (negative ? normalized.slice(1) : normalized).split(".");
  const denominator = 10n ** BigInt(fraction.length);
  return {
    numerator: BigInt(`${whole}${fraction}`) * (negative ? -1n : 1n),
    denominator,
  };
}

function formatRatio(numerator: bigint, denominator: bigint, precision: number): string {
  const sign = numerator < 0n ? -1n : 1n;
  const scale = 10n ** BigInt(precision);
  const scaled = numerator * sign * scale;
  let rounded = scaled / denominator;
  if ((scaled % denominator) * 2n >= denominator) rounded += 1n;
  rounded *= sign;
  const magnitude = rounded < 0n ? -rounded : rounded;
  const whole = rounded / scale;
  const fraction = (magnitude % scale).toString().padStart(precision, "0").replace(/0+$/, "");
  return fraction ? `${whole}.${fraction}` : whole.toString();
}
