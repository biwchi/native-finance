const scale = 10_000n;

export function moneyUnits(amount: string): bigint {
  if (!/^-?(?:0|[1-9]\d{0,14})(?:\.\d{1,4})?$/.test(amount)) throw new Error("The amount could not be read reliably.");
  const negative = amount.startsWith("-");
  const [whole = "0", fraction = ""] = (negative ? amount.slice(1) : amount).split(".");
  const magnitude = BigInt(whole) * scale + BigInt(fraction.padEnd(4, "0"));
  if (magnitude === 0n) throw new Error("Enter a non-zero amount.");
  return magnitude;
}

export function dividePayment(total: string, count: number, currency: string): string {
  if (!Number.isInteger(count) || count < 1 || count > 10_000) throw new Error("The number of payments needs confirmation.");
  const numerator = moneyUnits(total);
  const precision = Math.min(4, new Intl.NumberFormat("en", { style: "currency", currency }).resolvedOptions().maximumFractionDigits ?? 2);
  const step = 10n ** BigInt(4 - precision);
  const denominator = BigInt(count) * step;
  const roundedUnits = ((numerator + denominator / 2n) / denominator) * step;
  if (roundedUnits === 0n) throw new Error("The calculated payment is too small. Enter the payment amount.");
  return formatMoneyUnits(roundedUnits);
}

export function formatMoneyUnits(units: bigint): string {
  const sign = units < 0n ? "-" : "";
  const magnitude = units < 0n ? -units : units;
  const fraction = (magnitude % scale).toString().padStart(4, "0").replace(/0+$/, "");
  return `${sign}${magnitude / scale}${fraction ? `.${fraction}` : ""}`;
}
