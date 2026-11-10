"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { PAGE_SIZE, searchDishes, searchFallback } from "@/lib/search/api";
import { searchKey } from "@/lib/search/params";
import type { DishResult, SearchFallback, SearchState } from "@/lib/search/types";

interface Result {
  results: DishResult[];
  total: number;
  loading: boolean;
  loadingMore: boolean;
  hasMore: boolean;
  error: string | null;
  fallback: SearchFallback | null;
  loadMore: () => void;
  retry: () => void;
}

/**
 * Infinite-scrolling dish search. A new search (any change to `state` other than view /
 * location label) aborts in-flight requests and restarts at page 1; responses from
 * superseded searches are ignored.
 */
export function useDishSearch(state: SearchState, buyerCurrency: string): Result {
  const key = `${searchKey(state)}|${buyerCurrency}`;
  const [results, setResults] = useState<DishResult[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  // Key of the search whose first page (+ fallback when empty) has fully arrived. Deriving
  // `loading` from it avoids flashing an empty state before the first fetch starts.
  const [settledKey, setSettledKey] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fallback, setFallback] = useState<SearchFallback | null>(null);
  const [attempt, setAttempt] = useState(0);

  const stateRef = useRef(state);
  stateRef.current = state;
  const activeKey = useRef(key);
  const abortRef = useRef<AbortController | null>(null);

  const hasLocation = state.lat != null && state.lng != null;

  // First page (and fallback when empty) for every new search.
  useEffect(() => {
    activeKey.current = key;
    abortRef.current?.abort();
    setLoadingMore(false); // an in-flight "load more" for the previous search is now moot
    if (!hasLocation) {
      setResults([]);
      setTotal(0);
      setFallback(null);
      setSettledKey(key);
      return;
    }
    const ctrl = new AbortController();
    abortRef.current = ctrl;
    setError(null);
    setSettledKey(null); // also covers retry(), where the key itself does not change
    setPage(1);
    const s = stateRef.current;
    (async () => {
      try {
        const rows = await searchDishes(s, buyerCurrency, 1, ctrl.signal);
        if (activeKey.current !== key) return;
        setResults(rows);
        setTotal(rows[0]?.total_count ?? 0);
        if (rows.length === 0) {
          const fb = await searchFallback(s, buyerCurrency, ctrl.signal).catch(() => null);
          if (activeKey.current !== key) return;
          setFallback(fb);
        } else {
          setFallback(null);
        }
        setSettledKey(key);
      } catch (e) {
        if (ctrl.signal.aborted || activeKey.current !== key) return;
        setError(e instanceof Error ? e.message : "Search failed");
        setSettledKey(key);
      }
    })();
    return () => ctrl.abort();
  }, [key, hasLocation, buyerCurrency, attempt]);

  const loading = settledKey !== key;
  const hasMore = !loading && results.length < total;

  const loadMore = useCallback(() => {
    if (loading || loadingMore || !hasMore) return;
    const next = page + 1;
    const myKey = activeKey.current;
    const ctrl = new AbortController();
    setLoadingMore(true);
    searchDishes(stateRef.current, buyerCurrency, next, ctrl.signal)
      .then((rows) => {
        if (activeKey.current !== myKey) return;
        setResults((prev) => {
          const seen = new Set(prev.map((r) => r.id));
          return [...prev, ...rows.filter((r) => !seen.has(r.id))];
        });
        if (rows[0]) setTotal(rows[0].total_count);
        if (rows.length < PAGE_SIZE) setTotal((t) => Math.min(t, (next - 1) * PAGE_SIZE + rows.length));
        setPage(next);
      })
      .catch((e) => {
        if (activeKey.current === myKey) setError(e instanceof Error ? e.message : "Search failed");
      })
      .finally(() => {
        if (activeKey.current === myKey) setLoadingMore(false);
      });
  }, [loading, loadingMore, hasMore, page, buyerCurrency]);

  const retry = useCallback(() => setAttempt((a) => a + 1), []);

  return { results, total, loading, loadingMore, hasMore, error, fallback, loadMore, retry };
}
