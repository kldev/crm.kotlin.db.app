#!/usr/bin/env bash
# Builds the React app and copies dist/ into the Spring Boot resources (app/src/main/resources/static), so the
# application serves the website from the same origin as the API (session and CSRF cookies just work).
# The Docker image runs the same build in its own stage; this script is for local runs (./gradlew bootRun,
# or a jar built outside Docker). The copied files are git-ignored: the source of truth is frontend/.
set -euo pipefail
cd "$(dirname "$0")"

target=../app/src/main/resources/static

corepack enable >/dev/null 2>&1 || true
yarn install --immutable
yarn build

rm -rf "$target"
mkdir -p "$target"
cp -R dist/. "$target/"
echo "Copied $(find "$target" -type f | wc -l) files to app/src/main/resources/static"
