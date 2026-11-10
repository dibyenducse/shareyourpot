import { regionFromLocale } from "./units";

const REGION_CURRENCY: Record<string, string> = {
  US: "USD", GB: "GBP", CA: "CAD", AU: "AUD", NZ: "NZD", IN: "INR", BD: "BDT", PK: "PKR",
  AE: "AED", MX: "MXN", NG: "NGN", JP: "JPY", CN: "CNY", SG: "SGD", ZA: "ZAR", BR: "BRL",
  // Euro area
  AT: "EUR", BE: "EUR", CY: "EUR", DE: "EUR", EE: "EUR", ES: "EUR", FI: "EUR", FR: "EUR",
  GR: "EUR", HR: "EUR", IE: "EUR", IT: "EUR", LT: "EUR", LU: "EUR", LV: "EUR", MT: "EUR",
  NL: "EUR", PT: "EUR", SI: "EUR", SK: "EUR",
};

/** Buyer currency for "approx. in your currency", from the browser locale (default USD). */
export function currencyForLocales(locales: readonly string[]): string {
  for (const l of locales) {
    const region = regionFromLocale(l);
    if (region && REGION_CURRENCY[region]) return REGION_CURRENCY[region];
  }
  return "USD";
}

export function formatMoney(cents: number, currency: string, locale?: string): string {
  try {
    const fmt = new Intl.NumberFormat(locale, { style: "currency", currency });
    const digits = fmt.resolvedOptions().maximumFractionDigits ?? 2;
    return new Intl.NumberFormat(locale, {
      style: "currency",
      currency,
      maximumFractionDigits: digits === 0 ? 0 : cents % 100 === 0 ? 0 : 2,
    }).format(cents / 100);
  } catch {
    return `${(cents / 100).toFixed(2)} ${currency}`;
  }
}

/** "৳450" or "৳450 (≈ $3.74)" when the buyer uses a different currency. */
export function formatPriceWithApprox(
  priceCents: number,
  currency: string,
  buyerPriceCents: number | null,
  buyerCurrency: string,
  locale?: string,
): { local: string; approx: string | null } {
  const local = formatMoney(priceCents, currency, locale);
  if (buyerPriceCents == null || currency.toUpperCase() === buyerCurrency.toUpperCase()) {
    return { local, approx: null };
  }
  return { local, approx: `≈ ${formatMoney(buyerPriceCents, buyerCurrency, locale)}` };
}
