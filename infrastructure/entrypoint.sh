#!/bin/sh
# CRM_MODE selects what the container does: app (HTTP API), migrate (Flyway, then exit), seed (EXEC seed.run, then exit).
set -e
case "${CRM_MODE:-app}" in
  app)     profiles="" ;;
  migrate) profiles="migrate" ;;
  seed)    profiles="seed" ;;
  *) echo "Unknown CRM_MODE '${CRM_MODE}' (expected: app, migrate, seed)" >&2; exit 2 ;;
esac
exec java -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError \
  ${profiles:+-Dspring.profiles.active=$profiles} \
  -jar /app/app.jar "$@"
