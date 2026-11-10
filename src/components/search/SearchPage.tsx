"use client";

import dynamic from "next/dynamic";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useDebouncedValue } from "@/hooks/useDebouncedValue";
import { useDishSearch } from "@/hooks/useDishSearch";
import { useLocalePrefs } from "@/hooks/useLocalePrefs";
import { defaultSearchState, parseSearchParams, radiusMeters, searchUrl } from "@/lib/search/params";
import { loadRemembered, saveRemembered } from "@/lib/search/remember";
import { SORT_OPTIONS, type DistanceUnit, type SearchState, type SortOption } from "@/lib/search/types";
import { FiltersPanel } from "./FiltersPanel";
import { NoResults } from "./NoResults";
import { ResultsList } from "./ResultsList";
import { SaveSearchButton } from "./SaveSearchButton";
import { SearchBar } from "./SearchBar";

const ResultsMap = dynamic(() => import("./ResultsMap"), {
  ssr: false,
  loading: () => <div className="h-[70vh] min-h-[420px] animate-pulse rounded-3xl bg-stone-100" />,
});

const DEBOUNCE_MS = 300;

function SkeletonGrid() {
  return (
    <ul className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3" aria-hidden>
      {Array.from({ length: 6 }, (_, i) => (
        <li key={i} className="h-72 animate-pulse rounded-2xl bg-stone-100" />
      ))}
    </ul>
  );
}

