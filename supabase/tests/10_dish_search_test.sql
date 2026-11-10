-- Tests for "Find a Dish Near Me". Run via scripts/db-test.sh (migrations + seed first).
-- Each block raises an exception (failing the run) when an expectation does not hold.

\echo '  search: biryani within 5 miles in every seed city'
do $$
declare
  c record;
  n int;
  n_live int;
begin
  for c in select * from (values
      ('New York', 40.7549, -73.9840), ('London', 51.5072, -0.1276), ('Toronto', 43.6532, -79.3832),
      ('Dhaka', 23.8103, 90.4125), ('Kolkata', 22.5726, 88.3639), ('Sydney', -33.8688, 151.2093)) v(city, lat, lng)
  loop
    select count(*), count(*) filter (where is_live) into n, n_live
      from search_dishes('biryani', c.lat, c.lng, 8047);
    assert n >= 2, format('%s: expected >= 2 biryani results within 5 mi, got %s', c.city, n);
    assert n_live >= 1, format('%s: expected a live biryani post', c.city);
    assert (select bool_and(distance <= 5.0) from search_dishes('biryani', c.lat, c.lng, 8047)),
      format('%s: result outside radius', c.city);
  end loop;
end $$;

\echo '  search: live posts first, then nearest'
do $$
begin
  -- the first non-live row must come after every live row
  assert not exists (
    with r as (select row_number() over () as pos, is_live from search_dishes('biryani', 40.7549, -73.9840, 8047))
    select 1 from r a join r b on a.pos < b.pos where not a.is_live and b.is_live), 'live rows must be on top';
  -- among non-live rows, distances are non-decreasing
  assert not exists (
    with r as (select row_number() over () as pos, distance_m from search_dishes('biryani', 40.7549, -73.9840, 8047) where not is_live)
    select 1 from r a join r b on b.pos = a.pos + 1 where b.distance_m < a.distance_m), 'nearest sort broken';
end $$;

\echo '  matching: typos, prefixes, synonyms, multilingual'
do $$
declare
  t record;
begin
  for t in select * from (values
      -- query,          lat,      lng,       expected title fragment (case-insensitive)
      ('biriani',        40.7549, -73.9840, 'biryani'),
      ('biriyani',       40.7549, -73.9840, 'biryani'),
      ('briyani',        51.5072,  -0.1276, 'biri'),
      ('biryan',         43.6532, -79.3832, 'biryani'),     -- search-as-you-type prefix
      ('biry',           43.6532, -79.3832, 'biryani'),
      ('BIRYANI!!',      22.5726,  88.3639, 'biryani'),     -- case/punctuation
      ('বিরিয়ানি',        23.8103,  90.4125, 'biri'),        -- Bengali script
      ('बिरयानी',          40.7549, -73.9840, 'biryani'),     -- Hindi script
      ('pilaf',          23.8103,  90.4125, 'polao'),       -- synonym group pulao/polao/pilaf
      ('polao',          40.7549, -73.9840, 'pilaf'),
      ('pulao',          40.7549, -73.9840, 'polo'),
      ('khichdi',        23.8103,  90.4125, 'khichuri'),
      ('chicken curry',  22.5726,  88.3639, 'murgir jhol'),  -- phrase synonym
      ('fish curry',     22.5726,  88.3639, 'macher jhol'),
      ('chiken',         51.5072,  -0.1276, 'chicken'),     -- typo corrected via lexicon
      ('tacos',          40.7549, -73.9840, 'tacos'),
      ('taco',           40.7549, -73.9840, 'tacos'),
      ('dumplings',      -33.8688, 151.2093, 'momo'),
      ('bangladeshi',    40.7549, -73.9840, 'tehari'),      -- cuisine field
      ('mustard oil',    40.7549, -73.9840, 'tehari'),      -- tags field
      ('saffron',        40.7549, -73.9840, 'biryani'),     -- description field
      ('rice',           23.8103,  90.4125, '')             -- category field
    ) v(q, lat, lng, expect)
  loop
    assert exists (
      select 1 from search_dishes(t.q, t.lat, t.lng, 16093, '{}', 'best_match', 1, 50) r
       where t.expect = '' or lower(r.title) like '%' || t.expect || '%'),
      format('query %L: expected a result containing %L', t.q, t.expect);
  end loop;
end $$;

