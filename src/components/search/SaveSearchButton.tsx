"use client";

import Link from "next/link";
import { useState } from "react";
import { getSupabase } from "@/lib/supabase/client";
import { enablePushAlerts, pushSupported } from "@/lib/push";
import { radiusMeters, searchUrl, toRpcFilters } from "@/lib/search/params";
import type { SearchState } from "@/lib/search/types";
import { useUser } from "@/hooks/useUser";

/** "Notify me when someone within X mi posts [dish]" — saved search with push/email alerts. */
export function SaveSearchButton({ state, currency }: { state: SearchState; currency: string }) {
  const { user, loading } = useUser();
  const [status, setStatus] = useState<"idle" | "saving" | "saved" | "error">("idle");
  const [message, setMessage] = useState<string | null>(null);
  const dish = state.q.trim();

  if (!dish || state.lat == null || state.lng == null) return null;
  const label = `Notify me when someone within ${state.r} ${state.unit} posts “${dish}”`;

  if (!loading && !user) {
    return (
      <Link
        href={`/login?next=${encodeURIComponent(searchUrl(state))}`}
        className="inline-flex items-center gap-2 rounded-full border border-orange-300 bg-orange-50 px-4 py-2 text-sm font-medium text-orange-800 hover:bg-orange-100"
      >
        🔔 {label}
      </Link>
    );
  }

  async function save() {
    setStatus("saving");
    setMessage(null);
    const filters = toRpcFilters(state, currency);
    // Only dish-level filters make sense for alerts.
    const alertFilters = Object.fromEntries(Object.entries(filters).filter(([k]) => k === "diet" || k === "cuisines"));
    const { error } = await getSupabase().rpc("create_saved_search", {
      query: dish,
      lat: state.lat,
      lng: state.lng,
      radius_meters: radiusMeters(state),
      unit: state.unit,
      location_label: state.loc || null,
      filters: alertFilters,
      notify_push: pushSupported(),
      notify_email: true,
    });
    if (error) {
      setStatus("error");
      setMessage(error.message.includes("limit") ? "You've reached the limit of 25 saved searches." : "Couldn't save this search.");
      return;
    }
    const push = await enablePushAlerts().catch(() => false);
    setStatus("saved");
    setMessage(push ? "Saved — we'll send a push notification and an email." : "Saved — we'll email you.");
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <button
        type="button"
        onClick={save}
        disabled={status === "saving" || status === "saved" || loading}
        className="inline-flex items-center gap-2 rounded-full border border-orange-300 bg-orange-50 px-4 py-2 text-sm font-medium text-orange-800 hover:bg-orange-100 disabled:opacity-70"
        data-testid="save-search"
      >
        {status === "saved" ? "✅" : "🔔"} {status === "saving" ? "Saving…" : label}
      </button>
      {message && (
        <span className={`text-sm ${status === "error" ? "text-red-600" : "text-stone-600"}`} role="status">
          {message} {status === "saved" && <Link href="/saved" className="underline">Manage alerts</Link>}
        </span>
      )}
    </div>
  );
}
