# PostgreSQL + pgAdmin

Script: `scripts/postgresql.ps1`. Tasks: `task postgresql:<command>`. This recipe is independent of
the [TimescaleDB recipe](postgresql+timescale.md) and can run alongside it.

| Setting | Value |
|---------|-------|
| Image | `postgres:17` |
| Host endpoint | `127.0.0.1:5432` |
| User / password | `postgres` / `postgres` |
| Default database | `app` |
| pgAdmin | <http://127.0.0.1:5050> |
| Containers | `wslc-postgresql`, `wslc-postgresql-pgadmin` |
| Volumes | `wslc-postgresql-data`, `wslc-postgresql-pgadmin-data` |
| Network | `wslc-postgresql-net` (pgAdmin reaches the DB as `wslc-postgresql:5432`) |

Override with the `POSTGRES_*` keys in `.env`. User, password and database are fixed on first start.
To apply new ones, run `task postgresql:reset` (this destroys data).

```powershell
task postgresql:up
task postgresql:shell           # psql inside the container
task postgresql:logs -- pgadmin # pgAdmin logs (default: db)
task postgresql:pgadmin         # open pgAdmin in the browser
```

## pgAdmin

- `up` starts pgAdmin with the database and waits for it. First start takes about 40-60 s.
- It runs in **desktop mode**, so there is no pgAdmin login screen. This is fine for local research,
  but don't expose it.
- The server is pre-registered (group **wslc-recipes**). The script generates
  `.local/postgresql/pgadmin-servers.json` from the current config and mounts it into the container.
  pgAdmin connects over the recipe's private network by container name, not via `127.0.0.1`.
- The first time you open the server, pgAdmin asks for the password (`postgres`). Tick *Save password*.
- pgAdmin imports `servers.json` only when its data volume is first created. If you change the
  user or database, run `task postgresql:reset`.

## Connect from Windows clients

| Client | How |
|--------|-----|
| psql on Windows | `psql "postgresql://postgres:postgres@127.0.0.1:5432/app"` |
| VS Code / DBeaver / DataGrip | Host `127.0.0.1`, port `5432`, user `postgres` |
| .NET (Npgsql) | `Host=127.0.0.1;Port=5432;Database=app;Username=postgres;Password=postgres` |
| JDBC | `jdbc:postgresql://127.0.0.1:5432/app` |

Use `127.0.0.1`, not `localhost`. wslc publishes ports on IPv4 loopback only. See
[wsl-containers.md](wsl-containers.md).
