"use client";

import { useId } from "react";
import { convertRadius, RADIUS_MAX, RADIUS_MIN, RADIUS_PRESETS } from "@/lib/search/units";
import type { DistanceUnit } from "@/lib/search/types";

/** "Within": preset chips (1/3/5/10/25/50), a 1–100 slider and a mi/km toggle. */
export function RadiusSelector({
  radius, unit, onChange,
}: { radius: number; unit: DistanceUnit; onChange: (radius: number, unit: DistanceUnit) => void }) {
  const sliderId = useId();
  return (
    <div className="min-w-0">
      <div className="flex items-center justify-between px-1">
        <label htmlFor={sliderId} className="text-[11px] font-semibold uppercase tracking-wide text-stone-500">
          Within <span className="normal-case text-stone-800" data-testid="radius-value">{radius} {unit}</span>
        </label>
        <div role="group" aria-label="Distance unit" className="flex overflow-hidden rounded-full border border-stone-200 text-xs">
          {(["mi", "km"] as const).map((u) => (
            <button
              key={u}
              type="button"
              aria-pressed={unit === u}
              onClick={() => u !== unit && onChange(convertRadius(radius, unit, u), u)}
              className={`px-2 py-0.5 ${unit === u ? "bg-stone-800 text-white" : "text-stone-600 hover:bg-stone-100"}`}
            >
              {u}
            </button>
          ))}
        </div>
      </div>
      <div className="mt-1 flex flex-wrap gap-1" role="group" aria-label="Quick distances">
        {RADIUS_PRESETS.map((p) => (
          <button
            key={p}
            type="button"
            aria-pressed={radius === p}
            onClick={() => onChange(p, unit)}
            className={`rounded-full border px-2.5 py-0.5 text-sm ${
              radius === p ? "border-orange-500 bg-orange-500 text-white" : "border-stone-200 text-stone-700 hover:border-orange-300"
            }`}
          >
            {p}
          </button>
        ))}
      </div>
      <input
        id={sliderId}
        type="range"
        min={RADIUS_MIN}
        max={RADIUS_MAX}
        step={1}
        value={radius}
        onChange={(e) => onChange(Number(e.target.value), unit)}
        className="mt-2 w-full accent-orange-500"
        aria-valuetext={`${radius} ${unit === "mi" ? "miles" : "kilometres"}`}
      />
    </div>
  );
}
