"use client";

import { getSupabase } from "@/lib/supabase/client";
import { radiusMeters, toRpcFilters } from "./params";
import type { DishResult, SearchFallback, SearchState } from "./types";

export const PAGE_SIZE = 20;

export async function searchDishes(
  state: SearchState,
  buyerCurrency: string,
  page: number,
  signal?: AbortSignal,
): Promise<DishResult[]> {
  if (state.lat == null || state.lng == null) return [];
  let req = getSupabase().rpc("search_dishes", {
    query: state.q,
    lat: state.lat,
    lng: state.lng,
    radius_meters: radiusMeters(state),
    filters: toRpcFilters(state, buyerCurrency),
    sort: state.sort,
    page,
    page_size: PAGE_SIZE,
  });
  if (signal) req = req.abortSignal(signal);
  const { data, error } = await req;
  if (error) throw new Error(error.message);
  return (data ?? []) as DishResult[];
}

export async function searchFallback(
  state: SearchState,
  buyerCurrency: string,
  signal?: AbortSignal,
): Promise<SearchFallback> {
  if (state.lat == null || state.lng == null) return { nearest_match_m: null, similar: [] };
  let req = getSupabase().rpc("dish_search_fallback", {
    query: state.q,
    lat: state.lat,
    lng: state.lng,
    radius_meters: radiusMeters(state),
    filters: toRpcFilters(state, buyerCurrency),
  });
  if (signal) req = req.abortSignal(signal);
  const { data, error } = await req;
  if (error) throw new Error(error.message);
  return data as SearchFallback;
}

export async function dishSuggestions(query: string, signal?: AbortSignal): Promise<string[]> {
  if (query.trim().length < 2) return [];
  let req = getSupabase().rpc("search_suggestions", { query, max_results: 8 });
  if (signal) req = req.abortSignal(signal);
  const { data, error } = await req;
  if (error) return [];
  return ((data ?? []) as { suggestion?: unknown }[])
    .map((r) => r.suggestion)
    .filter((s): s is string => typeof s === "string");
}
