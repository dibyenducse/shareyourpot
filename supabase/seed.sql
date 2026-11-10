-- Seed data for "Find a Dish Near Me".
-- Six cities; in every one, "biryani within 5 miles" of the city centre returns real
-- results (with varied spellings: biryani / biriyani / biriani / briyani / বিরিয়ানি),
-- and there is always another biryani between 5 and 15 miles so that the
-- "Expand to 10 mi?" flow can be tried.
--
-- City centres (use these to try it out):
--   New York  40.7549, -73.9840     London   51.5072, -0.1276    Toronto 43.6532, -79.3832
--   Dhaka     23.8103,  90.4125     Kolkata  22.5726, 88.3639    Sydney -33.8688, 151.2093
--
-- Cooking Now posts are live for 12 hours from when the seed runs. To revive them:
--   update cooking_now_posts set status = 'live', available_until = now() + interval '12 hours';

begin;

-- ---------------------------------------------------------------------------
-- FX rates (USD per unit). Static demo values: refresh from a provider in production.
-- ---------------------------------------------------------------------------
insert into public.fx_rates (currency, usd_per_unit) values
  ('USD', 1), ('GBP', 1.27), ('EUR', 1.08), ('CAD', 0.73), ('AUD', 0.66),
  ('BDT', 0.0083), ('INR', 0.012), ('PKR', 0.0036), ('AED', 0.2723), ('MXN', 0.055), ('NGN', 0.00065)
on conflict (currency) do update set usd_per_unit = excluded.usd_per_unit, updated_at = now();

-- ---------------------------------------------------------------------------
-- Synonyms: multilingual names + common misspellings. Groups are matched as a whole,
-- so searching any term finds dishes named with any other term in the group.
-- ---------------------------------------------------------------------------
insert into public.dish_synonyms (group_key, term, lang) values
  ('biryani', 'biryani', 'en'), ('biryani', 'biriyani', 'en'), ('biryani', 'biriani', 'en'),
  ('biryani', 'briyani', 'en'), ('biryani', 'beryani', 'en'), ('biryani', 'buriyani', 'en'),
  ('biryani', 'বিরিয়ানি', 'bn'), ('biryani', 'बिरयानी', 'hi'), ('biryani', 'بریانی', 'ur'), ('biryani', 'برياني', 'ar'),
  ('pulao', 'pulao', 'en'), ('pulao', 'polao', 'bn'), ('pulao', 'pilaf', 'en'), ('pulao', 'pilau', 'en'),
  ('pulao', 'pilav', 'tr'), ('pulao', 'plov', 'ru'), ('pulao', 'palaw', 'ps'), ('pulao', 'polo', 'fa'),
  ('pulao', 'pulav', 'hi'), ('pulao', 'পোলাও', 'bn'), ('pulao', 'पुलाव', 'hi'), ('pulao', 'پلو', 'fa'),
  ('khichdi', 'khichdi', 'hi'), ('khichdi', 'khichuri', 'bn'), ('khichdi', 'kitchari', 'en'),
  ('khichdi', 'khichri', 'en'), ('khichdi', 'খিচুড়ি', 'bn'), ('khichdi', 'खिचड़ी', 'hi'),
  ('tehari', 'tehari', 'bn'), ('tehari', 'tahari', 'hi'), ('tehari', 'tehri', 'hi'), ('tehari', 'তেহারি', 'bn'),
  ('taco', 'taco', 'es'), ('taco', 'tacos', 'es'),
  ('chicken_curry', 'chicken curry', 'en'), ('chicken_curry', 'murgir jhol', 'bn'),
  ('chicken_curry', 'murgi jhol', 'bn'), ('chicken_curry', 'মুরগির ঝোল', 'bn'),
  ('chicken_curry', 'murgh curry', 'hi'), ('chicken_curry', 'chicken salan', 'ur'),
  ('fish_curry', 'fish curry', 'en'), ('fish_curry', 'macher jhol', 'bn'), ('fish_curry', 'maacher jhol', 'bn'),
  ('fish_curry', 'machher jhol', 'bn'), ('fish_curry', 'মাছের ঝোল', 'bn'),
  ('dumpling', 'dumpling', 'en'), ('dumpling', 'momo', 'ne'), ('dumpling', 'gyoza', 'ja'),
  ('dumpling', 'jiaozi', 'zh'), ('dumpling', 'mandu', 'ko'), ('dumpling', 'pierogi', 'pl'),
  ('kebab', 'kebab', 'en'), ('kebab', 'kabab', 'en'), ('kebab', 'kabob', 'en'), ('kebab', 'kebap', 'tr'), ('kebab', 'কাবাব', 'bn'),
  ('shawarma', 'shawarma', 'ar'), ('shawarma', 'shawerma', 'ar'), ('shawarma', 'shwarma', 'en'),
  ('paratha', 'paratha', 'hi'), ('paratha', 'porota', 'bn'), ('paratha', 'parotta', 'ta'), ('paratha', 'পরোটা', 'bn'),
  ('fuchka', 'fuchka', 'bn'), ('fuchka', 'phuchka', 'bn'), ('fuchka', 'pani puri', 'hi'),
  ('fuchka', 'golgappa', 'hi'), ('fuchka', 'ফুচকা', 'bn'),
  ('rosogolla', 'rosogolla', 'bn'), ('rosogolla', 'rasgulla', 'hi'), ('rosogolla', 'rasagola', 'or'), ('rosogolla', 'রসগোল্লা', 'bn'),
  ('dosa', 'dosa', 'ta'), ('dosa', 'dosai', 'ta'), ('dosa', 'thosai', 'ms'),
  ('falafel', 'falafel', 'ar'), ('falafel', 'felafel', 'en'), ('falafel', 'taamiya', 'ar'),
  ('vegetable', 'vegetable', 'en'), ('vegetable', 'veg', 'en'), ('vegetable', 'veggie', 'en'),
  ('vegetable', 'sabzi', 'hi'), ('vegetable', 'sabji', 'bn'),
  ('chicken', 'chicken', 'en'), ('chicken', 'murgh', 'hi'), ('chicken', 'murgi', 'bn'),
  ('chicken', 'morog', 'bn'), ('chicken', 'মুরগি', 'bn'),
  ('mutton', 'mutton', 'en'), ('mutton', 'goat', 'en'), ('mutton', 'khasi', 'bn'), ('mutton', 'খাসি', 'bn'),
  ('mutton', 'মাটন', 'bn'),
  ('pho', 'pho', 'vi'), ('pho', 'phở', 'vi')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Cities
