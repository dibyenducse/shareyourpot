import { NextResponse, type NextRequest } from "next/server";

/**
 * Geocoding proxy for the "Where" box.
 *   GET /api/geocode?q=brick+lane&lat=51.5&lng=-0.1   -> address/city/ZIP autocomplete
 *   GET /api/geocode?lat=51.5&lng=-0.1&reverse=1      -> label for "Use my current location"
 * Uses Photon (OpenStreetMap, no key) unless MAPBOX_ACCESS_TOKEN is set. Proxying keeps
 * provider keys server-side and lets us cache.
 */

export interface GeocodeResult {
  label: string;
  lat: number;
  lng: number;
}

const UA = "ShareYourPot/1.0 (dish search geocoder)";

function coord(v: string | null, limit: number): number | null {
  if (v == null || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) && Math.abs(n) <= limit ? n : null;
}

interface PhotonFeature {
  geometry: { coordinates: [number, number] };
  properties: Record<string, string | undefined>;
}

function photonLabel(p: Record<string, string | undefined>): string {
  const street = [p.housenumber, p.street].filter(Boolean).join(" ");
  const parts = [p.name !== p.city ? p.name : undefined, street || undefined, p.district, p.city, p.postcode, p.state, p.country];
  return [...new Set(parts.filter((x): x is string => !!x))].join(", ");
}

async function photon(q: string | null, lat: number | null, lng: number | null, reverse: boolean): Promise<GeocodeResult[]> {
  const url = reverse
    ? new URL("https://photon.komoot.io/reverse")
    : new URL("https://photon.komoot.io/api/");
  if (reverse) {
    url.searchParams.set("lat", String(lat));
    url.searchParams.set("lon", String(lng));
  } else {
    url.searchParams.set("q", q ?? "");
    url.searchParams.set("limit", "6");
    if (lat != null && lng != null) {
      url.searchParams.set("lat", String(lat));
      url.searchParams.set("lon", String(lng));
    }
  }
  const res = await fetch(url, { headers: { "User-Agent": UA }, next: { revalidate: 86400 } });
  if (!res.ok) throw new Error(`photon ${res.status}`);
  const json = (await res.json()) as { features?: PhotonFeature[] };
  return (json.features ?? []).map((f) => ({
    label: photonLabel(f.properties),
    lng: f.geometry.coordinates[0],
    lat: f.geometry.coordinates[1],
  }));
}

interface MapboxFeature {
  geometry: { coordinates: [number, number] };
  properties: { full_address?: string; name?: string; place_formatted?: string };
}

async function mapbox(token: string, q: string | null, lat: number | null, lng: number | null, reverse: boolean): Promise<GeocodeResult[]> {
  const url = reverse
    ? new URL("https://api.mapbox.com/search/geocode/v6/reverse")
    : new URL("https://api.mapbox.com/search/geocode/v6/forward");
  url.searchParams.set("access_token", token);
  url.searchParams.set("limit", reverse ? "1" : "6");
  if (reverse) {
    url.searchParams.set("longitude", String(lng));
    url.searchParams.set("latitude", String(lat));
  } else {
    url.searchParams.set("q", q ?? "");
    url.searchParams.set("autocomplete", "true");
    if (lat != null && lng != null) url.searchParams.set("proximity", `${lng},${lat}`);
  }
  const res = await fetch(url, { next: { revalidate: 86400 } });
  if (!res.ok) throw new Error(`mapbox ${res.status}`);
  const json = (await res.json()) as { features?: MapboxFeature[] };
  return (json.features ?? []).map((f) => ({
    label: f.properties.full_address ?? [f.properties.name, f.properties.place_formatted].filter(Boolean).join(", "),
    lng: f.geometry.coordinates[0],
    lat: f.geometry.coordinates[1],
  }));
}

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const q = sp.get("q")?.trim().slice(0, 120) ?? null;
  const lat = coord(sp.get("lat"), 90);
  const lng = coord(sp.get("lng"), 180);
  const reverse = sp.get("reverse") === "1";

  if (reverse ? lat == null || lng == null : !q || q.length < 2) {
    return NextResponse.json({ results: [] });
  }
  try {
    const token = process.env.MAPBOX_ACCESS_TOKEN;
    const results = token ? await mapbox(token, q, lat, lng, reverse) : await photon(q, lat, lng, reverse);
    return NextResponse.json(
      { results },
      { headers: { "Cache-Control": "public, s-maxage=86400, stale-while-revalidate=604800" } },
    );
  } catch {
    return NextResponse.json({ results: [], error: "geocoder_unavailable" }, { status: 502 });
  }
}
