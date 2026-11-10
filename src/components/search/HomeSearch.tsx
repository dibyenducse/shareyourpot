"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { useLocalePrefs } from "@/hooks/useLocalePrefs";
import { CITIES } from "@/lib/cities";
import { defaultSearchState, searchUrl } from "@/lib/search/params";
import { loadRemembered } from "@/lib/search/remember";
import type { DistanceUnit } from "@/lib/search/types";
import { DEFAULT_RADIUS } from "@/lib/search/units";
import type { PickedLocation } from "./LocationInput";
import { SearchBar } from "./SearchBar";

const POPULAR = ["biryani", "tacos", "dumplings", "khichuri", "jollof rice", "chicken curry"];

/** Homepage hero search: fills in What/Where/Within and navigates to /search. */
export function HomeSearch() {
  const router = useRouter();
  const { unit: localeUnit } = useLocalePrefs();
  const [q, setQ] = useState("");
  const [location, setLocation] = useState<PickedLocation | null>(null);
  const [radius, setRadius] = useState<{ r: number; unit: DistanceUnit } | null>(null);

  // Start from the last location + radius this browser used.
  useEffect(() => {
    const rem = loadRemembered();
    if (rem) {
      setLocation({ lat: rem.lat, lng: rem.lng, loc: rem.loc });
      setRadius({ r: rem.r, unit: rem.unit });
    }
  }, []);

  const r = radius ?? { r: DEFAULT_RADIUS, unit: localeUnit };

  function go(overrides: { q?: string; location?: PickedLocation } = {}) {
    const loc = overrides.location ?? location;
    router.push(
      searchUrl({
        ...defaultSearchState(r.unit),
        q: (overrides.q ?? q).trim(),
        lat: loc?.lat ?? null,
        lng: loc?.lng ?? null,
        loc: loc?.loc ?? "",
        r: r.r,
        unit: r.unit,
      }),
    );
  }

  return (
    <div>
      <SearchBar
        q={q}
        onQueryChange={setQ}
        location={location}
        onLocationChange={setLocation}
        radius={r.r}
        unit={r.unit}
        onRadiusChange={(rr, unit) => setRadius({ r: rr, unit })}
        onSubmit={() => go()}
        submitLabel="Find dishes"
      />
      <div className="mt-5 flex flex-wrap items-center gap-2 text-sm">
        <span className="text-stone-500">Popular:</span>
        {POPULAR.map((p) => (
          <button key={p} type="button" onClick={() => go({ q: p })} className="rounded-full bg-white px-3 py-1 text-stone-700 shadow-sm ring-1 ring-stone-200 hover:ring-orange-300">
            {p}
          </button>
        ))}
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-2 text-sm">
        <span className="text-stone-500">Cities:</span>
        {CITIES.map((c) => (
          <button
            key={c.name}
            type="button"
            onClick={() => go({ location: { lat: c.lat, lng: c.lng, loc: c.name } })}
            className="rounded-full bg-white px-3 py-1 text-stone-700 shadow-sm ring-1 ring-stone-200 hover:ring-orange-300"
          >
            {c.name}
          </button>
        ))}
      </div>
    </div>
  );
}