-- ---------------------------------------------------------------------------
create temp table seed_cities (code text primary key, city text, country char(2), currency char(3), lat float8, lng float8) on commit drop;
insert into seed_cities values
  ('nyc', 'New York', 'US', 'USD',  40.7549,  -73.9840),
  ('lon', 'London',   'GB', 'GBP',  51.5072,   -0.1276),
  ('tor', 'Toronto',  'CA', 'CAD',  43.6532,  -79.3832),
  ('dha', 'Dhaka',    'BD', 'BDT',  23.8103,   90.4125),
  ('kol', 'Kolkata',  'IN', 'INR',  22.5726,   88.3639),
  ('syd', 'Sydney',   'AU', 'AUD', -33.8688,  151.2093);

-- ---------------------------------------------------------------------------
-- Cooks: placed by (distance km, bearing degrees) from the city centre.
-- ---------------------------------------------------------------------------
create temp table seed_cooks (
  city text, n int, name text, km float8, bearing float8, rating numeric, ratings int,
  delivery boolean, delivery_km float8, accepting boolean default true
) on commit drop;
insert into seed_cooks values
  -- New York (1 mi = 1.609 km)
  ('nyc', 1, 'Ayesha''s Kitchen',        1.2,   0, 4.8, 212, true,  5,   true),
  ('nyc', 2, 'Rahman Home Foods',        3.5,  80, 4.9, 341, true,  8,   true),
  ('nyc', 3, 'Abuela Rosa',              2.0, 180, 4.7, 158, false, 0,   true),
  ('nyc', 4, 'Nonna Lucia',              0.8, 270, 4.6,  97, true,  3,   true),
  ('nyc', 5, 'Seoul Mama',               4.5,  45, 4.5,  64, false, 0,   true),
  ('nyc', 6, 'Lagos Pot',                6.0, 135, 4.4,  51, true,  10,  false),
  ('nyc', 7, 'Green Leaf Biryani',       6.5,   5, 4.3,  38, false, 0,   true),
  ('nyc', 8, 'Persian Table',            3.0, 260, 4.7,  88, true,  4,   true),
  ('nyc', 9, 'Queens Biryani Corner',   14.0,  90, 4.6, 120, true,  6,   true),
  -- London
  ('lon', 1, 'Brick Lane Biriani Co',    4.0,  75, 4.7, 280, true,  6,   true),
  ('lon', 2, 'Sylheti Kitchen',          5.5,  95, 4.9, 175, true,  9,   true),
  ('lon', 3, 'Caribbean Corner',         3.0, 170, 4.6, 132, false, 0,   true),
  ('lon', 4, 'Nan''s Roast',             1.5,   0, 4.5,  70, true,  3,   true),
  ('lon', 5, 'Polski Dom',               7.0, 270, 4.4,  45, false, 0,   true),
  ('lon', 6, 'Istanbul Ev',              2.5,  40, 4.8, 110, true,  5,   true),
  ('lon', 7, 'Pho Hanoi Home',           2.0, 220, 4.6,  83, false, 0,   true),
  ('lon', 8, 'Taqueria en Casa',        10.0,   0, 4.3,  29, false, 0,   true),
  ('lon', 9, 'Hyderabad Nights',        13.0, 280, 4.8, 140, true,  5,   true),
  -- Toronto
  ('tor', 1, 'Mumbai Masala Home',       2.0,   0, 4.7, 160, true,  5,   true),
  ('tor', 2, 'Karachi Kitchen',          5.0,  85, 4.8, 220, true,  8,   true),
  ('tor', 3, 'Tia Maria',                1.0, 270, 4.6,  75, false, 0,   true),
  ('tor', 4, 'Lola''s Adobo',            3.5, 315, 4.7,  90, true,  4,   true),
  ('tor', 5, 'Trini Doubles',            6.5,  45, 4.5,  60, false, 0,   true),
  ('tor', 6, 'Mesob Ethiopian Home',     2.5, 200, 4.8,  99, true,  6,   true),
  ('tor', 7, 'Tehran Home',              7.0,   0, 4.4,  40, false, 0,   true),
  ('tor', 8, 'Biryani Bros',            15.0,  10, 4.6, 130, true,  7,   true),
  -- Dhaka
  ('dha', 1, 'Puran Dhaka Kacchi',       2.0, 180, 4.9, 512, true,  4,   true),
  ('dha', 2, 'Ammu''s Rannaghor',        1.0,   0, 4.8, 260, true,  3,   true),
  ('dha', 3, 'Khichuri Ghor',            3.5,  90, 4.6, 140, false, 0,   true),
  ('dha', 4, 'Tehari Bari',              5.0, 270, 4.7, 190, true,  6,   true),
  ('dha', 5, 'Pitha Ghor',               2.8,  45, 4.5,  80, false, 0,   true),
  ('dha', 6, 'Chotpoti Corner',          1.5, 225, 4.4,  66, false, 0,   true),
  ('dha', 7, 'Sylhet Biriyani House',    6.5,   0, 4.6, 120, true,  5,   true),
  ('dha', 8, 'Chattogram Mezban',        9.0,  10, 4.7, 101, true,  8,   true),
  ('dha', 9, 'Mughlai Darbar',          14.0, 330, 4.5,  70, false, 0,   true),
  -- Kolkata
  ('kol', 1, 'Kolkata Biryani Ghar',     1.5,   0, 4.8, 430, true,  4,   true),
  ('kol', 2, 'Bouma''s Kitchen',         2.5, 180, 4.9, 200, false, 0,   true),
  ('kol', 3, 'Maacher Jhol Home',        3.0,  90, 4.7, 150, true,  5,   true),
  ('kol', 4, 'Tangra Home Kitchen',      6.0,  80, 4.5,  95, true,  7,   true),
  ('kol', 5, 'Mishti Mukh',              1.0, 270, 4.6, 180, false, 0,   true),
  ('kol', 6, 'Kathi Roll Co',            0.7, 135, 4.4, 140, true,  2,   true),
  ('kol', 7, 'Awadhi Handi',             5.5,  10, 4.7, 165, true,  6,   true),
  ('kol', 8, 'Basanti Pulao House',      4.0, 300, 4.6,  77, false, 0,   true),
  ('kol', 9, 'Salt Lake Biriyani',      10.0,  70, 4.5,  85, true,  5,   true),
  -- Sydney
  ('syd', 1, 'Lakemba Biryani Spot',     7.5, 235, 4.8, 260, true,  9,   true),
  ('syd', 2, 'Harris Park Dosa',         6.0, 280, 4.6, 140, false, 0,   true),
  ('syd', 3, 'Thai Mum''s Kitchen',      1.5, 180, 4.7, 120, true,  4,   true),
  ('syd', 4, 'Yiayia''s Table',          3.0, 225, 4.8,  98, false, 0,   true),
  ('syd', 5, 'Lebanese Home',            4.0,   0, 4.6, 110, true,  6,   true),
  ('syd', 6, 'Taco Tuesday Home',        2.0,  90, 4.4,  57, false, 0,   true),
  ('syd', 7, 'Dumpling Lady',            1.0, 270, 4.9, 300, true,  3,   true),
  ('syd', 8, 'Parramatta Biryani House',20.0, 280, 4.5,  90, true,  6,   true);

