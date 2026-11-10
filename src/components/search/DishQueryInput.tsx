"use client";

import { useEffect, useState } from "react";
import { dishSuggestions } from "@/lib/search/api";
import { useDebouncedValue } from "@/hooks/useDebouncedValue";
import { Autocomplete } from "./Autocomplete";

/** "What": dish name or keyword, with dish-name suggestions (typo-tolerant server side). */
export function DishQueryInput({
  value, onChange, onSubmit,
}: { value: string; onChange: (v: string) => void; onSubmit?: () => void }) {
  const debounced = useDebouncedValue(value, 200);
  const [suggestions, setSuggestions] = useState<string[]>([]);

  useEffect(() => {
    if (debounced.trim().length < 2) {
      setSuggestions([]);
      return;
    }
    const ctrl = new AbortController();
    dishSuggestions(debounced, ctrl.signal).then((s) => {
      if (!ctrl.signal.aborted) setSuggestions(s.filter((x) => x.toLowerCase() !== debounced.trim().toLowerCase()));
    });
    return () => ctrl.abort();
  }, [debounced]);

  return (
    <Autocomplete
      label="What"
      value={value}
      onInputChange={onChange}
      suggestions={suggestions}
      getKey={(s) => s}
      renderItem={(s) => <span>{s}</span>}
      onPick={(s) => onChange(s)}
      onEnter={onSubmit}
      placeholder='Dish or keyword, e.g. "biryani"'
      icon="🔎"
      inputTestId="dish-query"
      trailing={
        value ? (
          <button type="button" aria-label="Clear dish" className="px-1 text-stone-400 hover:text-stone-700" onClick={() => onChange("")}>
            ✕
          </button>
        ) : null
      }
    />
  );
}
