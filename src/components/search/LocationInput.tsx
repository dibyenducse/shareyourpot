"use client";

import { useEffect, useState } from "react";
import { useDebouncedValue } from "@/hooks/useDebouncedValue";
import { Autocomplete } from "./Autocomplete";

export interface PickedLocation {
  lat: number;
  lng: number;
  loc: string;
}

interface GeocodeResult {
  label: string;
  lat: number;
  lng: number;
}

async function geocode(params: Record<string, string>, signal?: AbortSignal): Promise<GeocodeResult[]> {
  const res = await fetch(`/api/geocode?${new URLSearchParams(params)}`, { signal });
  if (!res.ok) return [];
  return ((await res.json()) as { results: GeocodeResult[] }).results;
}

/** "Where": GPS ("Use my current location") or typed address / city / ZIP / postcode. */
export function LocationInput({
  value, onPick, onSubmit,
}: {
  value: PickedLocation | null;
  onPick: (loc: PickedLocation) => void;
  onSubmit?: () => void;
}) {
  const [text, setText] = useState(value?.loc ?? "");
  const [locating, setLocating] = useState(false);
  const [gpsError, setGpsError] = useState<string | null>(null);
  const [suggestions, setSuggestions] = useState<GeocodeResult[]>([]);
  const debounced = useDebouncedValue(text, 250);

  // Keep the box in sync when the location changes elsewhere (URL, remembered location).
  useEffect(() => {
    setText(value?.loc ?? "");
  }, [value?.loc]);

  useEffect(() => {
    const q = debounced.trim();
    if (q.length < 2 || q === value?.loc) {
      setSuggestions([]);
      return;
    }
    const ctrl = new AbortController();
    const bias: Record<string, string> = value ? { lat: String(value.lat), lng: String(value.lng) } : {};
    geocode({ q, ...bias }, ctrl.signal)
      .then((r) => !ctrl.signal.aborted && setSuggestions(r))
      .catch(() => {});
    return () => ctrl.abort();
  }, [debounced, value]);

  function useMyLocation() {
    if (!("geolocation" in navigator)) {
      setGpsError("Location isn't available in this browser.");
      return;
    }
    setLocating(true);
    setGpsError(null);
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const lat = pos.coords.latitude;
        const lng = pos.coords.longitude;
        let label = "Current location";
        try {
          const [r] = await geocode({ lat: String(lat), lng: String(lng), reverse: "1" });
          if (r?.label) label = `Near ${r.label.split(",").slice(0, 2).join(",")}`;
        } catch {
          /* keep generic label */
        }
        setLocating(false);
        onPick({ lat, lng, loc: label });
      },
      (err) => {
        setLocating(false);
        setGpsError(err.code === err.PERMISSION_DENIED ? "Location permission denied — type an address instead." : "Couldn't get your location.");
      },
      { enableHighAccuracy: false, timeout: 10000, maximumAge: 5 * 60 * 1000 },
    );
  }

  return (
    <div className="min-w-0 flex-1">
      <Autocomplete
        label="Where"
        value={text}
        onInputChange={setText}
        suggestions={suggestions}
        getKey={(s) => `${s.lat},${s.lng},${s.label}`}
        renderItem={(s) => <span>📍 {s.label}</span>}
        onPick={(s) => {
          setText(s.label);
          setSuggestions([]);
          onPick({ lat: s.lat, lng: s.lng, loc: s.label });
        }}
        onEnter={() => {
          // Enter with suggestions but none highlighted: take the top one.
          if (suggestions[0] && text !== value?.loc) {
            const s = suggestions[0];
            setText(s.label);
            onPick({ lat: s.lat, lng: s.lng, loc: s.label });
          } else {
            onSubmit?.();
          }
        }}
        placeholder="Address, city, ZIP or postcode"
        icon="📍"
        inputTestId="location-input"
        trailing={
          <button
            type="button"
            onClick={useMyLocation}
            disabled={locating}
            className="shrink-0 whitespace-nowrap rounded-full px-2 py-1 text-xs font-medium text-orange-700 hover:bg-orange-50 disabled:opacity-60"
            title="Use my current location"
          >
            {locating ? "Locating…" : "◎ Use my location"}
          </button>
        }
      />
      {gpsError && <p className="px-1 pt-1 text-xs text-red-600" role="alert">{gpsError}</p>}
    </div>
  );
}
