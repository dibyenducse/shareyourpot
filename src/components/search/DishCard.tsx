"use client";

import { formatPriceWithApprox } from "@/lib/search/currency";
import { formatDistance } from "@/lib/search/units";
import { DIET_FLAGS, type DishResult } from "@/lib/search/types";
import { DishPhoto } from "./DishPhoto";
import { LiveBadge } from "./LiveBadge";

const DIET_LABEL: Record<string, string> = Object.fromEntries(DIET_FLAGS.map((d) => [d.value, d.label]));

export function DishCard({
  dish, locale, compact = false, onSelect, selected = false,
}: {
  dish: DishResult;
  locale: string;
  compact?: boolean;
  onSelect?: (dish: DishResult) => void;
  selected?: boolean;
}) {
  const price = formatPriceWithApprox(dish.price_cents, dish.currency, dish.buyer_price_cents, dish.buyer_currency, locale);
  const diets = dish.diet_flags.filter((f) => DIET_LABEL[f] && !(f === "vegetarian" && dish.diet_flags.includes("vegan")));

  return (
    <article
      className={`group flex overflow-hidden rounded-2xl border bg-white shadow-sm transition hover:shadow-md ${
        selected ? "border-orange-500 ring-2 ring-orange-200" : "border-stone-200"
      } ${compact ? "flex-row" : "flex-col"}`}
      onMouseEnter={onSelect ? () => onSelect(dish) : undefined}
      data-testid="dish-card"
      data-live={dish.is_live || undefined}
    >
      <div className={`relative shrink-0 ${compact ? "w-28" : "aspect-[4/3] w-full"}`}>
        <DishPhoto url={dish.photo_url} title={dish.title} category={dish.category} cuisine={dish.cuisine} className="h-full w-full" />
        {dish.is_live && !compact && (
          <div className="absolute left-2 top-2 rounded-full bg-white/95 px-1.5 py-1 shadow">
            <LiveBadge readyAt={dish.ready_at} availableUntil={dish.available_until} />
          </div>
        )}
      </div>

      <div className="flex min-w-0 flex-1 flex-col gap-1 p-3">
        {dish.is_live && compact && <LiveBadge readyAt={dish.ready_at} availableUntil={dish.available_until} />}
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            <h3 className="truncate font-semibold text-stone-900" title={dish.title}>{dish.title}</h3>
            {dish.title_local && dish.title_local !== dish.title && (
              <p className="truncate text-sm text-stone-500" lang="und">{dish.title_local}</p>
            )}
          </div>
          <div className="shrink-0 text-right">
            <div className="font-semibold text-stone-900">{price.local}</div>
            {price.approx && <div className="text-xs text-stone-500">{price.approx}</div>}
          </div>
        </div>

        <p className="truncate text-sm text-stone-600">
          by <span className="font-medium text-stone-800">{dish.cook_name}</span>
          {dish.cook_rating_count > 0 && (
            <span className="ml-1.5 whitespace-nowrap" aria-label={`Rated ${dish.cook_rating} out of 5 from ${dish.cook_rating_count} reviews`}>
              <span className="text-amber-500" aria-hidden>★</span> {Number(dish.cook_rating).toFixed(1)}
              <span className="text-stone-400"> ({dish.cook_rating_count})</span>
            </span>
          )}
        </p>

        <div className="mt-auto flex flex-wrap items-center gap-1.5 pt-1 text-xs">
          <span className="font-medium text-stone-700" data-testid="distance">
            📍 {formatDistance(dish.distance, dish.distance_unit)}
          </span>
          {dish.can_deliver ? (
            <span className="rounded-full bg-emerald-50 px-2 py-0.5 font-medium text-emerald-700">Delivers to you</span>
          ) : (
            <span className="rounded-full bg-stone-100 px-2 py-0.5 font-medium text-stone-600">Pickup only</span>
          )}
          {!dish.is_live && dish.prep_time_minutes != null && !compact && (
            <span className="text-stone-500">~{dish.prep_time_minutes} min prep</span>
          )}
          {diets.slice(0, compact ? 1 : 3).map((d) => (
            <span key={d} className="rounded-full bg-lime-50 px-2 py-0.5 text-lime-800">{DIET_LABEL[d]}</span>
          ))}
        </div>
      </div>
    </article>
  );
}