insert into public.cooks (id, display_name, city, country_code, currency, rating_avg, rating_count,
                          accepting_orders, pickup_available, delivery_available, delivery_radius_m, bio)
select md5('cook:' || s.city || ':' || s.n)::uuid, s.name, c.city, c.country, c.currency, s.rating, s.ratings,
       s.accepting, true, s.delivery, (s.delivery_km * 1000)::int,
       'Home cook in ' || c.city || '.'
  from seed_cooks s join seed_cities c on c.code = s.city
on conflict (id) do nothing;

-- Exact (private) points. The trigger derives the fuzzed public point.
insert into public.cook_locations (cook_id, location, address_line, city, country_code, pickup_instructions)
select md5('cook:' || s.city || ':' || s.n)::uuid,
       extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(c.lng, c.lat), 4326)::extensions.geography,
                             s.km * 1000, radians(s.bearing)),
       s.n || ' Demo Street', c.city, c.country, 'Ring the bell; pickup at the side door.'
  from seed_cooks s join seed_cities c on c.code = s.city
on conflict (cook_id) do nothing;

-- ---------------------------------------------------------------------------
-- Kitchen Cards
-- ---------------------------------------------------------------------------
create temp table seed_cards (
  city text, n int, title text, title_local text, cuisine text, category text,
  tags text[], diet text[], price numeric, prep int, description text
) on commit drop;
insert into seed_cards values
  -- New York
  ('nyc', 1, 'Hyderabadi Dum Biryani', 'हैदराबादी दम बिरयानी', 'Indian', 'Rice', '{rice,spicy,dum}', '{halal}', 16, 60, 'Basmati layered with marinated chicken, saffron and fried onions, sealed and slow-cooked.'),
  ('nyc', 1, 'Chicken 65', null, 'Indian', 'Appetizer', '{fried,spicy}', '{halal}', 11, 30, 'Crisp, curry-leaf fried chicken bites.'),
  ('nyc', 1, 'Mirchi ka Salan', null, 'Indian', 'Curry', '{chili,peanut}', '{vegetarian,vegan}', 8, 40, 'Tangy chili and peanut curry, the classic biryani side.'),
  ('nyc', 2, 'Kacchi Biriyani', 'কাচ্চি বিরিয়ানি', 'Bangladeshi', 'Rice', '{mutton,rice,dhaka}', '{halal}', 18, 120, 'Old-Dhaka style: raw marinated mutton and potato cooked with aromatic rice.'),
  ('nyc', 2, 'Beef Tehari', 'গরুর তেহারি', 'Bangladeshi', 'Rice', '{beef,rice,mustard oil}', '{halal}', 15, 90, 'Beef and rice cooked in mustard oil with green chilies.'),
  ('nyc', 2, 'Mishti Doi', 'মিষ্টি দই', 'Bangladeshi', 'Dessert', '{yogurt,sweet}', '{vegetarian}', 5, 20, 'Caramelised sweet yogurt set in clay pots.'),
  ('nyc', 3, 'Tacos al Pastor', null, 'Mexican', 'Tacos', '{pork,pineapple,corn tortilla}', '{}', 12, 25, 'Achiote-marinated pork with pineapple on corn tortillas.'),
  ('nyc', 3, 'Chicken Tinga Tacos', null, 'Mexican', 'Tacos', '{chicken,chipotle}', '{gluten_free}', 11, 25, 'Smoky chipotle shredded chicken tacos.'),
  ('nyc', 3, 'Pork Tamales', null, 'Mexican', 'Main', '{corn,masa}', '{gluten_free}', 14, 90, 'Half dozen red-chile pork tamales.'),
  ('nyc', 4, 'Nonna''s Lasagna', null, 'Italian', 'Pasta', '{beef,bechamel}', '{}', 17, 75, 'Seven layers, ragù and béchamel.'),
  ('nyc', 4, 'Eggplant Parmigiana', null, 'Italian', 'Main', '{eggplant,cheese}', '{vegetarian}', 14, 60, 'Fried eggplant baked with tomato and mozzarella.'),
  ('nyc', 5, 'Kimchi Jjigae', '김치찌개', 'Korean', 'Stew', '{kimchi,pork,tofu}', '{}', 13, 40, 'Aged kimchi stew with pork belly and tofu.'),
  ('nyc', 5, 'Vegetable Bibimbap', '비빔밥', 'Korean', 'Rice', '{rice,gochujang}', '{vegetarian}', 12, 30, 'Rice bowl with seasoned vegetables and gochujang.'),
  ('nyc', 6, 'Party Jollof Rice', null, 'Nigerian', 'Rice', '{rice,tomato,smoky}', '{vegan,gluten_free}', 13, 60, 'Smoky party-style jollof.'),
  ('nyc', 6, 'Egusi Soup', null, 'Nigerian', 'Soup', '{melon seed,spinach}', '{gluten_free}', 15, 75, 'Ground melon seed soup with greens and assorted meat.'),
  ('nyc', 7, 'Vegetable Biryani', 'सब्ज़ी बिरयानी', 'Indian', 'Rice', '{rice,vegetables}', '{vegan}', 13, 45, 'Seasonal vegetables and basmati, no ghee.'),
  ('nyc', 7, 'Chana Masala', null, 'Indian', 'Curry', '{chickpea}', '{vegan,gluten_free}', 10, 30, 'Punjabi chickpea curry.'),
  ('nyc', 8, 'Zereshk Polo with Chicken', 'زرشک پلو', 'Persian', 'Rice', '{barberry,saffron,rice}', '{halal}', 17, 60, 'Saffron rice with barberries and braised chicken.'),
  ('nyc', 8, 'Lamb Pilaf', null, 'Persian', 'Rice', '{lamb,rice}', '{halal}', 18, 75, 'Fragrant rice pilaf with tender lamb.'),
  ('nyc', 9, 'Mutton Biryani', null, 'Pakistani', 'Rice', '{mutton,rice,spicy}', '{halal}', 17, 90, 'Karachi-style spicy mutton biryani.'),
  -- London
  ('lon', 1, 'Lamb Biriani', null, 'Bangladeshi', 'Rice', '{lamb,rice}', '{halal}', 11, 60, 'Brick Lane classic lamb biriani with vegetable curry on the side.'),
  ('lon', 1, 'Chicken Tikka Masala', null, 'British Indian', 'Curry', '{chicken,creamy}', '{halal,gluten_free}', 10, 45, 'The national favourite.'),
  ('lon', 2, 'Chicken Biriyani', 'মুরগির বিরিয়ানি', 'Bangladeshi', 'Rice', '{chicken,rice}', '{halal}', 10, 60, 'Sylheti home-style chicken biriyani.'),
  ('lon', 2, 'Shatkora Beef Curry', null, 'Bangladeshi', 'Curry', '{beef,citrus}', '{halal,gluten_free}', 12, 90, 'Beef slow-cooked with Sylheti shatkora citrus.'),
  ('lon', 3, 'Jerk Chicken', null, 'Caribbean', 'Main', '{chicken,spicy,grill}', '{gluten_free}', 11, 60, 'Scotch bonnet and allspice marinated chicken.'),
  ('lon', 3, 'Curry Goat with Rice and Peas', null, 'Caribbean', 'Curry', '{goat,rice}', '{gluten_free}', 13, 120, 'Jamaican curry goat.'),
  ('lon', 4, 'Sunday Roast Beef', null, 'British', 'Main', '{beef,yorkshire pudding}', '{}', 16, 120, 'Roast beef, Yorkshire puddings and all the trimmings.'),
  ('lon', 4, 'Shepherd''s Pie', null, 'British', 'Main', '{lamb,potato}', '{gluten_free}', 12, 60, 'Minced lamb under buttery mash.'),
  ('lon', 5, 'Ruskie Pierogi', null, 'Polish', 'Dumplings', '{potato,cheese}', '{vegetarian}', 9, 45, 'Potato and twaróg dumplings with fried onion.'),
  ('lon', 5, 'Bigos', null, 'Polish', 'Stew', '{cabbage,sausage}', '{gluten_free}', 11, 120, 'Hunter''s stew.'),
  ('lon', 6, 'Lamb Pilav', null, 'Turkish', 'Rice', '{lamb,rice,bulgur}', '{halal}', 12, 60, 'Buttery Turkish rice pilav with lamb.'),
  ('lon', 6, 'Red Lentil Soup', null, 'Turkish', 'Soup', '{lentil,mercimek}', '{vegan,gluten_free}', 6, 30, 'Mercimek çorbası with lemon.'),
  ('lon', 7, 'Pho Bo', 'Phở bò', 'Vietnamese', 'Soup', '{beef,noodles}', '{gluten_free}', 11, 240, 'Twelve-hour beef broth with rice noodles.'),
  ('lon', 7, 'Vegan Summer Rolls', null, 'Vietnamese', 'Appetizer', '{rice paper,tofu}', '{vegan,gluten_free}', 7, 20, 'Fresh rolls with peanut dip.'),
  ('lon', 8, 'Fish Tacos', null, 'Mexican', 'Tacos', '{fish,slaw}', '{}', 10, 30, 'Beer-battered fish, chipotle mayo.'),
  ('lon', 9, 'Hyderabadi Chicken Biryani', null, 'Indian', 'Rice', '{chicken,rice,dum}', '{halal}', 13, 75, 'Kacchi-style Hyderabadi dum biryani.'),
  -- Toronto
  ('tor', 1, 'Veg Biryani', null, 'Indian', 'Rice', '{rice,vegetables,paneer}', '{vegetarian}', 15, 45, 'Mixed vegetable and paneer biryani.'),
  ('tor', 1, 'Pav Bhaji', null, 'Indian', 'Street Food', '{butter,bun}', '{vegetarian}', 12, 30, 'Mumbai street-style mashed vegetable curry with buttered buns.'),
  ('tor', 2, 'Chicken Biryani', 'چکن بریانی', 'Pakistani', 'Rice', '{chicken,rice,spicy}', '{halal}', 17, 60, 'Sindhi-style chicken biryani with plums and potatoes.'),
  ('tor', 2, 'Beef Nihari', null, 'Pakistani', 'Curry', '{beef,slow cooked}', '{halal}', 19, 480, 'Overnight slow-cooked beef shank stew.'),
  ('tor', 3, 'Beef Tacos', null, 'Mexican', 'Tacos', '{beef,corn tortilla}', '{gluten_free}', 13, 25, 'Carne asada tacos.'),
  ('tor', 3, 'Pupusas Revueltas', null, 'Salvadoran', 'Main', '{corn,cheese,pork}', '{gluten_free}', 12, 40, 'Stuffed corn cakes with curtido.'),
  ('tor', 4, 'Chicken Adobo', null, 'Filipino', 'Main', '{chicken,soy,vinegar}', '{}', 15, 60, 'Braised in vinegar, soy and garlic.'),
  ('tor', 4, 'Pancit Bihon', null, 'Filipino', 'Noodles', '{rice noodles}', '{}', 13, 40, 'Stir-fried rice noodles.'),
  ('tor', 5, 'Doubles', null, 'Trinidadian', 'Street Food', '{chickpea,bara}', '{vegan}', 6, 20, 'Curried channa in fried bara.'),
  ('tor', 5, 'Chicken Roti', null, 'Trinidadian', 'Main', '{chicken,curry,roti}', '{halal}', 14, 45, 'Dhalpuri roti wrapped round curry chicken.'),
  ('tor', 6, 'Doro Wat', null, 'Ethiopian', 'Stew', '{chicken,berbere,egg}', '{gluten_free}', 18, 120, 'Berbere chicken stew with injera.'),
  ('tor', 6, 'Misir Wat', null, 'Ethiopian', 'Stew', '{lentil,berbere}', '{vegan,gluten_free}', 14, 60, 'Spicy red lentil stew with injera.'),
  ('tor', 7, 'Sabzi Polo with Fish', 'سبزی پلو', 'Persian', 'Rice', '{herbs,fish,rice}', '{halal}', 20, 60, 'Herbed rice with fried fish.'),
  ('tor', 8, 'Mutton Biryani', null, 'Pakistani', 'Rice', '{mutton,rice}', '{halal}', 19, 90, 'Weekend special mutton biryani.'),
  -- Dhaka
  ('dha', 1, 'Kacchi Biryani', 'কাচ্চি বিরিয়ানি', 'Bangladeshi', 'Rice', '{mutton,rice,old dhaka}', '{halal}', 450, 120, 'Puran Dhaka kacchi with khasi mutton and aloo.'),
  ('dha', 1, 'Borhani', 'বোরহানি', 'Bangladeshi', 'Drink', '{yogurt,mint}', '{vegetarian,gluten_free}', 80, 10, 'Spiced yogurt drink.'),
  ('dha', 2, 'Chicken Biriyani', 'মুরগির বিরিয়ানি', 'Bangladeshi', 'Rice', '{chicken,rice}', '{halal}', 320, 75, 'Home-style chicken biriyani.'),
  ('dha', 2, 'Morog Polao', 'মোরগ পোলাও', 'Bangladeshi', 'Rice', '{chicken,rice,wedding}', '{halal}', 350, 90, 'Wedding-style chicken polao.'),
  ('dha', 2, 'Shorshe Ilish', 'সর্ষে ইলিশ', 'Bangladeshi', 'Fish', '{hilsa,mustard}', '{halal,gluten_free}', 600, 45, 'Hilsa in mustard sauce.'),
  ('dha', 3, 'Bhuna Khichuri', 'ভুনা খিচুড়ি', 'Bangladeshi', 'Rice', '{lentil,rice,rainy day}', '{vegetarian}', 220, 60, 'Rich lentil-rice khichuri with fried eggplant.'),
  ('dha', 3, 'Beef Bhuna', 'গরুর মাংস ভুনা', 'Bangladeshi', 'Curry', '{beef}', '{halal,gluten_free}', 380, 90, 'Dry-fried spicy beef.'),
  ('dha', 4, 'Beef Tehari', 'গরুর তেহারি', 'Bangladeshi', 'Rice', '{beef,rice}', '{halal}', 280, 90, 'Mustard-oil beef tehari.'),
  ('dha', 4, 'Mutton Tehari', 'খাসির তেহারি', 'Bangladeshi', 'Rice', '{mutton,rice}', '{halal}', 340, 90, 'Mutton tehari, Puran Dhaka style.'),
  ('dha', 5, 'Bhapa Pitha', 'ভাপা পিঠা', 'Bangladeshi', 'Dessert', '{rice flour,jaggery,winter}', '{vegetarian,gluten_free}', 120, 30, 'Steamed rice cakes with date jaggery.'),
  ('dha', 5, 'Chitoi Pitha', 'চিতই পিঠা', 'Bangladeshi', 'Snack', '{rice flour}', '{vegan,gluten_free}', 100, 30, 'Rice pancakes with shutki bhorta.'),
  ('dha', 6, 'Fuchka', 'ফুচকা', 'Bangladeshi', 'Street Food', '{tamarind,chickpea}', '{vegetarian}', 120, 20, 'Crisp shells with spiced potato and tamarind water.'),
  ('dha', 6, 'Chotpoti', 'চটপটি', 'Bangladeshi', 'Street Food', '{peas,egg}', '{vegetarian}', 100, 20, 'Spicy yellow pea chaat.'),
  ('dha', 7, 'Mutton Biriyani', 'খাসির বিরিয়ানি', 'Bangladeshi', 'Rice', '{mutton,rice}', '{halal}', 420, 90, 'Sylheti mutton biriyani.'),
  ('dha', 8, 'Mezbani Beef', 'মেজবানি মাংস', 'Bangladeshi', 'Curry', '{beef,chattogram}', '{halal,gluten_free}', 400, 120, 'Chattogram feast-style beef.'),
  ('dha', 9, 'Shahi Biryani', 'শাহী বিরিয়ানি', 'Mughlai', 'Rice', '{chicken,rice,royal}', '{halal}', 500, 120, 'Royal Mughlai biryani with dried fruit.'),
  -- Kolkata
  ('kol', 1, 'Kolkata Mutton Biryani', 'কলকাতা মাটন বিরিয়ানি', 'Bengali', 'Rice', '{mutton,rice,aloo,egg}', '{halal}', 350, 90, 'With the famous potato and boiled egg.'),
  ('kol', 1, 'Chicken Chaap', 'চিকেন চাপ', 'Bengali', 'Curry', '{chicken,mughlai}', '{halal}', 260, 60, 'Rich, slow-cooked chicken chaap.'),
  ('kol', 2, 'Kosha Mangsho', 'কষা মাংস', 'Bengali', 'Curry', '{mutton,slow cooked}', '{gluten_free}', 380, 120, 'Slow-fried Bengali mutton curry.'),
  ('kol', 2, 'Luchi Alur Dom', 'লুচি আলুর দম', 'Bengali', 'Breakfast', '{potato,fried bread}', '{vegetarian}', 150, 30, 'Puffed luchi with spiced baby potatoes.'),
  ('kol', 3, 'Macher Jhol', 'মাছের ঝোল', 'Bengali', 'Fish', '{fish,rui,light curry}', '{gluten_free}', 220, 45, 'Light home-style rohu fish curry.'),
  ('kol', 3, 'Chingri Malai Curry', 'চিংড়ি মালাইকারি', 'Bengali', 'Fish', '{prawn,coconut}', '{gluten_free}', 420, 45, 'Prawns in coconut milk.'),
  ('kol', 4, 'Chilli Chicken', null, 'Indo-Chinese', 'Main', '{chicken,tangra}', '{}', 240, 30, 'Tangra-style chilli chicken.'),
  ('kol', 4, 'Veg Hakka Noodles', null, 'Indo-Chinese', 'Noodles', '{noodles,vegetables}', '{vegan}', 180, 20, 'Wok-tossed noodles.'),
  ('kol', 5, 'Rosogolla', 'রসগোল্লা', 'Bengali', 'Dessert', '{chhena,syrup}', '{vegetarian,gluten_free}', 120, 30, 'Spongy chhena balls in light syrup (box of 6).'),
  ('kol', 5, 'Mishti Doi', 'মিষ্টি দই', 'Bengali', 'Dessert', '{yogurt}', '{vegetarian,gluten_free}', 90, 10, 'Sweet set yogurt.'),
  ('kol', 6, 'Chicken Kathi Roll', null, 'Bengali', 'Street Food', '{paratha,chicken}', '{halal}', 140, 15, 'Egg-paratha roll with chicken tikka.'),
  ('kol', 6, 'Paneer Kathi Roll', null, 'Bengali', 'Street Food', '{paratha,paneer}', '{vegetarian}', 130, 15, 'Paneer tikka roll.'),
  ('kol', 7, 'Awadhi Chicken Biryani', 'अवधी चिकन बिरयानी', 'Awadhi', 'Rice', '{chicken,rice,dum}', '{halal}', 320, 90, 'Lucknowi pakki biryani.'),
  ('kol', 7, 'Galouti Kebab', null, 'Awadhi', 'Appetizer', '{mutton,kebab}', '{halal}', 300, 45, 'Melt-in-mouth minced mutton kebabs.'),
  ('kol', 8, 'Basanti Pulao', 'বাসন্তী পোলাও', 'Bengali', 'Rice', '{gobindobhog,sweet,festive}', '{vegetarian,gluten_free}', 200, 45, 'Saffron-yellow sweet pulao.'),
  ('kol', 8, 'Murgir Jhol', 'মুরগির ঝোল', 'Bengali', 'Curry', '{chicken,potato,sunday}', '{gluten_free}', 240, 60, 'Sunday-style light chicken curry with potatoes.'),
  ('kol', 9, 'Egg Biriyani', 'ডিম বিরিয়ানি', 'Bengali', 'Rice', '{egg,rice}', '{vegetarian}', 200, 60, 'Biriyani with masala eggs.'),
  -- Sydney
  ('syd', 1, 'Chicken Briyani', null, 'Pakistani', 'Rice', '{chicken,rice}', '{halal}', 18, 60, 'Lakemba favourite chicken briyani.'),
  ('syd', 1, 'Haleem', null, 'Pakistani', 'Stew', '{lentil,beef,wheat}', '{halal}', 15, 240, 'Slow-cooked meat, lentil and wheat stew.'),
  ('syd', 2, 'Hyderabadi Veg Biryani', null, 'Indian', 'Rice', '{rice,vegetables}', '{vegetarian}', 16, 45, 'Dum-cooked vegetable biryani.'),
  ('syd', 2, 'Masala Dosa', null, 'South Indian', 'Breakfast', '{potato,crepe}', '{vegan,gluten_free}', 14, 20, 'Crisp dosa with potato masala, sambar and chutney.'),
  ('syd', 3, 'Green Curry Chicken', 'แกงเขียวหวานไก่', 'Thai', 'Curry', '{chicken,coconut}', '{gluten_free}', 19, 40, 'Fragrant green curry.'),
  ('syd', 3, 'Pad See Ew', 'ผัดซีอิ๊ว', 'Thai', 'Noodles', '{noodles,beef}', '{}', 17, 25, 'Wide rice noodles, beef, Chinese broccoli.'),
  ('syd', 4, 'Moussaka', 'Μουσακάς', 'Greek', 'Main', '{eggplant,lamb}', '{}', 22, 90, 'Yiayia''s moussaka.'),
  ('syd', 4, 'Spanakopita', 'Σπανακόπιτα', 'Greek', 'Pastry', '{spinach,feta}', '{vegetarian}', 14, 60, 'Spinach and feta pie.'),
  ('syd', 5, 'Chicken Shawarma Plate', 'شاورما دجاج', 'Lebanese', 'Main', '{chicken,garlic}', '{halal}', 20, 40, 'With toum, pickles and rice.'),
  ('syd', 5, 'Falafel Wrap', 'فلافل', 'Lebanese', 'Wrap', '{chickpea,tahini}', '{vegan}', 13, 20, 'Crisp falafel with tahini.'),
  ('syd', 6, 'Pork Carnitas Tacos', null, 'Mexican', 'Tacos', '{pork}', '{gluten_free}', 16, 30, 'Slow-cooked carnitas.'),
  ('syd', 6, 'Vegan Mushroom Tacos', null, 'Mexican', 'Tacos', '{mushroom}', '{vegan,gluten_free}', 15, 25, 'Chipotle mushrooms, pickled onion.'),
  ('syd', 7, 'Pork and Chive Dumplings', '韭菜猪肉饺子', 'Chinese', 'Dumplings', '{pork,chive,jiaozi}', '{}', 14, 30, 'Twenty handmade dumplings.'),
  ('syd', 7, 'Vegetable Momo', null, 'Nepali', 'Dumplings', '{cabbage,momo}', '{vegan}', 13, 30, 'Steamed momo with tomato achar.'),
  ('syd', 8, 'Mutton Biryani', null, 'Pakistani', 'Rice', '{mutton,rice}', '{halal}', 20, 90, 'Family-recipe mutton biryani.');

