-- "Find a Dish Near Me": smart matching + radius search RPCs.
--
-- Matching pipeline for a query such as "biriani" or "chiken polao":
--   1. normalise (unaccent, lowercase, strip punctuation)
--   2. per token: expand via dish_synonyms (exact / typo / prefix hits on any term in a
--      synonym group, incl. local-language names) and via dish_lexicon (typo correction
--      against words that actually occur in dish names/tags)
--   3. build a tsquery: tokens AND-ed, each token's alternatives OR-ed, with prefix
--      matching for search-as-you-type; whole-phrase synonyms are OR-ed on top
--   4. match rows by full-text (title/description/tags/cuisine/category, weighted) OR
--      trigram word_similarity on the compact search_doc (catches remaining typos)

-- ---------------------------------------------------------------------------
-- Synonyms (multilingual, incl. common misspellings)
-- ---------------------------------------------------------------------------
create table public.dish_synonyms (
  id          bigint generated always as identity primary key,
  group_key   text not null,             -- e.g. 'biryani'
  term        text not null,             -- e.g. 'biriyani', 'বিরিয়ানি', 'pulao', 'pilaf'
  lang        text not null default 'en',
  term_norm   text generated always as (public.normalize_dish_text(term)) stored,
  unique (group_key, term_norm)
);

create index dish_synonyms_term_idx  on public.dish_synonyms (term_norm text_pattern_ops);
create index dish_synonyms_trgm_idx  on public.dish_synonyms using gin (term_norm extensions.gin_trgm_ops);
create index dish_synonyms_group_idx on public.dish_synonyms (group_key);

alter table public.dish_synonyms enable row level security;
create policy dish_synonyms_public_read on public.dish_synonyms for select using (true);

-- ---------------------------------------------------------------------------
-- Lexicon of words that occur in dish names/tags/cuisines: used for typo correction.
-- Maintained incrementally by the dish triggers; words are never deleted (harmless).
-- ---------------------------------------------------------------------------
create table public.dish_lexicon (
  word text primary key check (char_length(word) between 2 and 60)
);
create index dish_lexicon_trgm_idx   on public.dish_lexicon using gin (word extensions.gin_trgm_ops);
create index dish_lexicon_prefix_idx on public.dish_lexicon (word text_pattern_ops);

alter table public.dish_lexicon enable row level security;
create policy dish_lexicon_public_read on public.dish_lexicon for select using (true);

create or replace function public.dish_lexicon_collect()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.dish_lexicon (word)
  select distinct w
    from regexp_split_to_table(new.search_doc, '\s+') as w
   where char_length(w) between 3 and 60
     and w !~ '^[0-9]+$'
  on conflict do nothing;
  return null;
end;
$$;

create trigger kitchen_cards_lexicon after insert or update of search_doc on public.kitchen_cards
  for each row execute function public.dish_lexicon_collect();
create trigger cooking_now_posts_lexicon after insert or update of search_doc on public.cooking_now_posts
  for each row execute function public.dish_lexicon_collect();

-- ---------------------------------------------------------------------------
-- Query expansion
-- ---------------------------------------------------------------------------

-- All alternative spellings/synonyms/corrections for ONE normalised token or phrase.
create or replace function public.expand_dish_term(p_term text)
returns setof text
language sql
stable
parallel safe
set search_path = public, extensions
set pg_trgm.similarity_threshold = 0.3
as $$
  with t as (select p_term as term, char_length(p_term) as len),
  exact as (
    select distinct s.group_key from public.dish_synonyms s, t where s.term_norm = t.term
  ),
  fuzzy as (
    -- Only when the term is not itself a known synonym (otherwise "polao" would also
    -- pull in groups one edit away).
    select distinct s.group_key
      from public.dish_synonyms s, t
     where not exists (select 1 from exact)
       and t.len >= 4
       and (
            -- typo tolerance: biriani / biriyani / briyani -> biryani
            (s.term_norm % t.term
             and extensions.levenshtein_less_equal(s.term_norm, t.term, 2) <= case when t.len >= 7 then 2 else 1 end)
            -- search-as-you-type: "biry" -> biryani group
         or (s.term_norm like t.term || '%' and s.term_norm not like '% %'))
  ),
  groups as (select group_key from exact union select group_key from fuzzy),
  corrections as (
    -- typo correction against real dish vocabulary (e.g. "chiken" -> "chicken")
    select l.word
      from public.dish_lexicon l, t
     where t.len >= 4
       and not exists (select 1 from public.dish_lexicon x where x.word = t.term)
       and (l.word % t.term or l.word like left(t.term, 2) || '%')
       and abs(char_length(l.word) - t.len) <= 2
       and extensions.levenshtein_less_equal(l.word, t.term, 2) <= case when t.len >= 7 then 2 else 1 end
     order by extensions.levenshtein(l.word, t.term), extensions.similarity(l.word, t.term) desc
     limit 3
  )
  select term from t
  union
  select s.term_norm from public.dish_synonyms s join groups g using (group_key)
  union
  select word from corrections
