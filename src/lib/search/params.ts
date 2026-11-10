import { clampRadius, DEFAULT_RADIUS, toMeters } from "./units";
import {
  DIET_FLAGS,
  SORT_OPTIONS,
  type DietFlag,
  type DistanceUnit,
  type Fulfillment,
  type SearchState,
  type SortOption,
} from "./types";

/**
 * The whole search lives in the URL so it can be shared and bookmarked:
 *   /search?q=biryani&lat=40.75&lng=-73.98&loc=Midtown&r=10&unit=mi&sort=rating
 *          &view=map&cuisine=indian,bangladeshi&diet=halal&pmin=5&pmax=20&rating=4.5
 *          &fulfil=delivery&now=1&deliver=1
 */

const SORTS = new Set<string>(SORT_OPTIONS.map((s) => s.value));
const DIETS = new Set<string>(DIET_FLAGS.map((d) => d.value));

export function defaultSearchState(unit: DistanceUnit = "mi"): SearchState {
  return {
    q: "",
    lat: null,
    lng: null,
    loc: "",
    r: DEFAULT_RADIUS,
    unit,
    sort: "nearest",
    view: "list",
    cuisines: [],
    diet: [],
    priceMin: null,
    priceMax: null,
    minRating: null,
    fulfillment: null,
    availableNow: false,
    deliverToMe: false,
  };
}

function num(v: string | null, min: number, max: number): number | null {
  if (v == null || v.trim() === "") return null;
  const n = Number(v);
  return Number.isFinite(n) && n >= min && n <= max ? n : null;
}

function list(v: string | null): string[] {
  if (!v) return [];
  return [...new Set(v.split(",").map((s) => s.trim()).filter(Boolean))];
}

/** Parse URL params. Invalid values fall back to defaults instead of erroring. */
export function parseSearchParams(
  params: URLSearchParams,
  defaults: SearchState = defaultSearchState(),
): SearchState {
  const lat = num(params.get("lat"), -90, 90);
  const lng = num(params.get("lng"), -180, 180);
  const hasPoint = lat != null && lng != null;
  const unitParam = params.get("unit");
  const unit: DistanceUnit = unitParam === "km" || unitParam === "mi" ? unitParam : defaults.unit;
  const r = num(params.get("r"), 0.1, 1000);
  const sort = params.get("sort");
  const fulfil = params.get("fulfil");

  return {
    q: (params.get("q") ?? defaults.q).slice(0, 100),
    lat: hasPoint ? lat : defaults.lat,
    lng: hasPoint ? lng : defaults.lng,
    loc: hasPoint ? (params.get("loc") ?? "") : defaults.loc,
    r: r != null ? clampRadius(r) : defaults.r,
    unit,
    sort: sort && SORTS.has(sort) ? (sort as SortOption) : defaults.sort,
    view: params.get("view") === "map" ? "map" : "list",
    cuisines: list(params.get("cuisine")).map((c) => c.toLowerCase()),
    diet: list(params.get("diet")).filter((d): d is DietFlag => DIETS.has(d)),
    priceMin: num(params.get("pmin"), 0, 1e7),
    priceMax: num(params.get("pmax"), 0, 1e7),
    minRating: num(params.get("rating"), 0, 5),
    fulfillment: fulfil === "pickup" || fulfil === "delivery" ? (fulfil as Fulfillment) : null,
    availableNow: params.get("now") === "1",
    deliverToMe: params.get("deliver") === "1",
  };
}

/** Serialise to URL params, omitting defaults to keep shared links short. */
export function toSearchParams(state: SearchState): URLSearchParams {
  const p = new URLSearchParams();
  if (state.q.trim()) p.set("q", state.q.trim());
  if (state.lat != null && state.lng != null) {
    p.set("lat", state.lat.toFixed(5));
    p.set("lng", state.lng.toFixed(5));
    if (state.loc) p.set("loc", state.loc);
  }
  p.set("r", String(state.r));
  p.set("unit", state.unit);
  if (state.sort !== "nearest") p.set("sort", state.sort);
  if (state.view !== "list") p.set("view", state.view);
  if (state.cuisines.length) p.set("cuisine", state.cuisines.join(","));
  if (state.diet.length) p.set("diet", state.diet.join(","));
  if (state.priceMin != null) p.set("pmin", String(state.priceMin));
  if (state.priceMax != null) p.set("pmax", String(state.priceMax));
  if (state.minRating != null) p.set("rating", String(state.minRating));
  if (state.fulfillment) p.set("fulfil", state.fulfillment);
  if (state.availableNow) p.set("now", "1");
  if (state.deliverToMe) p.set("deliver", "1");
  return p;
}

export function searchUrl(state: SearchState): string {
  return `/search?${toSearchParams(state).toString()}`;
}

/** The `filters` jsonb accepted by the search_dishes RPC. */
export function toRpcFilters(state: SearchState, buyerCurrency: string): Record<string, unknown> {
  const f: Record<string, unknown> = { currency: buyerCurrency, unit: state.unit };
  if (state.cuisines.length) f.cuisines = state.cuisines;
  if (state.diet.length) f.diet = state.diet;
  if (state.priceMin != null) f.price_min = state.priceMin;
  if (state.priceMax != null) f.price_max = state.priceMax;
  if (state.minRating != null) f.min_rating = state.minRating;
  if (state.fulfillment) f.fulfillment = state.fulfillment;
  if (state.availableNow) f.available_now = true;
  if (state.deliverToMe) f.deliver_to_me = true;
  return f;
}

export function radiusMeters(state: Pick<SearchState, "r" | "unit">): number {
  return toMeters(state.r, state.unit);
}

/** Stable key: identical searches share a cache entry / do not refetch. */
export function searchKey(state: SearchState): string {
  const { view: _view, loc: _loc, ...rest } = state;
  return JSON.stringify(rest);
}