export function SearchPage() {
  const router = useRouter();
  const params = useSearchParams();
  const { unit: localeUnit, currency, locale } = useLocalePrefs();

  // The URL is the source of truth for the search.
  const state = useMemo(
    () => parseSearchParams(new URLSearchParams(params.toString()), defaultSearchState(localeUnit)),
    [params, localeUnit],
  );
  const stateRef = useRef(state);
  stateRef.current = state;

  const replace = useCallback(
    (next: SearchState) => router.replace(searchUrl(next), { scroll: false }),
    [router],
  );
  const update = useCallback((patch: Partial<SearchState>) => replace({ ...stateRef.current, ...patch }), [replace]);

  // --- Restore the remembered location/radius when the URL has none; remember otherwise.
  useEffect(() => {
    if (state.lat == null || state.lng == null) {
      const rem = loadRemembered();
      if (rem) {
        replace({
          ...state,
          lat: rem.lat,
          lng: rem.lng,
          loc: rem.loc,
          r: params.has("r") ? state.r : rem.r,
          unit: params.has("unit") ? state.unit : rem.unit,
        });
      }
    } else {
      saveRemembered({ lat: state.lat, lng: state.lng, loc: state.loc, r: state.r, unit: state.unit });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.lat, state.lng, state.loc, state.r, state.unit]);

  // --- Debounced search-as-you-type: the input updates instantly, the URL/search lags.
  const [qDraft, setQDraft] = useState(state.q);
  const pushedQ = useRef(state.q);
  useEffect(() => {
    if (state.q !== pushedQ.current) {
      // changed from outside (back/forward, pasted link)
      pushedQ.current = state.q;
      setQDraft(state.q);
    }
  }, [state.q]);
  const debouncedQ = useDebouncedValue(qDraft, DEBOUNCE_MS);
  useEffect(() => {
    if (debouncedQ !== stateRef.current.q) {
      pushedQ.current = debouncedQ;
      update({ q: debouncedQ });
    }
  }, [debouncedQ, update]);

  // --- Radius slider drafts (dragging should not fire a search per pixel).
  const [radiusDraft, setRadiusDraft] = useState<{ r: number; unit: DistanceUnit }>({ r: state.r, unit: state.unit });
  useEffect(() => setRadiusDraft({ r: state.r, unit: state.unit }), [state.r, state.unit]);
  const debouncedRadius = useDebouncedValue(radiusDraft, 250);
  useEffect(() => {
    const s = stateRef.current;
    if (debouncedRadius.r !== s.r || debouncedRadius.unit !== s.unit) update(debouncedRadius);
  }, [debouncedRadius, update]);

  const search = useDishSearch(state, currency);
  const hasLocation = state.lat != null && state.lng != null;
  const activeFilterCount =
    state.cuisines.length + state.diet.length +
    [state.priceMin, state.priceMax, state.minRating, state.fulfillment].filter((v) => v != null).length +
    Number(state.availableNow) + Number(state.deliverToMe);
  const hasFilters = activeFilterCount > 0;
  const [filtersOpen, setFiltersOpen] = useState(false);
  const clearFilters = () =>
    update({ cuisines: [], diet: [], priceMin: null, priceMax: null, minRating: null, fulfillment: null, availableNow: false, deliverToMe: false });
  const liveCount = search.results.filter((r) => r.is_live).length;
  const typing = qDraft !== state.q;

  return (
    <div className="mx-auto max-w-7xl px-4 pb-16">
      <div className="z-[1050] -mx-4 bg-stone-50/95 px-4 py-3 backdrop-blur md:sticky md:top-0">
        <SearchBar
          q={qDraft}
          onQueryChange={setQDraft}
          location={hasLocation ? { lat: state.lat!, lng: state.lng!, loc: state.loc } : null}
          onLocationChange={(l) => update(l)}
          radius={radiusDraft.r}
          unit={radiusDraft.unit}
          onRadiusChange={(r, unit) => setRadiusDraft({ r, unit })}
          onSubmit={() => {
            pushedQ.current = qDraft;
            update({ q: qDraft });
          }}
        />
      </div>

      {!hasLocation ? (
        <section className="mt-10 rounded-3xl border border-dashed border-stone-300 bg-white p-8 text-center">
          <p className="text-lg font-semibold">Where should we look?</p>
          <p className="mt-1 text-stone-600">Use your current location or type an address, city, ZIP or postcode above.</p>
        </section>
      ) : (
        <div className="mt-4 grid gap-6 lg:grid-cols-[260px_1fr]">
          <aside className="lg:sticky lg:top-40 lg:self-start">
            {/* Mobile: collapsed behind a toggle so results stay above the fold. */}
            <button
              type="button"
              onClick={() => setFiltersOpen((o) => !o)}
              aria-expanded={filtersOpen}
              aria-controls="search-filters"
              className="w-full rounded-2xl border border-stone-200 bg-white px-4 py-2.5 text-left text-sm font-semibold lg:hidden"
            >
              {filtersOpen ? "Hide filters ▲" : `Filters${activeFilterCount ? ` (${activeFilterCount})` : ""} ▼`}
            </button>
            <div
              id="search-filters"
              className={`${filtersOpen ? "mt-2 block" : "hidden"} rounded-2xl border border-stone-200 bg-white p-4 lg:mt-0 lg:block`}
            >
              <FiltersPanel state={state} currency={currency} onChange={update} onReset={clearFilters} />
            </div>
          </aside>

          <main>
            <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
              <p className="text-sm text-stone-600" aria-live="polite" data-testid="result-summary">
                {search.loading || typing ? (
                  "Searching…"
                ) : (
                  <>
                    <span className="font-semibold text-stone-900">{search.total}</span>{" "}
                    {state.q.trim() ? <>“{state.q.trim()}” result{search.total === 1 ? "" : "s"}</> : <>dish{search.total === 1 ? "" : "es"}</>}{" "}
                    within {state.r} {state.unit}
                    {state.loc && <> of {state.loc}</>}
                    {liveCount > 0 && (
                      <span className="ml-2 inline-block whitespace-nowrap rounded-full bg-red-50 px-2 py-0.5 text-xs font-semibold text-red-700">
                        {liveCount} cooking now
                      </span>
                    )}
                  </>
                )}
              </p>
              <div className="flex items-center gap-2">
                <label className="flex items-center gap-1.5 text-sm text-stone-600">
                  Sort
                  <select
                    value={state.sort}
                    onChange={(e) => update({ sort: e.target.value as SortOption })}
                    className="rounded-lg border border-stone-200 bg-white px-2 py-1.5 text-sm text-stone-900"
                    data-testid="sort"
                  >
                    {SORT_OPTIONS.map((o) => (
                      <option key={o.value} value={o.value}>{o.label}</option>
                    ))}
                  </select>
                </label>
                <div role="group" aria-label="View" className="flex overflow-hidden rounded-lg border border-stone-200 text-sm">
                  {(["list", "map"] as const).map((v) => (
                    <button
                      key={v}
                      type="button"
                      aria-pressed={state.view === v}
                      onClick={() => update({ view: v })}
                      className={`px-3 py-1.5 capitalize ${state.view === v ? "bg-stone-800 text-white" : "bg-white text-stone-700 hover:bg-stone-50"}`}
                    >
                      {v === "list" ? "☰ List" : "🗺 Map"}
                    </button>
                  ))}
                </div>
              </div>
            </div>

            <div className="mb-4">
              <SaveSearchButton state={state} currency={currency} />
            </div>

            {search.error ? (
              <div className="rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-800" role="alert">
                Search failed: {search.error}{" "}
                <button type="button" onClick={search.retry} className="font-semibold underline">Try again</button>
              </div>
            ) : search.loading && search.results.length === 0 ? (
              <SkeletonGrid />
            ) : search.results.length === 0 ? (
              <NoResults
                query={state.q}
                radius={state.r}
                unit={state.unit}
                fallback={search.fallback}
                locale={locale}
                onExpand={(r) => update({ r })}
                hasFilters={hasFilters}
                onClearFilters={clearFilters}
              />
            ) : state.view === "map" ? (
              <ResultsMap
                center={{ lat: state.lat!, lng: state.lng! }}
                radiusMeters={radiusMeters(state)}
                results={search.results}
                locale={locale}
                hasMore={search.hasMore}
                loadingMore={search.loadingMore}
                onLoadMore={search.loadMore}
              />
            ) : (
              <div className={search.loading ? "opacity-60 transition-opacity" : ""}>
                <ResultsList
                  results={search.results}
                  locale={locale}
                  hasMore={search.hasMore}
                  loadingMore={search.loadingMore}
                  onLoadMore={search.loadMore}
                />
              </div>
            )}
          </main>
        </div>
      )}
    </div>
  );
}
