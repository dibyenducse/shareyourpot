# ShareYourPot

Home-cooked food from neighbours. This repo currently implements **§8b "Find a Dish Near Me"**:
radius dish search across Kitchen Cards and live Cooking Now posts.

**Stack:** Next.js 16 (App Router) · Supabase (Postgres 15+/PostGIS/pg_trgm) · Tailwind CSS 4 · Leaflet.

## Quick start

```bash
npm install
cp .env.example .env.local        # fill in your Supabase URL + anon key
supabase init                     # only if supabase/config.toml does not exist yet
supabase start                    # local Supabase (Docker)
supabase db reset                 # applies supabase/migrations/* and supabase/seed.sql
npm run dev
```

For a hosted project, run `supabase link` then `supabase db push`, and load `supabase/seed.sql` with
`psql "$DATABASE_URL" -f supabase/seed.sql` if you want the demo data.

Then open <http://localhost:3000>, type "biryani" and pick a city. Each seed city returns biryani
within 5 miles of its centre:

| City | Centre | Try |
|---|---|---|
| New York | 40.7549, -73.9840 | `/search?q=biryani&lat=40.7549&lng=-73.984&r=5&unit=mi` |
| London | 51.5072, -0.1276 | `/search?q=biriani&lat=51.5072&lng=-0.1276&r=5&unit=mi` |
| Toronto | 43.6532, -79.3832 | `/search?q=biryani&lat=43.6532&lng=-79.3832&r=8&unit=km` |
| Dhaka | 23.8103, 90.4125 | `/search?q=বিরিয়ানি&lat=23.8103&lng=90.4125&r=8&unit=km` |
| Kolkata | 22.5726, 88.3639 | `/search?q=chicken%20curry&lat=22.5726&lng=88.3639&r=5&unit=mi` |
| Sydney | -33.8688, 151.2093 | `/search?q=biryani&lat=-33.8688&lng=151.2093&r=3&unit=mi` (empty, then "Expand to 5 mi?") |

Seeded Cooking Now posts stay live for 12 hours after seeding. Revive them with
`update cooking_now_posts set status = 'live', available_until = now() + interval '12 hours';`

## How it works

### Database (`supabase/migrations`)

| Migration | Contents |
|---|---|
| `…01_extensions` | PostGIS, pg_trgm, unaccent, fuzzystrmatch; `normalize_dish_text()` |
| `…02_core_schema` | `cooks`, **private** `cook_locations`, `kitchen_cards`, `cooking_now_posts`, `orders`, `fx_rates`, RLS, `get_order_pickup_address()` |
| `…03_dish_search` | `dish_synonyms`, `dish_lexicon`, query expansion, `search_dishes()`, `dish_search_fallback()`, `search_suggestions()` |
| `…04_saved_search_alerts` | `saved_searches`, `push_subscriptions`, alert queue + triggers, dispatcher RPCs |

**`search_dishes(query, lat, lng, radius_meters, filters, sort, page, page_size = 20)`** is the main RPC.

- **Radius:** `geography(Point)` columns with GIST indexes. The radius filter is written as
  `location && <box>` plus `ST_Distance(...) <= r`. It is equivalent to `ST_DWithin`, but gives the
  planner accurate row estimates in dense areas.
- **Results:** Kitchen Cards and live Cooking Now posts. Live posts always rank first.
- **Sorts:** `nearest` (default), `best_match`, `rating`, `price_asc`, `ready_soonest`.
- **`filters` (jsonb):** `cuisines[]`, `categories[]`, `diet[]` (all required; vegan implies
  vegetarian), `min_rating`, `price_min`/`price_max` (in the buyer `currency`), `currency`,
  `unit` (`mi`/`km`), `fulfillment` (`pickup`/`delivery`), `available_now`, `deliver_to_me`,
  `types[]` (`live`/`kitchen`).
- **Delivery labels:** `can_deliver` is true when the buyer is inside the cook's delivery radius;
  otherwise the UI labels the result "Pickup only".
- **Prices:** each row returns the local price plus `buyer_price_cents`, converted via `fx_rates`.
  Refresh that table from a rates provider in production; it is seeded with static values.

**Smart matching.** The query is unaccented and lowercased, then each word is expanded:

1. **Synonym groups** (`dish_synonyms`): e.g. `polao ↔ pulao ↔ pilaf ↔ پلو`, `biryani ↔ বিরিয়ানি ↔ बिरयानी`,
   and phrases such as `chicken curry ↔ murgir jhol`.
2. **Typo tolerance:** trigram + Levenshtein matching against synonym terms and against `dish_lexicon`
   (every word that appears in a dish name, tag or cuisine; maintained by trigger). So "biriani" and
   "chiken" both work.
3. **Prefixes** for search-as-you-type ("biry" finds biryani).

The expansions build a weighted full-text query: title (A), tags/cuisine/category (B), description (C).
A trigram fallback (`word_similarity`, where every word must match) catches anything left.
Fuzzy rewrites only apply to words that are not already known terms, so "polao" never drifts to "pollo".

**Empty state.** `dish_search_fallback()` returns the distance to the nearest match (up to 100 mi)
and similar dishes nearby (same cuisines; top-rated nearby if none). The UI uses it to offer
"No biryani within 3 mi. Expand to 5 mi?".