$$;

-- Build the full-text query for a free-text dish search (NULL if nothing searchable).
create or replace function public.build_dish_tsquery(p_query text)
returns tsquery
language plpgsql
stable
parallel safe
set search_path = public, extensions
as $$
declare
  v_norm   text := public.normalize_dish_text(p_query);
  v_token  text;
  v_alt    text;
  v_tok_q  tsquery;
  v_all    tsquery;
  v_phrase tsquery;
  v_part   tsquery;
  v_stem   tsquery;
begin
  if v_norm = '' then
    return null;
  end if;

  foreach v_token in array regexp_split_to_array(v_norm, ' ') loop
    -- skip English stop words ("with", "and", ...) unless it is the only token
    continue when v_token = ''
               or (v_norm <> v_token and numnode(plainto_tsquery('english', v_token)) = 0);
    v_tok_q := null;
    for v_alt in select public.expand_dish_term(v_token) loop
      if position(' ' in v_alt) > 0 then
        v_part := phraseto_tsquery('simple', v_alt);
      else
        -- prefix match on the raw term, plus the stemmed English form when it differs
        -- ("tacos" -> "taco"); keeping the tsquery small keeps per-row rechecks cheap.
        v_part := to_tsquery('simple', quote_literal(v_alt) || ':*');
        v_stem := plainto_tsquery('english', v_alt);
        if numnode(v_stem) > 0 and v_stem::text <> quote_literal(v_alt) then
          v_part := v_part || v_stem;
        end if;
      end if;
      continue when v_part is null or numnode(v_part) = 0;
      v_tok_q := case when v_tok_q is null then v_part else v_tok_q || v_part end;
    end loop;
    continue when v_tok_q is null;
    v_all := case when v_all is null then v_tok_q else v_all && v_tok_q end;
  end loop;

  -- Multi-word synonyms, e.g. "chicken curry" <-> "murgir jhol".
  if position(' ' in v_norm) > 0 then
    for v_alt in select public.expand_dish_term(v_norm) loop
      continue when v_alt = v_norm;
      v_phrase := phraseto_tsquery('simple', v_alt);
      continue when numnode(v_phrase) = 0;
      v_all := case when v_all is null then v_phrase else v_all || v_phrase end;
    end loop;
  end if;

  return v_all;
end;
$$;

-- Trigram fallback for typos the lexicon did not catch. EVERY token (3+ chars) must
-- fuzzy-match the doc; otherwise "chicken biryani" would match any chicken dish.
-- Callers prefilter with `q <% doc` so the GIN trigram index can be used.
create or replace function public.dish_fuzzy_match(p_norm_query text, p_doc text)
returns boolean
language sql
immutable
parallel safe
set search_path = public, extensions
as $$
  select coalesce(bool_and(extensions.word_similarity(tok, p_doc) >= 0.5), false)
    from regexp_split_to_table(p_norm_query, ' ') tok
   where char_length(tok) >= 3
$$;

