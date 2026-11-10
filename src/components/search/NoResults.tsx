"use client";

import { suggestExpandedRadius } from "@/lib/search/units";
import type { DistanceUnit, SearchFallback } from "@/lib/search/types";
import { DishCard } from "./DishCard";

/** "No biryani within 5 mi. Expand to 10 mi?" + similar dishes nearby. */
export function NoResults({
  query, radius, unit, fallback, locale, onExpand, hasFilters, onClearFilters,
}: {
  query: string;
  radius: number;
  unit: DistanceUnit;
  fallback: SearchFallback | null;
  locale: string;
  onExpand: (radius: number) => void;
  hasFilters: boolean;
  onClearFilters: () => void;
}) {
  const what = query.trim() || "dishes";
  const expandTo = suggestExpandedRadius(radius, fallback?.nearest_match_m ?? null, unit);

  return (
    <section className="rounded-3xl border border-dashed border-stone-300 bg-white p-6 text-center" data-testid="no-results">
      <p className="text-lg font-semibold text-stone-900">
        No {what} within {radius} {unit}.
      </p>
      {expandTo != null ? (
        <button
          type="button"
          onClick={() => onExpand(expandTo)}
          className="mt-3 rounded-full bg-orange-500 px-5 py-2 font-semibold text-white shadow hover:bg-orange-600"
          data-testid="expand-radius"
        >
          Expand to {expandTo} {unit}?
        </button>
      ) : (
        fallback && (
          <p className="mt-2 text-sm text-stone-600">
            Nobody is cooking {what} within 100 {unit} right now. Save this search below and we&apos;ll tell you when someone does.
          </p>
        )
      )}
      {hasFilters && (
        <p className="mt-3 text-sm text-stone-600">
          Filters are on.{" "}
          <button type="button" onClick={onClearFilters} className="font-medium text-orange-700 underline">
            Clear filters
          </button>
        </p>
      )}

      {fallback && fallback.similar.length > 0 && (
        <div className="mt-6 text-left">
          <h3 className="mb-3 font-semibold text-stone-800">Similar dishes nearby</h3>
          <ul className="grid gap-3 md:grid-cols-2">
            {fallback.similar.map((d) => (
              <li key={`${d.result_type}:${d.id}`}>
                <DishCard dish={d} locale={locale} compact />
              </li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}
