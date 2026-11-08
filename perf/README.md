# Performance

Load tests with k6 against the seeded data set (ADR-0004), on SQL Server 2025 **Express**.

| Run | Scenario | VUs | Result |
|---|---|---|---|
| - | not run yet | - | - |

Each run is stored in `perf/results/<yyyy-mm-dd>-<scenario>/`: `summary.json` (k6 `handleSummary`),
`summary.txt`, `sql-reads.txt` (logical reads per procedure) and `REPORT.md` (environment, Express limits,
p50/p95/p99 per endpoint, RPS, errors, slowest procedures, conclusions).

```bash
cd infrastructure
./start.sh --clean --seed            # the data set
./start.sh --k6 crm-mixed.js         # 200 VUs, results in perf/results/<date>-crm-mixed
```
