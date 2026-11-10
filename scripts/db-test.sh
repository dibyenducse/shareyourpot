#!/usr/bin/env bash
# Runs migrations + seed + SQL tests against a throwaway database on a plain Postgres
# (needs PostGIS + pg_trgm installed). Supabase specifics are stubbed by
# supabase/tests/00_local_supabase_stub.sql.
#
#   PGHOST=/tmp PGPORT=5432 PGUSER=postgres ./scripts/db-test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${TEST_DB:-shareyourpot_test}"
PSQL=(psql -X -q -v ON_ERROR_STOP=1 --set=client_min_messages=warning)

"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
export PGOPTIONS='-c client_min_messages=warning'
"${PSQL[@]}" -d "$DB" -f supabase/tests/00_local_supabase_stub.sql
for f in supabase/migrations/*.sql; do
  echo "migrate: $f"
  "${PSQL[@]}" -d "$DB" -f "$f"
done
echo "seed: supabase/seed.sql"
"${PSQL[@]}" -d "$DB" -f supabase/seed.sql
for f in supabase/tests/[1-9]*.sql; do
  [ -e "$f" ] || continue
  echo "test: $f"
  "${PSQL[@]}" -d "$DB" -f "$f"
done
echo "OK"