insert into public.kitchen_cards (id, cook_id, title, title_local, description, tags, cuisine, category,
                                  diet_flags, price_cents, currency, prep_time_minutes)
select md5('card:' || s.city || ':' || s.n || ':' || s.title)::uuid,
       md5('cook:' || s.city || ':' || s.n)::uuid,
       s.title, s.title_local, s.description, s.tags, s.cuisine, s.category, s.diet,
       (s.price * 100)::int, c.currency, s.prep
  from seed_cards s join seed_cities c on c.code = s.city
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Cooking Now (live) posts — appear at the top of results with a LIVE badge.
-- ---------------------------------------------------------------------------
create temp table seed_live (
  city text, n int, title text, title_local text, cuisine text, category text, tags text[], diet text[],
  price numeric, ready_in_min int, hours int, portions int, description text
) on commit drop;
insert into seed_live values
  ('nyc', 2, 'Kacchi Biriyani — fresh Friday batch', 'কাচ্চি বিরিয়ানি', 'Bangladeshi', 'Rice', '{mutton,rice}', '{halal}', 17, 20, 12, 12, 'Just sealed the handi. Pickup from 20 minutes.'),
  ('nyc', 3, 'Birria Tacos with Consommé', null, 'Mexican', 'Tacos', '{beef,birria}', '{}', 14, 0, 12, 20, 'Hot off the plancha.'),
  ('lon', 2, 'Chicken Biriyani (today''s pot)', 'মুরগির বিরিয়ানি', 'Bangladeshi', 'Rice', '{chicken,rice}', '{halal}', 9, 15, 12, 10, 'Big pot on the stove now.'),
  ('lon', 7, 'Pho Ga', 'Phở gà', 'Vietnamese', 'Soup', '{chicken,noodles}', '{gluten_free}', 10, 0, 12, 8, 'Chicken pho, broth ready.'),
  ('tor', 2, 'Chicken Biryani — weekend pot', null, 'Pakistani', 'Rice', '{chicken,rice}', '{halal}', 16, 30, 12, 15, 'Ready in 30 minutes.'),
  ('dha', 1, 'Kacchi Biryani — live handi', 'কাচ্চি বিরিয়ানি', 'Bangladeshi', 'Rice', '{mutton,rice}', '{halal}', 430, 10, 12, 30, 'Handi opens in 10 minutes.'),
  ('dha', 3, 'Rainy-day Bhuna Khichuri', 'ভুনা খিচুড়ি', 'Bangladeshi', 'Rice', '{khichuri,egg}', '{vegetarian}', 200, 0, 12, 15, 'With egg bhuna and begun bhaja.'),
  ('kol', 1, 'Mutton Biryani with Aloo — evening batch', 'মাটন বিরিয়ানি', 'Bengali', 'Rice', '{mutton,rice,aloo}', '{halal}', 330, 25, 12, 25, 'Evening batch, limited plates.'),
  ('kol', 3, 'Ilish Macher Jhol', 'ইলিশ মাছের ঝোল', 'Bengali', 'Fish', '{hilsa,fish curry}', '{gluten_free}', 450, 0, 12, 6, 'Fresh hilsa today.'),
  ('syd', 1, 'Chicken Briyani — Friday special', null, 'Pakistani', 'Rice', '{chicken,rice}', '{halal}', 17, 15, 12, 20, 'Friday special, pickup from 15 minutes.'),
  ('syd', 7, 'Steamed Pork Dumplings', null, 'Chinese', 'Dumplings', '{pork,jiaozi}', '{}', 13, 0, 12, 30, 'Steaming now.');

insert into public.cooking_now_posts (id, cook_id, title, title_local, description, tags, cuisine, category,
                                      diet_flags, price_cents, currency, portions_total, portions_left,
                                      ready_at, available_until, status)
select md5('live:' || s.city || ':' || s.n || ':' || s.title)::uuid,
       md5('cook:' || s.city || ':' || s.n)::uuid,
       s.title, s.title_local, s.description, s.tags, s.cuisine, s.category, s.diet,
       (s.price * 100)::int, c.currency, s.portions, s.portions,
       now() + make_interval(mins => s.ready_in_min), now() + make_interval(hours => s.hours), 'live'
  from seed_live s join seed_cities c on c.code = s.city
on conflict (id) do update
  set status = 'live', ready_at = excluded.ready_at, available_until = excluded.available_until,
      portions_left = excluded.portions_total;

commit;
