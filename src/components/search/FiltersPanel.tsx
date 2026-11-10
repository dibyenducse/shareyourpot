"use client";

import { useEffect, useState } from "react";
import { DIET_FLAGS, type DietFlag, type Fulfillment, type SearchState } from "@/lib/search/types";

const CUISINES = [
  "Indian", "Bangladeshi", "Pakistani", "Bengali", "Mexican", "Italian", "Chinese", "Thai", "Korean",
  "Japanese", "Vietnamese", "Lebanese", "Persian", "Turkish", "Greek", "Nigerian", "Ethiopian",
  "Caribbean", "Filipino", "British", "Polish",
];

const RATINGS = [null, 3.5, 4, 4.5] as const;

type FilterPatch = Partial<
  Pick<SearchState, "cuisines" | "diet" | "priceMin" | "priceMax" | "minRating" | "fulfillment" | "availableNow" | "deliverToMe">
>;

function Chip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      aria-pressed={active}
      onClick={onClick}
      className={`rounded-full border px-2.5 py-1 text-sm transition ${
        active ? "border-stone-800 bg-stone-800 text-white" : "border-stone-200 bg-white text-stone-700 hover:border-stone-400"
      }`}
    >
      {children}
    </button>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <fieldset className="border-t border-stone-100 pt-3 first:border-0 first:pt-0">
      <legend className="mb-2 text-xs font-semibold uppercase tracking-wide text-stone-500">{title}</legend>
      {children}
    </fieldset>
  );
}

function PriceInput({ label, value, onCommit }: { label: string; value: number | null; onCommit: (v: number | null) => void }) {
  const [draft, setDraft] = useState(value?.toString() ?? "");
  useEffect(() => setDraft(value?.toString() ?? ""), [value]);
  const commit = () => {
    const n = draft.trim() === "" ? null : Number(draft);
    onCommit(n != null && Number.isFinite(n) && n >= 0 ? n : null);
  };
  return (
    <label className="flex-1">
      <span className="sr-only">{label}</span>
      <input
        inputMode="decimal"
        placeholder={label}
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => e.key === "Enter" && commit()}
        className="w-full rounded-lg border border-stone-200 px-2 py-1.5 text-sm"
      />
    </label>
  );
}

export function FiltersPanel({
  state, currency, onChange, onReset,
}: { state: SearchState; currency: string; onChange: (patch: FilterPatch) => void; onReset: () => void }) {
  const cuisineOptions = [...new Set([...CUISINES.map((c) => c.toLowerCase()), ...state.cuisines])];
  const toggle = <T,>(list: T[], v: T) => (list.includes(v) ? list.filter((x) => x !== v) : [...list, v]);
  const active =
    state.cuisines.length + state.diet.length +
    [state.priceMin, state.priceMax, state.minRating, state.fulfillment].filter((v) => v != null).length +
    Number(state.availableNow) + Number(state.deliverToMe);

  return (
    <div className="space-y-3 text-sm" data-testid="filters">
      <div className="flex items-center justify-between">
        <h2 className="font-semibold text-stone-900">Filters{active > 0 && <span className="ml-1 text-orange-600">({active})</span>}</h2>
        {active > 0 && (
          <button type="button" onClick={onReset} className="text-xs text-stone-500 underline hover:text-stone-800">
            Clear all
          </button>
        )}
      </div>

      <Section title="Availability">
        <div className="space-y-1.5">
          <label className="flex items-center gap-2">
            <input type="checkbox" checked={state.availableNow} onChange={(e) => onChange({ availableNow: e.target.checked })} className="accent-orange-500" />
            Available now
          </label>
          <label className="flex items-center gap-2">
            <input type="checkbox" checked={state.deliverToMe} onChange={(e) => onChange({ deliverToMe: e.target.checked })} className="accent-orange-500" />
            Can deliver to me
          </label>
        </div>
      </Section>

      <Section title="Delivery or pickup">
        <div className="flex flex-wrap gap-1.5">
          {([null, "pickup", "delivery"] as (Fulfillment | null)[]).map((f) => (
            <Chip key={f ?? "any"} active={state.fulfillment === f} onClick={() => onChange({ fulfillment: f })}>
              {f == null ? "Any" : f === "pickup" ? "Pickup" : "Delivery"}
            </Chip>
          ))}
        </div>
      </Section>

      <Section title="Diet">
        <div className="flex flex-wrap gap-1.5">
          {DIET_FLAGS.map((d) => (
            <Chip key={d.value} active={state.diet.includes(d.value)} onClick={() => onChange({ diet: toggle<DietFlag>(state.diet, d.value) })}>
              {d.label}
            </Chip>
          ))}
        </div>
      </Section>

      <Section title={`Price (${currency})`}>
        <div className="flex items-center gap-2">
          <PriceInput label="Min" value={state.priceMin} onCommit={(v) => onChange({ priceMin: v })} />
          <span className="text-stone-400">–</span>
          <PriceInput label="Max" value={state.priceMax} onCommit={(v) => onChange({ priceMax: v })} />
        </div>
      </Section>

      <Section title="Cook rating">
        <div className="flex flex-wrap gap-1.5">
          {RATINGS.map((r) => (
            <Chip key={r ?? "any"} active={state.minRating === r} onClick={() => onChange({ minRating: r })}>
              {r == null ? "Any" : `${r}+ ★`}
            </Chip>
          ))}
        </div>
      </Section>

      <Section title="Cuisine">
        <div className="flex flex-wrap gap-1.5">
          {cuisineOptions.map((c) => (
            <Chip key={c} active={state.cuisines.includes(c)} onClick={() => onChange({ cuisines: toggle(state.cuisines, c) })}>
              <span className="capitalize">{c}</span>
            </Chip>
          ))}
        </div>
      </Section>
    </div>
  );
}
