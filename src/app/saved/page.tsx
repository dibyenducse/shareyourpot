"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase/client";
import { useUser } from "@/hooks/useUser";
import { defaultSearchState, searchUrl } from "@/lib/search/params";
import { fromMeters } from "@/lib/search/units";
import type { DistanceUnit } from "@/lib/search/types";

interface SavedSearch {
  id: string;
  query: string;
  location_label: string | null;
  lat: number;
  lng: number;
  radius_m: number;
  unit: DistanceUnit;
  notify_push: boolean;
  notify_email: boolean;
  is_active: boolean;
}

/** "My alerts": list, pause/resume and delete saved searches. */
export default function SavedSearchesPage() {
  const { user, loading } = useUser();
  const [items, setItems] = useState<SavedSearch[] | null>(null);

  const load = useCallback(async () => {
    const { data } = await getSupabase().rpc("list_saved_searches");
    setItems((data ?? []) as SavedSearch[]);
  }, []);

  useEffect(() => {
    if (user) load();
  }, [user, load]);

  async function patch(id: string, values: Partial<SavedSearch>) {
    await getSupabase().from("saved_searches").update(values).eq("id", id);
    load();
  }
  async function remove(id: string) {
    await getSupabase().from("saved_searches").delete().eq("id", id);
    load();
  }

  if (!loading && !user) {
    return (
      <main className="mx-auto max-w-2xl px-4 py-16">
        <h1 className="text-2xl font-bold">My alerts</h1>
        <p className="mt-2 text-stone-600">
          <Link href="/login?next=/saved" className="font-medium text-orange-700 underline">Sign in</Link> to see your saved searches.
        </p>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-2xl px-4 py-12">
      <h1 className="text-2xl font-bold">My alerts</h1>
      <p className="mt-1 text-stone-600">We notify you when a matching Kitchen Card or Cooking Now post goes live in range.</p>
      <ul className="mt-6 space-y-3">
        {items?.length === 0 && <li className="text-stone-500">No saved searches yet.</li>}
        {items?.map((s) => {
          const r = Math.round(fromMeters(s.radius_m, s.unit));
          const href = searchUrl({ ...defaultSearchState(s.unit), q: s.query, lat: s.lat, lng: s.lng, loc: s.location_label ?? "", r, unit: s.unit });
          return (
            <li key={s.id} className="rounded-2xl border border-stone-200 bg-white p-4">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <Link href={href} className="font-semibold hover:underline">“{s.query}”</Link>
                  <p className="text-sm text-stone-600">
                    within {r} {s.unit}{s.location_label ? ` of ${s.location_label}` : ""}
                  </p>
                </div>
                <button type="button" onClick={() => remove(s.id)} className="text-sm text-stone-500 hover:text-red-600">Delete</button>
              </div>
              <div className="mt-3 flex flex-wrap gap-4 text-sm">
                <label className="flex items-center gap-1.5">
                  <input type="checkbox" checked={s.is_active} onChange={(e) => patch(s.id, { is_active: e.target.checked })} className="accent-orange-500" />
                  Active
                </label>
                <label className="flex items-center gap-1.5">
                  <input type="checkbox" checked={s.notify_push} onChange={(e) => patch(s.id, { notify_push: e.target.checked })} className="accent-orange-500" />
                  Push
                </label>
                <label className="flex items-center gap-1.5">
                  <input type="checkbox" checked={s.notify_email} onChange={(e) => patch(s.id, { notify_email: e.target.checked })} className="accent-orange-500" />
                  Email
                </label>
              </div>
            </li>
          );
        })}
      </ul>
    </main>
  );
}
