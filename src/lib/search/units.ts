import type { DistanceUnit } from "./types";

export const METERS_PER_UNIT: Record<DistanceUnit, number> = { mi: 1609.344, km: 1000 };

/** Quick-pick radii shown as chips (in the active unit). */
export const RADIUS_PRESETS = [1, 3, 5, 10, 25, 50] as const;
export const RADIUS_MIN = 1;
export const RADIUS_MAX = 100;
export const DEFAULT_RADIUS = 5;

/** Countries that use miles for road distance. */
const MILES_REGIONS = new Set(["US", "GB", "LR", "MM"]);

/** Extract an ISO region from a BCP-47 tag ("en-GB" -> "GB", "zh-Hant-TW" -> "TW"). */
export function regionFromLocale(locale: string | undefined | null): string | null {
  if (!locale) return null;
  try {
    // Only an explicit region counts: a bare "en" says nothing about the country.
    return new Intl.Locale(locale.replace(/_/g, "-")).region ?? null;
  } catch {
    return null;
  }
}

/** Miles for US/UK (and LR/MM), km elsewhere. Uses the first locale that names a region. */
export function defaultUnitForLocales(locales: readonly string[]): DistanceUnit {
  for (const l of locales) {
    const region = regionFromLocale(l);
    if (region) return MILES_REGIONS.has(region) ? "mi" : "km";
  }
  return "km";
}

export function toMeters(value: number, unit: DistanceUnit): number {
  return Math.round(value * METERS_PER_UNIT[unit]);
}

export function fromMeters(meters: number, unit: DistanceUnit): number {
  return meters / METERS_PER_UNIT[unit];
}

/** Convert a radius when the user flips mi <-> km, snapping to a sensible value. */
export function convertRadius(value: number, from: DistanceUnit, to: DistanceUnit): number {
  if (from === to) return value;
  const converted = fromMeters(toMeters(value, from), to);
  return clampRadius(Math.round(converted));
}

export function clampRadius(value: number): number {
  if (!Number.isFinite(value)) return DEFAULT_RADIUS;
  return Math.min(RADIUS_MAX, Math.max(RADIUS_MIN, Math.round(value)));
}

/** "2.4 mi away" — distance is already privacy-rounded by the server. */
export function formatDistance(distance: number, unit: DistanceUnit): string {
  const rounded = Math.max(0.1, Math.round(distance * 10) / 10);
  return `${rounded.toFixed(1)} ${unit} away`;
}

/**
 * For the empty state: the smallest preset radius that is larger than the current one
 * AND reaches the nearest match. Returns null when nothing matches within RADIUS_MAX.
 */
export function suggestExpandedRadius(
  currentRadius: number,
  nearestMatchMeters: number | null,
  unit: DistanceUnit,
): number | null {
  if (nearestMatchMeters == null) return null;
  const needed = fromMeters(nearestMatchMeters, unit);
  const steps = [...RADIUS_PRESETS, RADIUS_MAX];
  for (const step of steps) {
    if (step > currentRadius && step >= needed) return step;
  }
  return null;
}
