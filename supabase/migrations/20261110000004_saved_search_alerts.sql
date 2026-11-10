-- Saved searches & alerts:
--   "Notify me when someone within X miles posts [dish]".
-- When a Kitchen Card becomes active or a Cooking Now post goes live, a trigger matches it
-- against saved searches whose circle contains the cook, and queues one alert per
-- (saved search, item). /api/cron/dispatch-alerts drains the queue (web push + email).

create table public.saved_searches (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  query             text not null check (char_length(btrim(query)) between 2 and 100),
  location          extensions.geography(Point, 4326) not null,  -- the buyer's own point; owner-only
  location_label    text,
  radius_m          integer not null check (radius_m between 100 and 160935),
  unit              text not null default 'mi' check (unit in ('mi', 'km')),
  filters           jsonb not null default '{}'::jsonb,
  notify_push       boolean not null default true,
  notify_email      boolean not null default true,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now()
);

create index saved_searches_location_gix on public.saved_searches using gist (location) where is_active;
create index saved_searches_user_idx     on public.saved_searches (user_id);

create or replace function public.saved_searches_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.saved_searches where user_id = new.user_id) >= 25 then
    raise exception 'saved search limit reached (25)' using errcode = '54000';
  end if;
  return new;
end;
$$;

create trigger saved_searches_limit before insert on public.saved_searches
  for each row execute function public.saved_searches_limit();

-- Convenience RPC so clients do not need to build PostGIS values.
create or replace function public.create_saved_search(
  query           text,
  lat             double precision,
  lng             double precision,
  radius_meters   integer,
  unit            text default 'mi',
  location_label  text default null,
  filters         jsonb default '{}'::jsonb,
  notify_push     boolean default true,
  notify_email    boolean default true
)
returns public.saved_searches
language sql
volatile
security invoker
set search_path = public, extensions
as $$
  insert into public.saved_searches (user_id, query, location, location_label, radius_m, unit, filters, notify_push, notify_email)
  values (auth.uid(), btrim(query), st_setsrid(st_makepoint(lng, lat), 4326)::geography, location_label,
          radius_meters, coalesce(unit, 'mi'), coalesce(filters, '{}'::jsonb),
          coalesce(notify_push, true), coalesce(notify_email, true))
  returning *
$$;

revoke all on function public.create_saved_search(text, double precision, double precision, integer, text, text, jsonb, boolean, boolean) from public, anon;
grant execute on function public.create_saved_search(text, double precision, double precision, integer, text, text, jsonb, boolean, boolean) to authenticated;

-- Web-push subscriptions (one per browser/device).
create table public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  created_at  timestamptz not null default now()
);
create index push_subscriptions_user_idx on public.push_subscriptions (user_id);

-- Alert queue.
create table public.saved_search_alerts (
  id               bigint generated always as identity primary key,
  saved_search_id  uuid not null references public.saved_searches (id) on delete cascade,
  user_id          uuid not null references auth.users (id) on delete cascade,
  item_type        text not null check (item_type in ('kitchen_card', 'cooking_now')),
  item_id          uuid not null,
  title            text not null,
  cook_name        text not null,
  distance_m       integer not null,  -- rounded, same privacy rules as search
  created_at       timestamptz not null default now(),
  claimed_at       timestamptz,
  sent_at          timestamptz,
  attempts         integer not null default 0,
  last_error       text,
  unique (saved_search_id, item_type, item_id)
);
create index saved_search_alerts_pending_idx on public.saved_search_alerts (created_at) where sent_at is null;
create index saved_search_alerts_user_idx    on public.saved_search_alerts (user_id, created_at desc);

alter table public.saved_searches       enable row level security;
alter table public.push_subscriptions   enable row level security;
alter table public.saved_search_alerts  enable row level security;

create policy saved_searches_owner on public.saved_searches for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy push_subscriptions_owner on public.push_subscriptions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy saved_search_alerts_owner_read on public.saved_search_alerts for select to authenticated
  using (user_id = auth.uid());
-- The queue is written only by triggers / the service role.
revoke insert, update, delete on public.saved_search_alerts from anon, authenticated;