\echo '  matching: no false positives'
do $$
begin
  assert not exists (select 1 from search_dishes('pizza', 40.7549, -73.9840, 16093)), 'pizza should not match';
  assert not exists (select 1 from search_dishes('sushi', 51.5072, -0.1276, 16093)), 'sushi should not match';
  -- "polao" must not drag in unrelated groups via edit distance
  assert not exists (select 1 from search_dishes('polao', 40.7549, -73.9840, 16093) where lower(title) like '%taco%');
  -- multi-word queries AND their terms
  assert not exists (select 1 from search_dishes('chicken biryani', 22.5726, 88.3639, 16093)
                      where lower(title) not like '%biryani%' and lower(title) not like '%biriyani%'
                        and lower(title) not like '%murgir jhol%');
  -- best match puts exact-title hits first
  assert (select lower(title) from search_dishes('chicken biryani', 43.6532, -79.3832, 16093, '{}', 'best_match') r
           where not r.is_live limit 1) = 'chicken biryani';
end $$;

\echo '  filters'
do $$
begin
  -- diet: vegan implies vegetarian; veg filter includes vegan dishes
  assert (select bool_and(diet_flags @> '{vegan}') and count(*) > 0
            from search_dishes('', 40.7549, -73.9840, 16093, '{"diet":["vegan"]}', 'nearest', 1, 50));
  assert exists (select 1 from search_dishes('biryani', 40.7549, -73.9840, 16093, '{"diet":["vegetarian"]}')
                  where title = 'Vegetable Biryani');
  assert (select bool_and(diet_flags @> '{halal}')
            from search_dishes('biryani', 40.7549, -73.9840, 16093, '{"diet":["halal"]}'));
  -- cuisine
  assert (select bool_and(cuisine = 'Mexican') and count(*) > 0
            from search_dishes('', 40.7549, -73.9840, 16093, '{"cuisines":["mexican"]}', 'nearest', 1, 50));
  -- rating
  assert (select bool_and(cook_rating >= 4.8) and count(*) > 0
            from search_dishes('', 40.7549, -73.9840, 16093, '{"min_rating":4.8}', 'nearest', 1, 50));
  -- can deliver to me => inside the cook's delivery radius
  assert (select bool_and(can_deliver) and count(*) > 0
            from search_dishes('', 40.7549, -73.9840, 16093, '{"deliver_to_me":true}', 'nearest', 1, 50));
  -- "Lagos Pot" delivers 10 km but NYC centre is 6 km away: deliverable; Ayesha delivers 5 km, 1.2 km away: deliverable
  assert (select bool_and(not can_deliver) from search_dishes('', 40.7549, -73.9840, 16093) where cook_name = 'Abuela Rosa');
  -- fulfilment
  assert (select bool_and(delivery_available)
            from search_dishes('', 40.7549, -73.9840, 16093, '{"fulfillment":"delivery"}', 'nearest', 1, 50));
  -- available now excludes cooks not accepting orders (Lagos Pot) but keeps live posts
  assert not exists (select 1 from search_dishes('', 40.7549, -73.9840, 16093, '{"available_now":true}', 'nearest', 1, 50)
                      where cook_name = 'Lagos Pot');
  -- price range is in the buyer's currency: USD 10..15
  assert (select bool_and(buyer_price_cents between 1000 and 1500) and count(*) > 0
            from search_dishes('', 40.7549, -73.9840, 16093, '{"price_min":10,"price_max":15,"currency":"USD"}', 'nearest', 1, 50));
  -- types
  assert (select bool_and(is_live) and count(*) > 0
            from search_dishes('', 40.7549, -73.9840, 16093, '{"types":["live"]}'));
end $$;

\echo '  currency conversion + units'
do $$
declare r record;
begin
  select * into r from search_dishes('kacchi', 23.8103, 90.4125, 8047, '{"currency":"GBP","unit":"km"}') limit 1;
  assert r.currency = 'BDT' and r.buyer_currency = 'GBP' and r.buyer_price_cents > 0, 'BDT -> GBP conversion';
  assert r.distance_unit = 'km';
  assert r.distance_m % 100 = 0, 'km distances are rounded to 0.1 km';
  assert r.distance = round(r.distance, 1);
end $$;

