import type { DistanceUnit } from "./types";

/** Last location + radius, remembered per browser so the next search starts there. */
export interface RememberedSearch {
  lat: number;
  lng: number;
  loc: string;
  r: number;
  unit: DistanceUnit;
}

const KEY = "syp:last-search-location";

export function loadRemembered(): RememberedSearch | null {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const v = JSON.parse(raw) as RememberedSearch;
    if (
      typeof v.lat === "number" && Math.abs(v.lat) <= 90 &&
      typeof v.lng === "number" && Math.abs(v.lng) <= 180 &&
      typeof v.r === "number" && (v.unit === "mi" || v.unit === "km")
    ) {
      return { ...v, loc: typeof v.loc === "string" ? v.loc : "" };
    }
  } catch {
    /* ignore corrupt / unavailable storage */
  }
  return null;
}

export function saveRemembered(v: RememberedSearch): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(v));
  } catch {
    /* storage may be disabled */
  }
}
