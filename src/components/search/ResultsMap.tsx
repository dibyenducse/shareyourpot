"use client";

import { useEffect, useRef, useState } from "react";
import type * as Leaflet from "leaflet";
import "leaflet/dist/leaflet.css";
import "leaflet.markercluster/dist/MarkerCluster.css";
import "leaflet.markercluster/dist/MarkerCluster.Default.css";
import type { DishResult } from "@/lib/search/types";
import { DishCard } from "./DishCard";

type L = typeof Leaflet;

/** leaflet.markercluster is a UMD plugin that patches the global `L`, so load it after Leaflet. */
async function loadLeaflet(): Promise<L> {
  const L = (await import("leaflet")).default as unknown as L;
  (window as unknown as { L: L }).L = L;
  await import("leaflet.markercluster");
  return L;
}

function pinHtml(d: DishResult): string {
  const cls = d.is_live ? "bg-red-600 text-white" : "bg-white text-stone-900";
  const label = d.is_live ? "LIVE" : "🍲";
  return `<div class="syp-pin ${cls}" style="padding:2px 8px;border-radius:9999px;font:600 12px/1.6 system-ui;box-shadow:0 1px 4px rgba(0,0,0,.35);white-space:nowrap;border:1px solid rgba(0,0,0,.1)">${label}</div>`;
}

/**
 * Map view. PRIVACY: pins sit on each cook's fuzzed public point and the selected cook
 * gets an approximate-area circle; exact addresses are never sent to the browser.
 */
export default function ResultsMap({
  center, radiusMeters, results, locale, hasMore, loadingMore, onLoadMore,
}: {
  center: { lat: number; lng: number };
  radiusMeters: number;
  results: DishResult[];
  locale: string;
  hasMore: boolean;
  loadingMore: boolean;
  onLoadMore: () => void;
}) {
  const el = useRef<HTMLDivElement>(null);
  const mapRef = useRef<Leaflet.Map | null>(null);
  const leafletRef = useRef<L | null>(null);
  const clusterRef = useRef<Leaflet.MarkerClusterGroup | null>(null);
  const searchCircleRef = useRef<Leaflet.Circle | null>(null);
  const approxCircleRef = useRef<Leaflet.Circle | null>(null);
  const [ready, setReady] = useState(false);
  const [selected, setSelected] = useState<DishResult | null>(null);

  // Create the map once.
  useEffect(() => {
    let cancelled = false;
    loadLeaflet().then((L) => {
      if (cancelled || !el.current || mapRef.current) return;
      leafletRef.current = L;
      // A view must exist before layers are added (Leaflet defers layers until then).
      const map = L.map(el.current, { zoomControl: true, scrollWheelZoom: true }).setView([center.lat, center.lng], 12);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 18,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      }).addTo(map);
      clusterRef.current = L.markerClusterGroup({ showCoverageOnHover: false, maxClusterRadius: 50 }).addTo(map);
      map.on("click", () => setSelected(null));
      mapRef.current = map;
      setReady(true);
    });
    return () => {
      cancelled = true;
      mapRef.current?.remove();
      mapRef.current = null;
    };
    // Initial view only; later centre/radius changes are handled below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Search area.
  useEffect(() => {
    const L = leafletRef.current;
    const map = mapRef.current;
    if (!ready || !L || !map) return;
    searchCircleRef.current?.remove();
    searchCircleRef.current = L.circle([center.lat, center.lng], {
      radius: radiusMeters, color: "#f97316", weight: 1, fillOpacity: 0.04, interactive: false,
    }).addTo(map);
    map.fitBounds(L.latLng(center.lat, center.lng).toBounds(radiusMeters * 2), { padding: [16, 16] });
  }, [ready, center.lat, center.lng, radiusMeters]);

  // Result pins.
  useEffect(() => {
    const L = leafletRef.current;
    const cluster = clusterRef.current;
    if (!ready || !L || !cluster) return;
    cluster.clearLayers();
    cluster.addLayers(
      results.map((d) =>
        L.marker([d.approx_lat, d.approx_lng], {
          icon: L.divIcon({ html: pinHtml(d), className: "", iconSize: undefined }),
          title: `${d.title} — ${d.cook_name}`,
          keyboard: true,
          zIndexOffset: d.is_live ? 1000 : 0,
        }).on("click", (e) => {
          L.DomEvent.stopPropagation(e);
          setSelected(d);
        }),
      ),
    );
  }, [ready, results]);

  // Approximate area for the selected cook.
  useEffect(() => {
    const L = leafletRef.current;
    const map = mapRef.current;
    approxCircleRef.current?.remove();
    approxCircleRef.current = null;
    if (!L || !map || !selected) return;
    approxCircleRef.current = L.circle([selected.approx_lat, selected.approx_lng], {
      radius: selected.approx_radius_m, color: "#0f766e", weight: 1, fillOpacity: 0.12, interactive: false,
    }).addTo(map);
  }, [selected]);

  return (
    <div className="relative h-[70vh] min-h-[420px] overflow-hidden rounded-3xl border border-stone-200" data-testid="results-map">
      <div ref={el} className="h-full w-full" />
      {selected && (
        <div className="absolute inset-x-3 bottom-3 z-[1000] mx-auto max-w-md" data-testid="map-selected">
          <div className="relative">
            <button
              type="button"
              aria-label="Close"
              onClick={() => setSelected(null)}
              className="absolute -right-2 -top-2 z-10 h-7 w-7 rounded-full bg-white text-stone-600 shadow"
            >
              ✕
            </button>
            <DishCard dish={selected} locale={locale} compact />
            <p className="mt-1 rounded-lg bg-white/90 px-2 py-1 text-center text-[11px] text-stone-600">
              Shaded circle = approximate area. Exact pickup address is shared after your order is confirmed.
            </p>
          </div>
        </div>
      )}
      {hasMore && (
        <button
          type="button"
          onClick={onLoadMore}
          disabled={loadingMore}
          className="absolute right-3 top-3 z-[1000] rounded-full bg-white px-3 py-1.5 text-sm shadow disabled:opacity-60"
        >
          {loadingMore ? "Loading…" : "Show more on map"}
        </button>
      )}
    </div>
  );
}