\echo '  sorting'
do $$
begin
  assert not exists (
    with r as (select row_number() over () pos, buyer_price_cents p
                 from search_dishes('', 40.7549, -73.9840, 16093, '{}', 'price_asc', 1, 50) where not is_live)
    select 1 from r a join r b on b.pos = a.pos + 1 where b.p < a.p), 'price_asc';
  assert not exists (
    with r as (select row_number() over () pos, cook_rating p
                 from search_dishes('', 40.7549, -73.9840, 16093, '{}', 'rating', 1, 50) where not is_live)
    select 1 from r a join r b on b.pos = a.pos + 1 where b.p > a.p), 'rating';
  assert not exists (
    with r as (select row_number() over () pos, match_score p
                 from search_dishes('biryani', 40.7549, -73.9840, 16093, '{}', 'best_match', 1, 50) where not is_live)
    select 1 from r a join r b on b.pos = a.pos + 1 where b.p > a.p), 'best_match';
  assert not exists (
    with r as (select row_number() over () pos, ready_at p
                 from search_dishes('', 40.7549, -73.9840, 16093, '{}', 'ready_soonest', 1, 50) where is_live)
    select 1 from r a join r b on b.pos = a.pos + 1 where b.p < a.p), 'ready_soonest (live)';
  begin
    perform search_dishes('x', 40.7, -73.9, 1000, '{}', 'drop table cooks');
    raise exception 'invalid sort accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform search_dishes('x', 91, 0, 1000);
    raise exception 'invalid latitude accepted';
  exception when invalid_parameter_value then null;
  end;
end $$;

\echo '  pagination'
do $$
declare total bigint;
begin
  select max(total_count) into total from search_dishes('', 40.7549, -73.9840, 16093, '{}', 'nearest', 1, 5);
  assert total > 10, 'need enough rows to paginate';
  assert (select count(*) from search_dishes('', 40.7549, -73.9840, 16093, '{}', 'nearest', 1, 5)) = 5;
  assert not exists (
    select id from search_dishes('', 40.7549, -73.9840, 16093, '{}', 'nearest', 1, 5)
    intersect
    select id from search_dishes('', 40.7549, -73.9840, 16093, '{}', 'nearest', 2, 5)), 'pages overlap';
  assert (select count(distinct id) from generate_series(1, (total / 5 + 1)::int) p,
            lateral search_dishes('', 40.7549, -73.9840, 16093, '{}', 'nearest', p, 5)) = total, 'pages miss rows';
end $$;

\echo '  empty state: expand radius + similar dishes'
do $$
declare fb jsonb;
begin
  -- Sydney: nearest biryani is ~3.7 mi away, so nothing within 3 mi
  assert not exists (select 1 from search_dishes('biryani', -33.8688, 151.2093, 4828));
  fb := dish_search_fallback('biryani', -33.8688, 151.2093, 4828);
  assert (fb ->> 'nearest_match_m')::int between 5500 and 6200, format('nearest match: %s', fb ->> 'nearest_match_m');
  assert jsonb_array_length(fb -> 'similar') > 0, 'similar dishes nearby';
  -- a dish nobody cooks: no nearest match
  fb := dish_search_fallback('sushi', 40.7549, -73.9840, 8047);
  assert fb ->> 'nearest_match_m' is null;
end $$;

\echo '  suggestions'
do $$
begin
  assert exists (select 1 from search_suggestions('biry') where lower(suggestion) like 'biry%');
  assert exists (select 1 from search_suggestions('kac') where lower(suggestion) like 'kacchi%');
end $$;

\echo '  privacy: exact location never exposed'
do $$
declare
  r record;
  exact extensions.geography;
begin
  -- the public point is 150-500 m from the private point for every cook
  assert (select bool_and(extensions.st_distance(c.approx_location, l.location) between 149 and 501)
            from cooks c join cook_locations l on l.cook_id = c.id), 'approx point offset';
  -- search returns the fuzzed point, never the exact one
  for r in select * from search_dishes('', 40.7549, -73.9840, 16093, '{}', 'nearest', 1, 50) loop
    select location into exact from cook_locations where cook_id = r.cook_id;
    assert extensions.st_distance(exact, extensions.st_setsrid(extensions.st_makepoint(r.approx_lng, r.approx_lat), 4326)::extensions.geography) > 149;
    -- distances are quantised to 0.1 mi (160.9 m)
    assert abs(r.distance_m - round(r.distance_m / 160.9344) * 160.9344) <= 1, format('distance not rounded: %s', r.distance_m);
  end loop;
end $$;

-- RLS checks run as the anon / authenticated roles.
set role anon;
do $$
begin
  assert (select count(*) from cook_locations) = 0, 'anon can read cook_locations!';
  assert (select count(*) from cooks) > 0, 'anon should read public cook profiles';
  assert (select count(*) from search_dishes('biryani', 40.7549, -73.9840, 8047)) > 0, 'anon can search';
  begin
    perform * from search_dishes_core('', 0, 0, 1000, '{}', 'nearest', 1, 0, true);
    raise exception 'anon can call search_dishes_core';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from get_order_pickup_address(gen_random_uuid());
    raise exception 'anon can call get_order_pickup_address';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