### Privacy

- Exact cook points live in `cook_locations`. RLS lets only the owning cook read them; anon and
  other users get zero rows.
- Search functions are `SECURITY DEFINER` and never return exact coordinates. They return:
  - a **fuzzed public point** (150–500 m from the real one, randomised once per location change so
    repeated reads cannot be averaged), and
  - a display circle radius for the map.
- Distances are **quantised to 0.1 of the display unit** server-side (160.9 m for miles, 100 m for km).
- `get_order_pickup_address(order_id)` reveals the address only to the buyer (or the cook) of an order
  in `confirmed`/`ready`/`completed` status.
- Clients cannot write `cooks.approx_location` or ratings (column-level grants).
- Residual risk: someone running many searches from different points could trilaterate a cook to
  roughly the 0.1-unit quantisation (~100–160 m), about the size of the public circle. Put
  rate limiting on the search RPC (e.g. at your API gateway) if that matters for your launch.

### Frontend (`src/`)

- `/` is a hero search. `/search` is the full experience: What / Where / Within inputs, filters,
  sort, list/map toggle, infinite scroll, empty state, and "Notify me".
- **URL state:** everything lives in the URL (`?q=biryani&lat=..&lng=..&r=10&unit=mi&sort=..&view=map&diet=halal…`),
  so searches can be shared and bookmarked. Parsing and serialisation are in `src/lib/search/params.ts`.
- **Debouncing:** typing and slider drags are debounced (300 ms / 250 ms). Superseded requests are
  aborted and their responses ignored.
- **Units and currency:** the distance unit defaults by locale (mi for US/UK/LR/MM, km elsewhere)
  and has a mi/km toggle. The buyer currency also comes from the locale.
- **Remembered location:** the last location and radius are kept in `localStorage` and restored on
  the next visit.
- **Where box:** "Use my current location" (browser GPS, reverse-geocoded label) or address/city/ZIP
  autocomplete via `/api/geocode`. That route uses Photon/OpenStreetMap, or Mapbox if
  `MAPBOX_ACCESS_TOKEN` is set.
- **Map:** Leaflet with clustered pins on the fuzzed points. Clicking a pin shows the dish card and
  an approximate-area circle. For production, use a tile provider that suits your traffic instead
  of `tile.openstreetmap.org`.

### Saved searches & alerts

1. "Notify me when someone within X mi posts biryani" calls `create_saved_search()` (sign-in by magic
   link). It also registers a web-push subscription when VAPID keys are configured.
2. When a Kitchen Card becomes active or a Cooking Now post goes live, a trigger matches it against
   saved searches whose circle contains the cook. It queues one alert per (search, item), deduplicated.
3. `GET /api/cron/dispatch-alerts` with `Authorization: Bearer $CRON_SECRET` claims queued alerts
   (`FOR UPDATE SKIP LOCKED`) and sends web push (`web-push`) and email (Resend). Failed alerts are
   retried up to 5 times. `vercel.json` schedules it every 5 minutes; any scheduler works
   (pg_cron + pg_net, GitHub Actions…).
4. `/saved` lists alerts, with pause, per-channel toggles, and delete.

## Testing

```bash
npm test                 # unit tests (URL state, units, currency)
npm run typecheck
npm run test:db          # migrations + seed + SQL test suite on a throwaway DB
```

`test:db` needs a plain Postgres with PostGIS and pg_trgm (`PGHOST`/`PGPORT`/`PGUSER` env vars). It
stubs the Supabase roles and `auth` schema with `supabase/tests/00_local_supabase_stub.sql`. The suite
covers:

- every seed city
- typos, synonyms and scripts
- false positives
- every filter and sort
- pagination
- the empty-state fallback
- RLS / privacy checks (anon can't read `cook_locations`; addresses are gated on order status)
- the saved-search → alert pipeline

### Performance

`supabase/tests/perf/load_and_benchmark.sql` loads 50k cooks, 250k Kitchen Cards and 5k live posts
within 50 km of Midtown Manhattan (far denser than reality), then times searches.
Medians on a dev container:

| Query | Matches | Median |
|---|---|---|
| biryani within 5 mi | 681 | 59 ms |
| "biriani" (typo) within 5 mi | 681 | 64 ms |
| "chiken curry" within 10 mi, best match | 1,279 | 207 ms |
| tacos 3 mi, deliver to me | 95 | 35 ms |
| browse (empty query) 3 mi | 2,505 | 24 ms |
| biryani 25 mi, price sort | 16,200 | 367 ms |
| biryani 50 mi, halal, rating | 20,002 | 351 ms |

Typical searches are well under 300 ms. Only the 16–20k-match, 25–50 mile cases go over, and that
is at this artificial density.

`search_dishes_core` has three function-scoped tunings:

- **Strategy choice:** it counts the cooks in the box first, then goes spatial-first for small or
  sparse areas and text-first (GIN) for dense ones.
- **`jit = off`:** JIT compilation added about 1 s to large-estimate plans.
- **`enable_seqscan = off`:** the planner prices text predicates as nearly free and would otherwise
  seq-scan instead of using the selective GIN indexes.
