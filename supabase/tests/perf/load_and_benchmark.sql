-- Optional load test (NOT run by db-test.sh): 50k cooks / 250k Kitchen Cards / 5k live
-- posts scattered over a ~50 km radius around New York, then times typical searches.
--   psql -d shareyourpot_test -f supabase/tests/perf/load_and_benchmark.sql
\timing off
set client_min_messages = warning;
alter table kitchen_cards disable trigger kitchen_cards_alerts;
alter table cooking_now_posts disable trigger cooking_now_posts_alerts;

insert into cooks (id, display_name, currency, rating_avg, rating_count, delivery_available, delivery_radius_m)
select md5('perf:' || g)::uuid, 'Perf Cook ' || g, 'USD', round((3 + random() * 2)::numeric, 2), (random() * 300)::int,
       random() < 0.5, (random() * 10000)::int
  from generate_series(1, 50000) g;

insert into cook_locations (cook_id, location)
select md5('perf:' || g)::uuid,
       extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(-73.9840, 40.7549), 4326)::extensions.geography,
                             sqrt(random()) * 50000, radians(random() * 360))
  from generate_series(1, 50000) g;

with dishes(title, cuisine, tags) as (values
  ('Chicken Biryani', 'Indian', '{rice,chicken}'), ('Beef Tacos', 'Mexican', '{beef}'), ('Pad Thai', 'Thai', '{noodles}'),
  ('Chicken Curry', 'Indian', '{chicken}'), ('Lasagna', 'Italian', '{pasta}'), ('Jollof Rice', 'Nigerian', '{rice}'),
  ('Pierogi', 'Polish', '{dumplings}'), ('Pho Bo', 'Vietnamese', '{soup}'), ('Falafel Wrap', 'Lebanese', '{chickpea}'),
  ('Kimchi Jjigae', 'Korean', '{stew}'), ('Mutton Pulao', 'Pakistani', '{rice}'), ('Fish Tacos', 'Mexican', '{fish}'),
  ('Veg Momo', 'Nepali', '{dumplings}'), ('Ramen', 'Japanese', '{noodles}'), ('Shepherd''s Pie', 'British', '{lamb}'),
  ('Kacchi Biriyani', 'Bangladeshi', '{mutton,rice}'), ('Moussaka', 'Greek', '{eggplant}'), ('Doro Wat', 'Ethiopian', '{stew}'),
  ('Chicken Adobo', 'Filipino', '{chicken}'), ('Butter Chicken', 'Indian', '{chicken}')),
numbered as (select row_number() over () - 1 as i, * from dishes)
insert into kitchen_cards (cook_id, title, description, cuisine, category, tags, diet_flags, price_cents, currency, prep_time_minutes)
select md5('perf:' || g)::uuid, d.title || ' #' || k, 'Home-made ' || lower(d.title) || ', family recipe.', d.cuisine, 'Main',
       d.tags::text[], case when random() < 0.2 then '{vegetarian}'::text[] else '{halal}'::text[] end,
       (800 + random() * 2000)::int, 'USD', 30 + (random() * 90)::int
  from generate_series(1, 50000) g
  cross join generate_series(1, 5) k
  join numbered d on d.i = ((hashtext(g::text || ':' || k) & 2147483647) % 20);

insert into cooking_now_posts (cook_id, title, cuisine, tags, price_cents, currency, available_until, ready_at)
select md5('perf:' || g)::uuid, (array['Biryani live batch','Tacos now','Curry pot','Dumplings steaming'])[1 + g % 4],
       'Mixed', '{}', 1200, 'USD', now() + interval '6 hours', now() + make_interval(mins => g % 60)
  from generate_series(1, 50000, 10) g;

alter table kitchen_cards enable trigger kitchen_cards_alerts;
alter table cooking_now_posts enable trigger cooking_now_posts_alerts;
analyze;

select (select count(*) from cooks) cooks, (select count(*) from kitchen_cards) cards, (select count(*) from cooking_now_posts) posts;

-- Warm-up, then time each query 5x and report the median.
create temp table bench (label text, q text, r int, f jsonb, s text);
insert into bench values
  ('biryani within 5 mi',          'biryani',        8047,  '{}',                       'nearest'),
  ('biriani (typo) within 5 mi',   'biriani',        8047,  '{}',                       'nearest'),
  ('chiken curry within 10 mi',    'chiken curry',   16093, '{}',                       'best_match'),
  ('tacos 3 mi, deliver to me',    'tacos',          4828,  '{"deliver_to_me":true}',   'nearest'),
  ('browse (empty q) 3 mi',        '',               4828,  '{}',                       'nearest'),
  ('biryani 25 mi, price sort',    'biryani',        40234, '{}',                       'price_asc'),
  ('biryani 50 mi, halal, rating', 'biryani',        80467, '{"diet":["halal"]}',       'rating');

do $$
declare b record; t0 timestamptz; ms numeric[]; n bigint;
begin
  for b in select * from bench loop
    perform * from search_dishes(b.q, 40.7549, -73.9840, b.r, b.f, b.s, 1, 20);
    ms := '{}';
    for i in 1..5 loop
      t0 := clock_timestamp();
      select max(total_count) into n from search_dishes(b.q, 40.7549, -73.9840, b.r, b.f, b.s, 1, 20);
      ms := ms || extract(epoch from clock_timestamp() - t0) * 1000;
    end loop;
    raise warning '%  matches=%  median=% ms', rpad(b.label, 32), lpad(coalesce(n, 0)::text, 6),
      round((select percentile_cont(0.5) within group (order by x) from unnest(ms) x)::numeric, 1);
  end loop;
end $$;
