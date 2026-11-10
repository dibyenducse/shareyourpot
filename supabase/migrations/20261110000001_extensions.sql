-- Extensions used by "Find a Dish Near Me".
-- Supabase convention: extensions live in the `extensions` schema.
create schema if not exists extensions;

create extension if not exists postgis       with schema extensions;
create extension if not exists pg_trgm       with schema extensions;
create extension if not exists unaccent      with schema extensions;
create extension if not exists fuzzystrmatch with schema extensions;

-- unaccent() is only STABLE (it depends on a dictionary), so it cannot be used in
-- index expressions / generated columns. This wrapper pins the dictionary, which
-- makes it safe to declare IMMUTABLE (the standard, documented workaround).
create or replace function public.immutable_unaccent(input text)
returns text
language sql
immutable
parallel safe
strict
set search_path = ''
as $$
  select extensions.unaccent('extensions.unaccent'::regdictionary, input)
$$;

-- Normalise free text for matching: unaccent, lowercase, collapse punctuation/whitespace.
-- Keeps non-Latin letters and combining marks (Bengali, Hindi, Arabic, ...) intact for
-- multilingual search: we strip an explicit punctuation list rather than "not [:alnum:]",
-- because [:alnum:] excludes all non-ASCII letters under the C collation.
create or replace function public.normalize_dish_text(input text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select btrim(regexp_replace(
           regexp_replace(lower(public.immutable_unaccent(coalesce(input, ''))),
                          '[!-/:-@\[-`{-~‘’“”–—…।॥،؛·•]+', ' ', 'g'),
           '\s+', ' ', 'g'))
$$;
