# 0004. One configurable seed for performance tests

Status: Accepted (stage 1)
Date: 2026-11-08

## Decision

- There is one seed: `seed.run`, a set-based procedure (GENERATE_SERIES, INSERT ... SELECT in batches, no row
  loops), started by `./start.sh --seed` (container `CRM_MODE=seed`, migrator login).
- Defaults: 5 000 000 clients, 5 000 000 projects, 2 000 000 comments, 5 000 users (10 ADMIN, 490 MANAGER,
  4 500 SALES), teams of 5 SALES users led by managers. Every value is configurable with `CRM_SEED_*`.
- Deterministic: every value is derived from SHA2_256(random seed, row number).
- Logins `perf.admin.NNNN`, `perf.manager.NNNN`, `perf.sales.NNNN`, one password from `CRM_SEED_PASSWORD`
  (hashed once by the application's encoder, so k6 uses the real login endpoint).
- Refuses to run on a database with clients (51060); start again with `./start.sh --clean --seed`.

## Planned, not done

- k6 scenario with 200 virtual users and the measurement of logical reads per procedure; results committed in
  `perf/results/`.