-- ---------------------------------------------------------------------------
-- Core search (internal). Callers: search_dishes, dish_search_fallback, alerts.
-- ---------------------------------------------------------------------------
create or replace function public.search_dishes_core(
  p_query          text,
  p_lat            double precision,
  p_lng            double precision,
  p_radius_meters  integer,
  p_filters        jsonb,
  p_sort           text,
  p_limit          integer,
  p_offset         integer,
  p_live_first     boolean default true
)
returns table (
  result_type        text,
  id                 uuid,
  cook_id            uuid,
  cook_name          text,
  cook_avatar_url    text,
  cook_rating        numeric,
  cook_rating_count  integer,
  title              text,
  title_local        text,
  description        text,
  photo_url          text,
  cuisine            text,
  category           text,
  diet_flags         text[],
  price_cents        integer,
  currency           text,
  buyer_price_cents  bigint,
  buyer_currency     text,
  distance_m         integer,
  distance           numeric,
  distance_unit      text,
  approx_lat         double precision,
  approx_lng         double precision,
  approx_radius_m    integer,
  is_live            boolean,
  ready_at           timestamptz,
  available_until    timestamptz,
  portions_left      integer,
  prep_time_minutes  integer,
  pickup_available   boolean,
  delivery_available boolean,
  can_deliver        boolean,
  match_score        real,
  total_count        bigint
)
language plpgsql
stable
security definer
set search_path = public, extensions
set pg_trgm.word_similarity_threshold = 0.5
-- JIT compilation costs ~1 s once a plan's estimated cost crosses jit_*_above_cost; it
-- never pays off for an interactive, LIMITed query like this one.
set jit = off
-- Text predicates (@@, <%) cost ~5 us/row but the planner prices them as nearly free, so
-- it may prefer a seq scan + filter over the selective GIN indexes. Every table touched
-- here has a suitable index; this only applies inside this function.
set enable_seqscan = off
as $fn$
declare
  v_filters    jsonb   := coalesce(p_filters, '{}'::jsonb);
  v_radius     integer := least(greatest(coalesce(p_radius_meters, 8047), 100), 160935); -- 100 m .. 100 mi
  v_norm       text    := public.normalize_dish_text(p_query);
  v_tsq        tsquery;
  v_ccy        text    := upper(coalesce(nullif(v_filters ->> 'currency', ''), 'USD'));
  v_ccy_rate   numeric;
  v_km         boolean := v_filters ->> 'unit' = 'km';
  v_cuisines   text[];
  v_categories text[];
  v_diet       text[];
  v_types      text[];
  v_sort       text    := coalesce(nullif(p_sort, ''), 'nearest');
  v_origin     extensions.geography;
  v_box        extensions.geography;
  v_cook_ids   uuid[];
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'invalid coordinates' using errcode = '22023';
  end if;
  if v_sort not in ('nearest', 'best_match', 'rating', 'price_asc', 'ready_soonest') then
    raise exception 'invalid sort: %', v_sort using errcode = '22023';
  end if;

  if v_norm <> '' then
    v_tsq := public.build_dish_tsquery(v_norm);
  end if;
  select r.usd_per_unit into v_ccy_rate from public.fx_rates r where r.currency = v_ccy;
  v_origin := extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography;
  v_box    := extensions._st_expand(v_origin, v_radius);

  -- Strategy. Text predicates cost ~5 us/row but the planner prices them as free, so
  -- choose explicitly:
  --  * spatial-first (browse, or few cooks in range): pass the in-range cook ids so only
  --    dishes of those cooks are text-checked (cook_id index);
  --  * text-first (dense area / wide radius): materialise the GIN-index text matches,
  --    then keep the ones whose cook is in range.
  if v_norm = '' or (select count(*) from (
                       select 1 from public.cook_locations l
                        where l.location operator(extensions.&&) v_box limit 6501) b) <= 6500 then
    select array_agg(l.cook_id) into v_cook_ids
      from public.cook_locations l
     where l.location operator(extensions.&&) v_box
       and extensions.st_distance(l.location, v_origin) <= v_radius;
    if v_cook_ids is null then
      return;
    end if;
  end if;

  select array_agg(lower(x)) into v_cuisines   from jsonb_array_elements_text(coalesce(v_filters -> 'cuisines', '[]')) x;
  select array_agg(lower(x)) into v_categories from jsonb_array_elements_text(coalesce(v_filters -> 'categories', '[]')) x;
  select array_agg(lower(replace(x, '-', '_'))) into v_diet from jsonb_array_elements_text(coalesce(v_filters -> 'diet', '[]')) x;
  select array_agg(lower(x)) into v_types      from jsonb_array_elements_text(coalesce(v_filters -> 'types', '[]')) x;

  -- Dynamic SQL so every search gets a custom plan for its actual values: the planner
  -- then picks text-first (GIN) for rare dishes over big radii, or space-first (GIST)
  -- for small radii / browsing. Values are passed with USING (never interpolated).
  return query execute format($q$
  with cand as %s (
    -- Text + dish-level filters. Uses the GIN (full-text / trigram) indexes when selective.
    select 'cooking_now'::text as result_type, p.id, p.cook_id, true as is_live, p.ready_at,
           null::integer as prep_time_minutes, p.price_cents, p.currency::text as currency,
           p.search_vector, p.search_doc, p.title_norm, p.title_local_norm
      from public.cooking_now_posts p
     where ($25::uuid[] is null or p.cook_id = any ($25::uuid[]))
       and p.status = 'live' and p.available_until > now() and coalesce(p.portions_left, 1) > 0
       and ($11 is null or 'live' = any ($11))
       and ($3 = '' or p.search_vector @@ $4
            or ($3 <%% p.search_doc
                and ($24::text[] is null or not exists (
                      select 1 from unnest($24::text[]) t where extensions.word_similarity(t, p.search_doc) < 0.5))))
       and ($8  is null or lower(p.cuisine)  = any ($8))
       and ($9  is null or lower(p.category) = any ($9))
       and ($10 is null or p.diet_flags @> $10)
    union all
    select 'kitchen_card'::text, k.id, k.cook_id, false, null::timestamptz,
           k.prep_time_minutes, k.price_cents, k.currency::text,
           k.search_vector, k.search_doc, k.title_norm, k.title_local_norm
      from public.kitchen_cards k
     where ($25::uuid[] is null or k.cook_id = any ($25::uuid[]))
       and k.is_active
       and ($11 is null or 'kitchen' = any ($11))
       and ($3 = '' or k.search_vector @@ $4
            or ($3 <%% k.search_doc
                and ($24::text[] is null or not exists (
                      select 1 from unnest($24::text[]) t where extensions.word_similarity(t, k.search_doc) < 0.5))))
       and ($8  is null or lower(k.cuisine)  = any ($8))
       and ($9  is null or lower(k.category) = any ($9))
       and ($10 is null or k.diet_flags @> $10)
  ),
  -- MATERIALIZED fence with NARROW rows: every filter (incl. radius) is applied before any
  -- relevance scoring or sorting; display columns are fetched later for one page only.
  filtered as materialized (
    select x.* from (
      select c.result_type, c.id, c.cook_id, c.is_live, c.ready_at, c.prep_time_minutes,
             ck.rating_avg, ck.rating_count, ck.accepting_orders,
             extensions.st_distance(l.location, $1) as dist,
             ck.delivery_available and extensions.st_distance(l.location, $1) <= ck.delivery_radius_m as can_deliver,
             case when c.currency = $6 then c.price_cents::bigint
                  else round(c.price_cents * fx.usd_per_unit / $7)::bigint end as buyer_price,
             case when $5 = 'best_match' and $3 <> ''
                  then (coalesce(ts_rank_cd('{0.1, 0.3, 0.6, 1.0}', c.search_vector, $4, 1), 0)
                    + extensions.word_similarity($3, c.search_doc)
                    + case when c.title_norm = $3 or c.title_local_norm = $3 then 1.0
                           when c.title_norm like $3 || '%%' then 0.5 else 0 end)::real
             end as rank_score
        from cand c
        join public.cook_locations l on l.cook_id = c.cook_id
        join public.cooks ck on ck.id = c.cook_id
        left join public.fx_rates fx on fx.currency = c.currency
       -- Radius written as bbox && + distance (not ST_DWithin): `&&` against a constant box
       -- is estimated from PostGIS column stats, while ST_DWithin's selectivity is a tiny
       -- default that makes the planner badly underestimate dense areas.
       where l.location operator(extensions.&&) $23
         and extensions.st_distance(l.location, $1) <= $2
         and ($12::numeric is null or ck.rating_avg >= $12)
         and (not $15 or c.is_live or ck.accepting_orders)
         and ($16::text is null
              or ($16 = 'pickup'   and ck.pickup_available)
              or ($16 = 'delivery' and ck.delivery_available))
    ) x
    where (not $17 or x.can_deliver)
      and ($13::bigint is null or x.buyer_price >= $13)
      and ($14::bigint is null or x.buyer_price <= $14)
  ),
  page as materialized (
    select f.*
      from filtered f
     order by
             case when $20 then f.is_live end desc nulls last,
             case when $5 = 'best_match'    then f.rank_score end desc nulls last,
             case when $5 = 'rating'        then f.rating_avg end desc nulls last,
             case when $5 = 'rating'        then f.rating_count end desc nulls last,
             case when $5 = 'price_asc'     then f.buyer_price end asc nulls last,
             case when $5 = 'ready_soonest' then
               case when f.is_live then greatest(f.ready_at, now())
                    when f.accepting_orders then now() + make_interval(mins => coalesce(f.prep_time_minutes, 120))
               end end asc nulls last,
             f.dist asc,
             f.id
     limit $18 offset $19
  )
  select f.result_type, f.id, f.cook_id, ck.display_name, ck.avatar_url, ck.rating_avg, ck.rating_count,
         coalesce(p.title, k.title), coalesce(p.title_local, k.title_local), coalesce(p.description, k.description),
         coalesce(p.photo_url, k.photo_url), coalesce(p.cuisine, k.cuisine), coalesce(p.category, k.category),
         coalesce(p.diet_flags, k.diet_flags), coalesce(p.price_cents, k.price_cents), coalesce(p.currency, k.currency)::text,
         f.buyer_price, $6,
         -- PRIVACY: distance is rounded to 0.1 of the display unit (never below 0.1).
         (greatest(round(f.dist / $21), 1) * $21)::integer,
         round((greatest(round(f.dist / $21), 1) * $21 / ($21 * 10))::numeric, 1),
         case when $22 then 'km' else 'mi' end,
         extensions.st_y(ck.approx_location::extensions.geometry), extensions.st_x(ck.approx_location::extensions.geometry),
         ck.approx_radius_m,
         f.is_live, p.ready_at, p.available_until, p.portions_left, k.prep_time_minutes,
         ck.pickup_available, ck.delivery_available, f.can_deliver,
         case when $3 = '' then 0::real else coalesce(f.rank_score,
                  (coalesce(ts_rank_cd('{0.1, 0.3, 0.6, 1.0}', coalesce(p.search_vector, k.search_vector), $4, 1), 0)
                    + extensions.word_similarity($3, coalesce(p.search_doc, k.search_doc))
                    + case when coalesce(p.title_norm, k.title_norm) = $3 or coalesce(p.title_local_norm, k.title_local_norm) = $3 then 1.0
                           when coalesce(p.title_norm, k.title_norm) like $3 || '%%' then 0.5 else 0 end)::real) end,
         (select count(*) from filtered)
    from page f
    join public.cooks ck on ck.id = f.cook_id
    left join public.cooking_now_posts p on f.result_type = 'cooking_now'  and p.id = f.id
    left join public.kitchen_cards     k on f.result_type = 'kitchen_card' and k.id = f.id
   order by
     case when $20 then f.is_live end desc nulls last,
     case when $5 = 'best_match'    then f.rank_score end desc nulls last,
     case when $5 = 'rating'        then f.rating_avg end desc nulls last,
     case when $5 = 'rating'        then f.rating_count end desc nulls last,
     case when $5 = 'price_asc'     then f.buyer_price end asc nulls last,
     case when $5 = 'ready_soonest' then
       case when f.is_live then greatest(f.ready_at, now())
            when f.accepting_orders then now() + make_interval(mins => coalesce(f.prep_time_minutes, 120))
       end end asc nulls last,
     f.dist asc,
     f.id
  $q$, case when v_cook_ids is null then 'materialized' else 'not materialized' end)
  using
    v_origin,                                                                                  -- $1
    v_radius,                                                                                  -- $2
    v_norm,                                                                                    -- $3
    v_tsq,                                                                                     -- $4
    v_sort,                                                                                    -- $5
    v_ccy,                                                                                     -- $6
    coalesce(v_ccy_rate, 1),                                                                   -- $7
    v_cuisines,                                                                                -- $8
    v_categories,                                                                              -- $9
    v_diet,                                                                                    -- $10
    v_types,                                                                                   -- $11
    nullif(v_filters ->> 'min_rating', '')::numeric,                                           -- $12
    round(nullif(v_filters ->> 'price_min', '')::numeric * 100)::bigint,                       -- $13
    round(nullif(v_filters ->> 'price_max', '')::numeric * 100)::bigint,                       -- $14
    coalesce((v_filters ->> 'available_now')::boolean, false),                                 -- $15
    nullif(v_filters ->> 'fulfillment', ''),                                                   -- $16
    coalesce((v_filters ->> 'deliver_to_me')::boolean, false),                                 -- $17
    greatest(least(coalesce(p_limit, 20), 100), 1),                                            -- $18
    greatest(coalesce(p_offset, 0), 0),                                                        -- $19
    coalesce(p_live_first, true),                                                              -- $20
    case when v_km then 100 else 160.9344 end::numeric,                                        -- $21 rounding step (0.1 unit)
    v_km,                                                                                      -- $22
    v_box,                                                                                     -- $23 search bbox
    -- $24: tokens that must EACH fuzzy-match (multi-word queries only; for one word `<%` suffices)
    case when array_length(array(select t from regexp_split_to_table(v_norm, ' ') t where char_length(t) >= 3), 1) > 1
         then array(select t from regexp_split_to_table(v_norm, ' ') t where char_length(t) >= 3) end,
    v_cook_ids;                                                                                -- $25 in-range cooks (spatial-first only)
