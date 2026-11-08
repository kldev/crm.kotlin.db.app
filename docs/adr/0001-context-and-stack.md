# 0001. Context and stack

Status: Accepted
Date: 2026-11-08

## Context

A small CRM (users, clients, teams, projects) that shows how far plain T-SQL procedures go behind a hand-written
Kotlin API, and how they behave under load on a free edition of SQL Server. Single organisation: no tenants and no
platform-owner role above the application administrator.

## Decision

- Kotlin 2.4, JVM 25, Spring Boot 4.1 (Web MVC, Security, JDBC, Actuator, Validation), Gradle 9.7 Kotlin DSL,
  one application project `app` (the business logic is in the database, so there is no domain module to split off).
- SQL Server 2025 **Express** (`MSSQL_PID=Express`), not Developer: the limits of the free edition are part of
  the experiment (50 GB per database, buffer pool about 1.4 GB, at most 4 cores / 1 socket).
- One Docker image with three modes (`CRM_MODE=app|migrate|seed`); docker compose for the local stack.
- Flyway for migrations: versioned files for tables, repeatable `R__` files (`CREATE OR ALTER`) for procedures.
- REST API with OpenAPI from controller annotations (springdoc), no frontend.

## Consequences

Plus: one place for every rule (the procedure), the API is thin and readable.
Minus: Express caps memory and CPU, so performance numbers are for this edition, not for SQL Server in general.

## Alternatives considered

- Developer edition: no limits, but the result would not say anything about the free edition.
- Liquibase: equivalent; Flyway is simpler with plain `.sql` files and has Spring Boot support.
