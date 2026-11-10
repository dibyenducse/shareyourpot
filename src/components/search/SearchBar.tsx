"use client";

import type { DistanceUnit } from "@/lib/search/types";
import { DishQueryInput } from "./DishQueryInput";
import { LocationInput, type PickedLocation } from "./LocationInput";
import { RadiusSelector } from "./RadiusSelector";

/** The three inputs: What / Where / Within. Fully controlled. */
export function SearchBar({
  q, onQueryChange, location, onLocationChange, radius, unit, onRadiusChange, onSubmit, submitLabel,
}: {
  q: string;
  onQueryChange: (q: string) => void;
  location: PickedLocation | null;
  onLocationChange: (loc: PickedLocation) => void;
  radius: number;
  unit: DistanceUnit;
  onRadiusChange: (radius: number, unit: DistanceUnit) => void;
  onSubmit?: () => void;
  submitLabel?: string;
}) {
  return (
    <form
      role="search"
      aria-label="Find a dish near me"
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit?.();
      }}
      className="grid gap-3 rounded-3xl border border-stone-200 bg-white p-3 shadow-lg md:grid-cols-[1.1fr_1.3fr_1fr_auto] md:items-center md:gap-0 md:divide-x md:divide-stone-200 md:p-2"
    >
      <div className="md:px-3">
        <DishQueryInput value={q} onChange={onQueryChange} onSubmit={onSubmit} />
      </div>
      <div className="md:px-3">
        <LocationInput value={location} onPick={onLocationChange} onSubmit={onSubmit} />
      </div>
      <div className="md:px-3">
        <RadiusSelector radius={radius} unit={unit} onChange={onRadiusChange} />
      </div>
      {submitLabel && (
        <div className="md:pl-2">
          <button
            type="submit"
            className="w-full rounded-2xl bg-orange-500 px-5 py-3 font-semibold text-white shadow hover:bg-orange-600 md:h-full"
          >
            {submitLabel}
          </button>
        </div>
      )}
    </form>
  );
}