end;
$fn$;

revoke all on function public.search_dishes_core(text, double precision, double precision, integer, jsonb, text, integer, integer, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Public RPC: search_dishes
--   filters (all optional):
--     cuisines[]   categories[]   diet[] (all required: halal, vegetarian, vegan, ...)
--     min_rating   price_min / price_max (major units of `currency`)
--     currency     buyer currency for approx. prices + price filter (default USD)
--     unit         'mi' | 'km' (controls distance rounding/display; default mi)
--     fulfillment  'pickup' | 'delivery'
--     available_now (bool)   deliver_to_me (bool)   types[] ('live','kitchen')
--   sort: nearest (default) | best_match | rating | price_asc | ready_soonest
--   page: 1-based. Live Cooking Now posts are always ranked first.
-- ---------------------------------------------------------------------------
create or replace function public.search_dishes(
  query          text,
  lat            double precision,
  lng            double precision,
  radius_meters  integer,
  filters        jsonb   default '{}'::jsonb,
  sort           text    default 'nearest',
  page           integer default 1,
  page_size      integer default 20
)
returns table (
  result_type text, id uuid, cook_id uuid, cook_name text, cook_avatar_url text,
  cook_rating numeric, cook_rating_count integer, title text, title_local text, description text,
  photo_url text, cuisine text, category text, diet_flags text[], price_cents integer, currency text,
  buyer_price_cents bigint, buyer_currency text, distance_m integer, distance numeric, distance_unit text,
  approx_lat double precision, approx_lng double precision, approx_radius_m integer,
  is_live boolean, ready_at timestamptz, available_until timestamptz, portions_left integer,
  prep_time_minutes integer, pickup_available boolean, delivery_available boolean, can_deliver boolean,
  match_score real, total_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select * from public.search_dishes_core(
    query, lat, lng, radius_meters, filters, sort,
    least(greatest(coalesce(page_size, 20), 1), 50),
    (greatest(coalesce(page, 1), 1) - 1) * least(greatest(coalesce(page_size, 20), 1), 50),
    true)
$$;

grant execute on function public.search_dishes(text, double precision, double precision, integer, jsonb, text, integer, integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Public RPC: dish_search_fallback — for the empty state:
--   "No biryani within 5 mi. Expand to 10 mi?" + similar dishes nearby.
-- Returns { nearest_match_m, similar: [...] }; the client picks the next preset radius
-- that covers nearest_match_m. Looks up to 100 mi away.
-- ---------------------------------------------------------------------------
create or replace function public.dish_search_fallback(
  query          text,
  lat            double precision,
  lng            double precision,
  radius_meters  integer,
  filters        jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
set pg_trgm.word_similarity_threshold = 0.4
as $$
declare
  v_norm      text  := public.normalize_dish_text(query);
  v_tsq       tsquery := public.build_dish_tsquery(query);
  v_nearest   integer;
  v_cuisines  jsonb;
  v_similar   jsonb;
begin
  select r.distance_m into v_nearest
    from public.search_dishes_core(query, lat, lng, 160935, filters, 'nearest', 1, 0, false) r;

  -- cuisines of dishes that match the query anywhere (sampled), e.g. biryani -> Bangladeshi, Indian
  select jsonb_agg(distinct lower(m.cuisine)) into v_cuisines
    from (
      (select k.cuisine from public.kitchen_cards k
        where k.is_active and k.cuisine is not null
          and ((v_tsq is not null and k.search_vector @@ v_tsq) or (v_norm <% k.search_doc and public.dish_fuzzy_match(v_norm, k.search_doc)))
        limit 200)
      union all
      (select p.cuisine from public.cooking_now_posts p
        where p.status = 'live' and p.available_until > now() and p.cuisine is not null
          and ((v_tsq is not null and p.search_vector @@ v_tsq) or (v_norm <% p.search_doc and public.dish_fuzzy_match(v_norm, p.search_doc)))
        limit 50)
    ) m;

  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into v_similar
    from public.search_dishes_core(
           '', lat, lng, radius_meters,
           (coalesce(filters, '{}'::jsonb) - 'cuisines' - 'categories')
             || case when v_cuisines is not null then jsonb_build_object('cuisines', v_cuisines) else '{}'::jsonb end,
           case when v_cuisines is not null then 'nearest' else 'rating' end,
           6, 0, true) r;

  -- nothing from related cuisines nearby: fall back to top-rated dishes nearby
  if v_similar = '[]'::jsonb and v_cuisines is not null then
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into v_similar
      from public.search_dishes_core('', lat, lng, radius_meters,
             coalesce(filters, '{}'::jsonb) - 'cuisines' - 'categories', 'rating', 6, 0, true) r;
  end if;

  return jsonb_build_object('nearest_match_m', v_nearest, 'similar', v_similar);
end;
$$;

grant execute on function public.dish_search_fallback(text, double precision, double precision, integer, jsonb)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Public RPC: search_suggestions — dish-name autocomplete for the "What" box.
-- ---------------------------------------------------------------------------
create or replace function public.search_suggestions(query text, max_results integer default 8)
returns table (suggestion text)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with q as (select public.normalize_dish_text(query) as n),
  candidates as (
    select s.term as suggestion, 0 as kind,
           extensions.similarity(s.term_norm, q.n) as sim
      from public.dish_synonyms s, q
     where char_length(q.n) >= 2 and s.term_norm like q.n || '%'
    union all
    select k.title, 1, extensions.word_similarity(q.n, k.search_doc)
      from public.kitchen_cards k, q
     where char_length(q.n) >= 2 and k.is_active
       and (k.search_doc like q.n || '%' or k.search_doc like '% ' || q.n || '%')
  )
  select suggestion
    from (select distinct on (lower(suggestion)) suggestion, kind, sim from candidates
           order by lower(suggestion), kind, sim desc) d
   order by kind, sim desc, char_length(suggestion)
   limit least(greatest(coalesce(max_results, 8), 1), 20)
$$;

grant execute on function public.search_suggestions(text, integer) to anon, authenticated;
