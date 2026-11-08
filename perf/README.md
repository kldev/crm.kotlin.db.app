# Performance

Load tests with k6 against the seeded data set (ADR-0004) on SQL Server 2025 **Express**, everything on one
laptop (16 cores, 30 GB RAM). Thresholds: p95 < 500 ms, p99 < 1 s, errors < 1%.

| Run | Change | VUs | Requests | p95 | p99 | Errors | DB CPU avg | Report |
|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | baseline (schema V3) | 200 | 260 563 (334/s) | 56.1 ms | 81.2 ms | 0.00% | 198% | [REPORT](results/2026-11-08-run1-baseline/REPORT.md) |
| 2 | read indexes + SALES project search (V4) | 200 | 263 307 (338/s) | **8.5 ms** | **10.4 ms** | 0.00% | **58%** | [REPORT](results/2026-11-08-run2-indexes/REPORT.md) |

Each run directory holds `summary.json` and `summary.txt` (k6), `k6-console.txt`, `docker-stats.txt`,
`procedure-stats.txt` (`sys.dm_exec_procedure_stats` of the run), `sql-reads.md` (logical reads per procedure,
`SET STATISTICS IO`) and `REPORT.md`.

## Run it

```bash
cd infrastructure
./start.sh --clean --seed                       # data set: about 13 min
# clear procedure statistics so they cover only the run (optional):
#   ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
./start.sh --k6 crm-mixed.js 2026-11-08-my-run  # 200 VUs, 13 min; K6_VUS / K6_RAMP / K6_HOLD / K6_RAMP_DOWN override
../perf/sql/measure-reads.sh "$PWD/../perf/results/2026-11-08-my-run"   # logical reads per procedure
```

`perf/k6/crm-mixed.js`: each VU logs in once (90% `perf.sales.NNNN`, 10% `perf.manager.NNNN`) and repeats a
weighted action: searches and details dominate, about a quarter of iterations write (create/update client, add
comment, change stage, create project).