-- Match ONE newly-live dish against all saved searches in range.
create or replace function public.enqueue_saved_search_alerts(p_item_type text, p_item_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, extensions
set pg_trgm.word_similarity_threshold = 0.5
as $$
declare
  v_cook_id   uuid;
  v_title     text;
  v_vector    tsvector;
  v_doc       text;
  v_diet      text[];
  v_cuisine   text;
  v_count     integer;
begin
  if p_item_type = 'cooking_now' then
    select p.cook_id, p.title, p.search_vector, p.search_doc, p.diet_flags, p.cuisine
      into v_cook_id, v_title, v_vector, v_doc, v_diet, v_cuisine
      from public.cooking_now_posts p where p.id = p_item_id;
  else
    select k.cook_id, k.title, k.search_vector, k.search_doc, k.diet_flags, k.cuisine
      into v_cook_id, v_title, v_vector, v_doc, v_diet, v_cuisine
      from public.kitchen_cards k where k.id = p_item_id;
  end if;
  if v_cook_id is null then
    return 0;
  end if;

  insert into public.saved_search_alerts (saved_search_id, user_id, item_type, item_id, title, cook_name, distance_m)
  select s.id, s.user_id, p_item_type, p_item_id, v_title, c.display_name,
         (greatest(round(st_distance(s.location, l.location) / case when s.unit = 'km' then 100 else 160.9344 end), 1)
           * case when s.unit = 'km' then 100 else 160.9344 end)::integer
    from public.cook_locations l
    join public.cooks c on c.id = l.cook_id
    join public.saved_searches s
      on s.is_active
     and (s.notify_push or s.notify_email)
     and st_dwithin(s.location, l.location, s.radius_m)
   where l.cook_id = v_cook_id
     and s.user_id is distinct from c.user_id
     and (v_vector @@ public.build_dish_tsquery(s.query)
          or (public.normalize_dish_text(s.query) <% v_doc
              and public.dish_fuzzy_match(public.normalize_dish_text(s.query), v_doc)))
     and (s.filters -> 'diet' is null
          or v_diet @> array(select lower(replace(x, '-', '_')) from jsonb_array_elements_text(s.filters -> 'diet') x))
     and (s.filters -> 'cuisines' is null or jsonb_array_length(s.filters -> 'cuisines') = 0
          or lower(v_cuisine) in (select lower(x) from jsonb_array_elements_text(s.filters -> 'cuisines') x))
  on conflict (saved_search_id, item_type, item_id) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.enqueue_saved_search_alerts(text, uuid) from public, anon, authenticated;

create or replace function public.dish_went_live_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_table_name = 'cooking_now_posts' then
    if new.status = 'live' and new.available_until > now()
       and (tg_op = 'INSERT' or old.status is distinct from 'live') then
      perform public.enqueue_saved_search_alerts('cooking_now', new.id);
    end if;
  else
    if new.is_active and (tg_op = 'INSERT' or not old.is_active) then
      perform public.enqueue_saved_search_alerts('kitchen_card', new.id);
    end if;
  end if;
  return null;
end;
$$;

create trigger cooking_now_posts_alerts after insert or update of status on public.cooking_now_posts
  for each row execute function public.dish_went_live_trigger();
create trigger kitchen_cards_alerts after insert or update of is_active on public.kitchen_cards
  for each row execute function public.dish_went_live_trigger();

-- ---------------------------------------------------------------------------
-- Dispatcher API (service role only)
-- ---------------------------------------------------------------------------
-- Atomically claims a batch of pending alerts with everything needed to deliver them.
create or replace function public.claim_saved_search_alerts(batch_size integer default 100)
returns table (
  alert_id bigint, user_id uuid, email text, notify_push boolean, notify_email boolean,
  query text, item_type text, item_id uuid, title text, cook_name text, distance_m integer,
  unit text, push_subscriptions jsonb
)
language sql
volatile
security definer
set search_path = public
as $$
  with claimed as (
    update public.saved_search_alerts a
       set claimed_at = now(), attempts = a.attempts + 1
     where a.id in (
       select x.id from public.saved_search_alerts x
        where x.sent_at is null and x.attempts < 5
          and (x.claimed_at is null or x.claimed_at < now() - interval '10 minutes')
        order by x.created_at
        limit least(greatest(coalesce(batch_size, 100), 1), 500)
        for update skip locked)
    returning a.*
  )
  select c.id, c.user_id, u.email::text, s.notify_push, s.notify_email, s.query,
         c.item_type, c.item_id, c.title, c.cook_name, c.distance_m, s.unit,
         coalesce((select jsonb_agg(jsonb_build_object('endpoint', p.endpoint, 'keys',
                    jsonb_build_object('p256dh', p.p256dh, 'auth', p.auth)))
                     from public.push_subscriptions p where p.user_id = c.user_id), '[]'::jsonb)
    from claimed c
    join public.saved_searches s on s.id = c.saved_search_id
    join auth.users u on u.id = c.user_id
$$;

create or replace function public.complete_saved_search_alert(alert_id bigint, error text default null)
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update public.saved_search_alerts
     set sent_at    = case when error is null then now() end,
         claimed_at = case when error is null then claimed_at end,
         last_error = error
   where id = alert_id
$$;

revoke all on function public.claim_saved_search_alerts(integer)          from public, anon, authenticated;
revoke all on function public.complete_saved_search_alert(bigint, text)   from public, anon, authenticated;
grant execute on function public.claim_saved_search_alerts(integer)        to service_role;
grant execute on function public.complete_saved_search_alert(bigint, text) to service_role;

-- Removes dead push endpoints reported by the push service (410 Gone).
create or replace function public.delete_push_subscription(p_endpoint text)
returns void
language sql
volatile
security definer
set search_path = public
as $$ delete from public.push_subscriptions where endpoint = p_endpoint $$;
revoke all on function public.delete_push_subscription(text) from public, anon, authenticated;
grant execute on function public.delete_push_subscription(text) to service_role;
