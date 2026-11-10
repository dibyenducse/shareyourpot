-- Core marketplace tables needed by dish search: cooks, their PRIVATE locations,
-- Kitchen Cards (standing menu items), Cooking Now posts (live, time-limited batches),
-- orders (used to gate pickup-address disclosure) and FX rates.

-- ---------------------------------------------------------------------------
-- Cooks (public profile; contains NO exact location)
-- ---------------------------------------------------------------------------
create table public.cooks (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid unique references auth.users (id) on delete cascade,
  display_name        text not null check (char_length(display_name) between 1 and 80),
  avatar_url          text,
  bio                 text,
  city                text,
  country_code        char(2),
  currency            char(3) not null default 'USD',
  rating_avg          numeric(3, 2) not null default 0 check (rating_avg between 0 and 5),
  rating_count        integer not null default 0 check (rating_count >= 0),
  accepting_orders    boolean not null default true,
  pickup_available    boolean not null default true,
  delivery_available  boolean not null default false,
  delivery_radius_m   integer not null default 0 check (delivery_radius_m between 0 and 80000),
  -- Public, deliberately fuzzed point (150–500 m from the real one) + display circle radius.
  -- Maintained by trigger from cook_locations; never written by clients.
  approx_location     extensions.geography(Point, 4326),
  approx_radius_m     integer not null default 800,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Cook exact location (PRIVATE). Only the owning cook can read it via RLS.
-- Search reads it through SECURITY DEFINER functions that never return it.
-- ---------------------------------------------------------------------------
create table public.cook_locations (
  cook_id              uuid primary key references public.cooks (id) on delete cascade,
  location             extensions.geography(Point, 4326) not null,
  address_line         text,
  postal_code          text,
  city                 text,
  country_code         char(2),
  pickup_instructions  text,
  updated_at           timestamptz not null default now()
);

create index cook_locations_location_gix on public.cook_locations using gist (location);

-- Fuzz the public point whenever the private point changes. The offset is random but
-- stored, so repeated reads cannot be averaged to recover the real point.
create or replace function public.cook_locations_sync_approx()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if tg_op = 'INSERT' or new.location is distinct from old.location then
    update public.cooks
       set approx_location = extensions.st_project(
             new.location,
             150 + random() * 350,          -- metres
             radians(random() * 360)),      -- bearing
           updated_at = now()
     where id = new.cook_id;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger cook_locations_sync_approx
  before insert or update on public.cook_locations
  for each row execute function public.cook_locations_sync_approx();

-- ---------------------------------------------------------------------------
-- Shared search-field maintenance for dish-like rows
-- ---------------------------------------------------------------------------
-- Also normalises diet flags; vegan implies vegetarian so the "veg" filter includes vegan dishes.
create or replace function public.set_dish_search_fields()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
declare
  v_tags text := public.normalize_dish_text(array_to_string(new.tags, ' '));
  v_meta text := public.normalize_dish_text(concat_ws(' ', new.cuisine, new.category));
begin
  new.search_vector :=
       setweight(to_tsvector('english', public.normalize_dish_text(new.title)), 'A')
    || setweight(to_tsvector('simple',  public.normalize_dish_text(concat_ws(' ', new.title, new.title_local))), 'A')
    || setweight(to_tsvector('simple',  concat_ws(' ', v_tags, v_meta)), 'B')
    || setweight(to_tsvector('english', concat_ws(' ', v_tags, v_meta)), 'B')
    || setweight(to_tsvector('english', public.normalize_dish_text(new.description)), 'C');
  new.title_norm := public.normalize_dish_text(new.title);
  new.title_local_norm := nullif(public.normalize_dish_text(new.title_local), '');
  new.search_doc := concat_ws(' ',
    public.normalize_dish_text(new.title),
    public.normalize_dish_text(new.title_local),
    v_tags, v_meta);
  new.diet_flags := coalesce(array(
    select distinct f from (
      select lower(replace(btrim(x), '-', '_')) as f from unnest(new.diet_flags) x
      union all
      select 'vegetarian' where 'vegan' = any (array(select lower(btrim(y)) from unnest(new.diet_flags) y))
    ) s where f <> '' order by 1), '{}');
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Kitchen Cards: a cook's standing menu items
-- ---------------------------------------------------------------------------
create table public.kitchen_cards (
  id                 uuid primary key default gen_random_uuid(),
  cook_id            uuid not null references public.cooks (id) on delete cascade,
  title              text not null check (char_length(title) between 1 and 120),
  title_local        text,                      -- dish name in the local language/script
  description        text,
  tags               text[] not null default '{}',
  cuisine            text,
  category           text,
  diet_flags         text[] not null default '{}', -- halal, vegetarian, vegan, gluten_free, ...
  price_cents        integer not null check (price_cents >= 0),
  currency           char(3) not null,
  photo_url          text,
  prep_time_minutes  integer check (prep_time_minutes > 0),
  is_active          boolean not null default true,
  search_vector      tsvector,
  search_doc         text,
  title_norm         text,                      -- normalised title / local title (for ranking)
  title_local_norm   text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create trigger kitchen_cards_search_fields
  before insert or update on public.kitchen_cards
  for each row execute function public.set_dish_search_fields();

create index kitchen_cards_cook_idx      on public.kitchen_cards (cook_id) where is_active;
create index kitchen_cards_fts_idx       on public.kitchen_cards using gin (search_vector);
create index kitchen_cards_trgm_idx      on public.kitchen_cards using gin (search_doc extensions.gin_trgm_ops);
-- (No index on diet_flags: flags like halal/vegetarian match a large share of rows, and an
--  index there lures the planner away from the selective text indexes.)

-- ---------------------------------------------------------------------------
-- Cooking Now posts: live, time-limited batches
-- ---------------------------------------------------------------------------
create table public.cooking_now_posts (
  id                uuid primary key default gen_random_uuid(),
  cook_id           uuid not null references public.cooks (id) on delete cascade,
  kitchen_card_id   uuid references public.kitchen_cards (id) on delete set null,
  title             text not null check (char_length(title) between 1 and 120),
  title_local       text,
  description       text,
  tags              text[] not null default '{}',
  cuisine           text,
  category          text,
  diet_flags        text[] not null default '{}',
  price_cents       integer not null check (price_cents >= 0),
  currency          char(3) not null,
  photo_url         text,
  portions_total    integer check (portions_total > 0),
  portions_left     integer check (portions_left >= 0),
  ready_at          timestamptz not null default now(),
  available_until   timestamptz not null,
  status            text not null default 'live'
                    check (status in ('live', 'sold_out', 'ended', 'cancelled')),
  search_vector     tsvector,
  search_doc        text,
  title_norm        text,
  title_local_norm  text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (available_until > ready_at - interval '1 day')
);

create trigger cooking_now_posts_search_fields
  before insert or update on public.cooking_now_posts
  for each row execute function public.set_dish_search_fields();

create index cooking_now_posts_live_idx on public.cooking_now_posts (cook_id, available_until) where status = 'live';
create index cooking_now_posts_fts_idx  on public.cooking_now_posts using gin (search_vector);
create index cooking_now_posts_trgm_idx on public.cooking_now_posts using gin (search_doc extensions.gin_trgm_ops);

-- A post is "live" while status = live, it has not expired and it is not sold out.
create or replace function public.is_post_live(p public.cooking_now_posts)
returns boolean
language sql
stable
set search_path = public
as $$
  select p.status = 'live'
     and p.available_until > now()
     and coalesce(p.portions_left, 1) > 0
$$;

-- ---------------------------------------------------------------------------
-- Orders (minimal: needed to gate exact pickup-address disclosure)
-- ---------------------------------------------------------------------------
create table public.orders (
  id                    uuid primary key default gen_random_uuid(),
  buyer_id              uuid not null references auth.users (id) on delete cascade,
  cook_id               uuid not null references public.cooks (id) on delete cascade,
  kitchen_card_id       uuid references public.kitchen_cards (id) on delete set null,
  cooking_now_post_id   uuid references public.cooking_now_posts (id) on delete set null,
  fulfillment           text not null default 'pickup' check (fulfillment in ('pickup', 'delivery')),
  status                text not null default 'pending'
                        check (status in ('pending', 'confirmed', 'ready', 'completed', 'cancelled', 'rejected')),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index orders_buyer_idx on public.orders (buyer_id);
create index orders_cook_idx  on public.orders (cook_id);

-- ---------------------------------------------------------------------------
-- FX rates for "approx. in your currency" and cross-currency price filters/sorting.
-- Refresh from a rates provider on a schedule; seeded with static values.
-- ---------------------------------------------------------------------------
create table public.fx_rates (
  currency      char(3) primary key,
  usd_per_unit  numeric(18, 8) not null check (usd_per_unit > 0),
  updated_at    timestamptz not null default now()
);

create or replace function public.convert_price_cents(amount_cents bigint, from_ccy text, to_ccy text)
returns bigint
language sql
stable
parallel safe
set search_path = public
as $$
  select case
    when upper(from_ccy) = upper(to_ccy) then amount_cents
    else round(amount_cents
               * (select usd_per_unit from public.fx_rates where currency = upper(from_ccy))
               / (select usd_per_unit from public.fx_rates where currency = upper(to_ccy)))::bigint
  end
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
create or replace function public.owns_cook(p_cook_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.cooks c where c.id = p_cook_id and c.user_id = auth.uid())
$$;

alter table public.cooks             enable row level security;
alter table public.cook_locations    enable row level security;
alter table public.kitchen_cards     enable row level security;
alter table public.cooking_now_posts enable row level security;
alter table public.orders            enable row level security;
alter table public.fx_rates          enable row level security;

create policy cooks_public_read  on public.cooks for select using (true);
create policy cooks_owner_insert on public.cooks for insert to authenticated with check (user_id = auth.uid());
create policy cooks_owner_update on public.cooks for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Exact location: owner only. No public policy => anon/other users get zero rows.
create policy cook_locations_owner_all on public.cook_locations for all to authenticated
  using (public.owns_cook(cook_id)) with check (public.owns_cook(cook_id));

create policy kitchen_cards_read  on public.kitchen_cards for select using (is_active or public.owns_cook(cook_id));
create policy kitchen_cards_write on public.kitchen_cards for all to authenticated
  using (public.owns_cook(cook_id)) with check (public.owns_cook(cook_id));

create policy cooking_now_read  on public.cooking_now_posts for select using (true);
create policy cooking_now_write on public.cooking_now_posts for all to authenticated
  using (public.owns_cook(cook_id)) with check (public.owns_cook(cook_id));

create policy orders_party_read   on public.orders for select to authenticated
  using (buyer_id = auth.uid() or public.owns_cook(cook_id));
create policy orders_buyer_insert on public.orders for insert to authenticated
  with check (buyer_id = auth.uid() and status = 'pending');
create policy orders_cook_update  on public.orders for update to authenticated
  using (public.owns_cook(cook_id)) with check (public.owns_cook(cook_id));

create policy fx_rates_public_read on public.fx_rates for select using (true);

-- Clients must never write the derived/fuzzed columns (approx_location, ratings) directly.
-- (A column-level REVOKE does not override a table-level grant, so grant columns explicitly.)
revoke insert, update on public.cooks from anon, authenticated;
grant insert (user_id, display_name, avatar_url, bio, city, country_code, currency,
              accepting_orders, pickup_available, delivery_available, delivery_radius_m)
  on public.cooks to authenticated;
grant update (display_name, avatar_url, bio, city, country_code, currency,
              accepting_orders, pickup_available, delivery_available, delivery_radius_m)
  on public.cooks to authenticated;

-- ---------------------------------------------------------------------------
-- Exact pickup address: revealed only to the buyer of a confirmed order.
-- ---------------------------------------------------------------------------
create or replace function public.get_order_pickup_address(p_order_id uuid)
returns table (address_line text, postal_code text, city text, pickup_instructions text, lat double precision, lng double precision)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select l.address_line, l.postal_code, l.city, l.pickup_instructions,
         st_y(l.location::geometry), st_x(l.location::geometry)
    from public.orders o
    join public.cook_locations l on l.cook_id = o.cook_id
   where o.id = p_order_id
     and (o.buyer_id = auth.uid() or public.owns_cook(o.cook_id))
     and o.status in ('confirmed', 'ready', 'completed')
$$;

revoke all on function public.get_order_pickup_address(uuid) from public, anon;
grant execute on function public.get_order_pickup_address(uuid) to authenticated;
