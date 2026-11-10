"use client";

import { useSyncExternalStore } from "react";
import { currencyForLocales } from "@/lib/search/currency";
import { defaultUnitForLocales } from "@/lib/search/units";
import type { DistanceUnit } from "@/lib/search/types";

function locales(): readonly string[] {
  return navigator.languages?.length ? navigator.languages : [navigator.language];
}

const noop = () => () => {};

/** Locale-derived defaults; server render assumes en-US until hydration. */
export function useLocalePrefs(): { unit: DistanceUnit; currency: string; locale: string } {
  const unit = useSyncExternalStore(noop, () => defaultUnitForLocales(locales()), () => "mi" as const);
  const currency = useSyncExternalStore(noop, () => currencyForLocales(locales()), () => "USD");
  const locale = useSyncExternalStore(noop, () => locales()[0] ?? "en-US", () => "en-US");
  return { unit, currency, locale };
}
