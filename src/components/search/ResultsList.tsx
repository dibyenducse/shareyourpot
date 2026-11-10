"use client";

import { useEffect, useRef } from "react";
import type { DishResult } from "@/lib/search/types";
import { DishCard } from "./DishCard";

/** Result grid with infinite scroll (IntersectionObserver on a sentinel). */
export function ResultsList({
  results, locale, hasMore, loadingMore, onLoadMore,
}: {
  results: DishResult[];
  locale: string;
  hasMore: boolean;
  loadingMore: boolean;
  onLoadMore: () => void;
}) {
  const sentinel = useRef<HTMLDivElement>(null);
  const loadMoreRef = useRef(onLoadMore);
  loadMoreRef.current = onLoadMore;

  useEffect(() => {
    const el = sentinel.current;
    if (!el || !hasMore) return;
    const io = new IntersectionObserver((entries) => entries[0]?.isIntersecting && loadMoreRef.current(), {
      rootMargin: "600px 0px",
    });
    io.observe(el);
    return () => io.disconnect();
  }, [hasMore, results.length]);

  return (
    <div>
      <ul className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3" data-testid="results">
        {results.map((d) => (
          <li key={`${d.result_type}:${d.id}`}>
            <DishCard dish={d} locale={locale} />
          </li>
        ))}
      </ul>
      <div ref={sentinel} aria-hidden className="h-px" />
      {hasMore && (
        <div className="py-6 text-center">
          <button
            type="button"
            onClick={onLoadMore}
            disabled={loadingMore}
            className="rounded-full border border-stone-300 px-4 py-2 text-sm text-stone-700 hover:bg-stone-50 disabled:opacity-60"
          >
            {loadingMore ? "Loading…" : "Load more"}
          </button>
        </div>
      )}
    </div>
  );
}