\echo '  privacy: pickup address only after order confirmation'
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000b001', 'buyer@example.com'),
  ('00000000-0000-0000-0000-00000000b002', 'other@example.com');
insert into orders (id, buyer_id, cook_id, status) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000b001', md5('cook:nyc:1')::uuid, 'pending');
set role authenticated;
do $$
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000b001', false);
  assert (select count(*) from cook_locations) = 0, 'buyer can read cook_locations!';
  assert not exists (select 1 from get_order_pickup_address('00000000-0000-0000-0000-0000000000a1')), 'pending order reveals address';
end $$;
reset role;
update orders set status = 'confirmed' where id = '00000000-0000-0000-0000-0000000000a1';
set role authenticated;
do $$
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000b001', false);
  assert (select address_line from get_order_pickup_address('00000000-0000-0000-0000-0000000000a1')) = '1 Demo Street',
    'confirmed order must reveal address to the buyer';
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000b002', false);
  assert not exists (select 1 from get_order_pickup_address('00000000-0000-0000-0000-0000000000a1')), 'other user sees address';
  -- clients cannot write the fuzzed point
  begin
    update cooks set approx_location = null;
    raise exception 'client could write approx_location';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

\echo '  saved searches + alerts'
set role authenticated;
do $$
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000b001', false);
  perform create_saved_search('biryani', 40.7549, -73.9840, 8047, 'mi', 'Midtown, New York');
  perform create_saved_search('biryani', 40.7549, -73.9840, 8047, 'mi', 'Midtown (vegan only)', '{"diet":["vegan"]}');
  assert (select count(*) from saved_searches) = 2;
  assert (select count(*) from list_saved_searches() where abs(lat - 40.7549) < 1e-6 and abs(lng + 73.9840) < 1e-6) = 2,
    'list_saved_searches returns plain coordinates';
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000b002', false);
  assert (select count(*) from saved_searches) = 0, 'saved searches leak between users';
  assert (select count(*) from list_saved_searches()) = 0, 'list_saved_searches leaks between users';
end $$;
reset role;
do $$
declare n int;
begin
  -- matching live post 2.2 mi away (typo'd title still matches)
  insert into cooking_now_posts (cook_id, title, cuisine, tags, price_cents, currency, available_until)
  values (md5('cook:nyc:2')::uuid, 'Biriyani tonight', 'Bangladeshi', '{rice}', 1500, 'USD', now() + interval '3 hours');
  -- non-matching dish nearby
  insert into cooking_now_posts (cook_id, title, price_cents, currency, available_until)
  values (md5('cook:nyc:3')::uuid, 'Pizza night', 1200, 'USD', now() + interval '3 hours');
  -- matching dish outside the circle (8.7 mi)
  insert into kitchen_cards (cook_id, title, price_cents, currency)
  values (md5('cook:nyc:9')::uuid, 'Chicken Biryani', 1600, 'USD');
  -- matching dish in another city
  insert into cooking_now_posts (cook_id, title, price_cents, currency, available_until)
  values (md5('cook:lon:1')::uuid, 'Biryani', 1000, 'GBP', now() + interval '3 hours');
  -- vegan biryani nearby: matches BOTH saved searches
  insert into kitchen_cards (cook_id, title, price_cents, currency, diet_flags)
  values (md5('cook:nyc:7')::uuid, 'Jackfruit Biryani', 1400, 'USD', '{vegan}');

  select count(*) into n from saved_search_alerts;
  assert n = 3, format('expected 3 alerts, got %s', n);
  assert (select count(*) from saved_search_alerts where title = 'Biriyani tonight') = 1;
  assert (select count(*) from saved_search_alerts where title = 'Jackfruit Biryani') = 2;
  assert (select bool_and(distance_m between 3000 and 7000) from saved_search_alerts);

  -- re-activating does not duplicate
  update kitchen_cards set is_active = false where title = 'Jackfruit Biryani';
  update kitchen_cards set is_active = true  where title = 'Jackfruit Biryani';
  assert (select count(*) from saved_search_alerts) = 3, 'duplicate alerts';

  -- dispatcher claims each alert once
  assert (select count(*) from claim_saved_search_alerts(50) where email = 'buyer@example.com') = 3;
  assert (select count(*) from claim_saved_search_alerts(50)) = 0, 'claimed twice';
  perform complete_saved_search_alert(id) from saved_search_alerts;
  assert (select bool_and(sent_at is not null) from saved_search_alerts);
end $$;

set role anon;
do $$
begin
  begin
    perform * from claim_saved_search_alerts(10);
    raise exception 'anon can claim alerts';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
