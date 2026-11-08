# syntax=docker/dockerfile:1
# One image, three modes (CRM_MODE): app (default), migrate (Flyway, then exit), seed (EXEC seed.run, then exit).
# The React app (frontend/), built once and served by Spring Boot from resources/static.
FROM node:22-alpine AS web
WORKDIR /web
RUN corepack enable
COPY frontend/package.json frontend/yarn.lock frontend/.yarnrc.yml ./
RUN --mount=type=cache,target=/root/.yarn/berry/cache yarn install --immutable
COPY frontend/ ./
RUN yarn build

# The Gradle image has the same Gradle as the wrapper (gradle/wrapper/gradle-wrapper.properties), so the build
# does not download a distribution.
FROM gradle:9.8.2-jdk25 AS build
WORKDIR /workspace

COPY settings.gradle.kts build.gradle.kts gradle.properties ./
COPY gradle/libs.versions.toml gradle/libs.versions.toml
COPY app/build.gradle.kts app/build.gradle.kts
RUN --mount=type=cache,target=/home/gradle/.gradle gradle :app:dependencies --no-daemon -q > /dev/null

COPY app/src/main app/src/main
COPY --from=web /web/dist app/src/main/resources/static
RUN --mount=type=cache,target=/home/gradle/.gradle gradle :app:bootJar --no-daemon -q

# Layers: dependencies change rarely, the application on every commit.
RUN java -Djarmode=tools -jar app/build/libs/app.jar extract --layers --destination /extracted

FROM eclipse-temurin:25-jre AS runtime

# HEALTHCHECK calls curl, which the temurin image does not ship.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home app

WORKDIR /app
COPY --from=build --chown=10001:10001 /extracted/dependencies/ ./
COPY --from=build --chown=10001:10001 /extracted/spring-boot-loader/ ./
COPY --from=build --chown=10001:10001 /extracted/snapshot-dependencies/ ./
COPY --from=build --chown=10001:10001 /extracted/application/ ./
COPY --chmod=755 infrastructure/entrypoint.sh /app/entrypoint.sh

USER 10001:10001
EXPOSE 8080

# Only the web mode has an HTTP port; migrate and seed are one-shot containers.
HEALTHCHECK --interval=10s --timeout=5s --start-period=40s --retries=5 \
    CMD [ "${CRM_MODE:-app}" != "app" ] || curl -fsS http://localhost:${PORT:-8080}/actuator/health/readiness || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
