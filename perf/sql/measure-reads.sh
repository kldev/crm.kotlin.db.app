#!/usr/bin/env bash
# Runs measure-reads.sql in the compose mssql container and writes the warm-run statistics to <dir>/sql-reads.md.
set -euo pipefail
cd "$(dirname "$0")/../../infrastructure"
out="${1:?usage: measure-reads.sh <results dir>}"
mkdir -p "$out"
pass=$(grep -E '^CRM_DB_MIGRATOR_PASSWORD=' .env | cut -d= -f2)
user=$(grep -E '^CRM_DB_MIGRATOR_USER=' .env | cut -d= -f2); user=${user:-crm_migrator}
db=$(grep -E '^CRM_DB_NAME=' .env | cut -d= -f2); db=${db:-crm}
docker compose --env-file .env exec -T -e SQLCMDPASSWORD="$pass" mssql \
  /opt/mssql-tools18/bin/sqlcmd -S localhost -U "$user" -C -I -d "$db" -h -1 -W \
  < ../perf/sql/measure-reads.sql > "$out/sql-reads-raw.txt"
# Second (measured) run only -> one row per call: total logical reads, reads per table, CPU and elapsed time.
awk '/^==== client_search: newest/{run++} run>=2' "$out/sql-reads-raw.txt" | awk '
  function flush() {
    if (label != "") printf "| %s | %d | %s | %d | %d |\n", label, total, tables, cpu, elapsed
  }
  /^==== / { flush(); label = substr($0, 6); total = 0; tables = ""; cpu = 0; elapsed = 0; next }
  /^Table / {
    match($0, /Table \x27[^\x27]+\x27/); t = substr($0, RSTART + 7, RLENGTH - 8)
    match($0, /logical reads [0-9]+/); r = substr($0, RSTART + 14, RLENGTH - 14) + 0
    if (r > 0) { total += r; tables = tables (tables == "" ? "" : ", ") t " " r }
    next
  }
  /CPU time/ {
    match($0, /CPU time = [0-9]+/); cpu += substr($0, RSTART + 11, RLENGTH - 11)
    match($0, /elapsed time = [0-9]+/); elapsed += substr($0, RSTART + 15, RLENGTH - 15)
  }
  END { flush() }
' > "$out/sql-reads.body"
{
  echo "| Call | Logical reads (8 KB pages) | Reads per table | CPU ms | Elapsed ms |"
  echo "|---|---:|---|---:|---:|"
  cat "$out/sql-reads.body"
} > "$out/sql-reads.md"
rm "$out/sql-reads.body"
rm "$out/sql-reads-raw.txt"
echo "written: $out/sql-reads.md"
