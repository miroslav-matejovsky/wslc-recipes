# PostgreSQL + TimescaleDB + pgAdmin

Script: `scripts/postgresql+timescale.ps1`. Tasks: `task timescale:<command>`. This recipe is
independent of the [plain PostgreSQL recipe](postgresql.md) and can run alongside it, since it uses
different ports.

| Setting | Value |
|---------|-------|
| Image | `timescale/timescaledb:latest-pg17` |
| Host endpoint | `127.0.0.1:5433` |
| User / password | `postgres` / `postgres` |
| Default database | `tsdb` (TimescaleDB extension already enabled) |
| pgAdmin | <http://127.0.0.1:5051> |
| Containers | `wslc-timescale`, `wslc-timescale-pgadmin` |
| Volumes | `wslc-timescale-data`, `wslc-timescale-pgadmin-data` |
| Network | `wslc-timescale-net` (pgAdmin reaches the DB as `wslc-timescale:5432`) |

Override with the `TIMESCALE_*` keys in `.env`. User, password and database are fixed on first start.
To apply new ones, run `task timescale:reset` (this destroys data).

```powershell
task timescale:up
task timescale:shell           # psql inside the container
task timescale:logs -- pgadmin # pgAdmin logs (default: db)
task timescale:pgadmin         # open pgAdmin in the browser
```

## pgAdmin

pgAdmin works the same way as in the [PostgreSQL recipe](postgresql.md#pgadmin): desktop mode,
server pre-registered from the generated `.local/timescale/pgadmin-servers.json`, password `postgres`
on first connect.

## Connect from Windows clients

| Client | How |
|--------|-----|
| psql on Windows | `psql "postgresql://postgres:postgres@127.0.0.1:5433/tsdb"` |
| VS Code / DBeaver / DataGrip | Host `127.0.0.1`, port `5433`, user `postgres` |
| .NET (Npgsql) | `Host=127.0.0.1;Port=5433;Database=tsdb;Username=postgres;Password=postgres` |
| JDBC | `jdbc:postgresql://127.0.0.1:5433/tsdb` |

## TimescaleDB quick check

The image creates the `timescaledb` extension in the default database (`tsdb`) automatically:

```sql
SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';

CREATE TABLE metrics (
    time   timestamptz NOT NULL,
    device text        NOT NULL,
    value  double precision
);
SELECT create_hypertable('metrics', by_range('time'));

INSERT INTO metrics
SELECT t, 'dev-' || (random() * 5)::int, random() * 100
FROM generate_series(now() - interval '1 day', now(), interval '1 minute') AS t;

SELECT time_bucket('1 hour', time) AS hour, device, avg(value)
FROM metrics GROUP BY 1, 2 ORDER BY 1 DESC LIMIT 10;
```

In any other database, run `CREATE EXTENSION IF NOT EXISTS timescaledb;` first.
