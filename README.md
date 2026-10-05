# wslc-recipes

Recipes for running local development infrastructure on **WSL containers** (`wslc`), the container
runtime built into WSL. No Docker Desktop, no distro, no `docker compose`: each recipe is one
self-contained PowerShell script plus a thin [Task](https://taskfile.dev) wrapper.

Use this repo as a reference for how to set up local infrastructure with `wslc`: copy a recipe into
another project, or use it as a template for a new one. It's for local research and development only,
not production.

## Recipes

Each recipe is **independent**: its own script, containers, volumes and network. Run any combination;
ports differ, so all of them can run side by side.

| Recipe                      | Script                             | Endpoint (Windows host) | Management                                 | Docs                                                    |
| --------------------------- | ---------------------------------- | ----------------------- | ------------------------------------------ | ------------------------------------------------------- |
| SQL Server 2025             | `scripts/mssql.ps1`                | `127.0.0.1,1433`        | SSMS on the host: `scripts/mssql-ssms.ps1` | [mssql.md](docs/mssql.md)                               |
| PostgreSQL 18               | `scripts/postgresql.ps1`           | `127.0.0.1:5432`        | pgAdmin <http://127.0.0.1:5050>            | [postgresql.md](docs/postgresql.md)                     |
| PostgreSQL 18 + TimescaleDB | `scripts/postgresql+timescale.ps1` | `127.0.0.1:5433`        | pgAdmin <http://127.0.0.1:5051>            | [postgresql+timescale.md](docs/postgresql+timescale.md) |

## Prerequisites

- Windows 11 with a WSL version that includes `wslc` (`wsl --update`)
- PowerShell 7+ (`pwsh`)
- [Task](https://taskfile.dev) (`scoop install task` or `winget install Task.Task`). Optional: the
  scripts can be run directly.
- Optional: SQL Server Management Studio

## Quick start

```powershell
task check              # wslc installed and responding?

task mssql:up           # SQL Server
task mssql:ssms         #   open SSMS connected to it

task postgresql:up      # PostgreSQL + pgAdmin
task postgresql:pgadmin #   open pgAdmin

task timescale:up       # PostgreSQL + TimescaleDB + pgAdmin
task timescale:pgadmin  #   open pgAdmin

task clean              # done for the day: stop + remove everything this repo started (data kept)
```

Without Task: `./scripts/postgresql.ps1 up`, `./scripts/mssql.ps1 shell`, `./scripts/clean.ps1`, and so on.

## Commands

Every recipe has the same set: `task <recipe>:<command>`, where `<recipe>` is `mssql`, `postgresql`
or `timescale`.

| Command                                   | What it does                                                         |
| ----------------------------------------- | -------------------------------------------------------------------- |
| `up`                                      | Create/start the containers and wait until they accept connections   |
| `stop`                                    | Stop the containers (keep them)                                      |
| `down`                                    | Remove the containers, keep data                                     |
| `reset`                                   | Remove the containers, **data volumes** and network (asks first)     |
| `status`                                  | Container and volume state                                           |
| `info`                                    | Connection details                                                   |
| `logs`                                    | Container logs (PostgreSQL recipes: `-- pgadmin` for pgAdmin's logs) |
| `shell`                                   | `sqlcmd` / `psql` inside the container                               |
| `pull`                                    | Pre-pull images                                                      |
| `mssql:ssms`                              | Launch SSMS on the host                                              |
| `postgresql:pgadmin`, `timescale:pgadmin` | Open that recipe's pgAdmin                                           |

Repo-wide:

| Command      | What it does                                                                             |
| ------------ | ---------------------------------------------------------------------------------------- |
| `task ps`    | List **all** wslc containers, volumes and networks (also ones not from this repo)        |
| `task clean` | Stop and remove the containers and networks of every recipe. Data volumes are kept       |
| `task purge` | `clean` plus delete every recipe's data volumes and the generated `.local/` (asks first) |

`clean` and `purge` find this repo's resources by the `wslc-recipes` label and by name
(`wslc-mssql*`, `wslc-postgresql*`, `wslc-timescale*`), so they also catch leftovers from older runs
or from manual experiments. Anything else on your machine is left alone.

## Configuration

Defaults are built into each script. To override ports, passwords or images, run `task env` (it
copies [.env.example](.env.example) to the git-ignored `.env`) and edit the keys for your recipe:
`MSSQL_*`, `POSTGRES_*` or `TIMESCALE_*`.

An existing `.env` keeps its image overrides when these defaults change. Update any old image tags
there before recreating containers. Existing containers keep the image they were created with; see
each recipe's upgrade notes before running `down` and `up`.

## Recipe conventions

Every recipe follows the same pattern, so they read alike and are easy to copy:

| Convention      | Rule                                                                                                    |
| --------------- | ------------------------------------------------------------------------------------------------------- |
| One script      | `scripts/<recipe>.ps1` is self-contained (no shared module), so it can be copied on its own             |
| Actions         | `up`, `stop`, `down`, `reset`, `status`, `info`, `logs`, `shell`, `pull` (+ recipe-specific ones)       |
| Names           | containers `wslc-<recipe>[-<role>]`, volumes `wslc-<recipe>[-<role>]-data`, network `wslc-<recipe>-net` |
| Label           | everything created gets `--label wslc-recipes=<recipe>`, which is how `task clean` finds it             |
| Config          | defaults at the top of the script, overridable by `<RECIPE>_*` keys in `.env`                           |
| Ports           | published on `127.0.0.1` only, each recipe on its own host ports                                        |
| Idempotent `up` | creates what's missing, starts what's stopped, then waits until the service accepts connections         |
| Generated files | under `.local/<recipe>/` (git-ignored), e.g. pgAdmin's `servers.json`                                   |
| Task wrapper    | `taskfiles/<recipe>.yml`, included in `Taskfile.yml` as the `<recipe>:` namespace                        |

### Adding a recipe

1. Copy the closest script (`mssql.ps1` for one container, `postgresql.ps1` for an app + admin UI on a
   private network) to `scripts/<recipe>.ps1` and adapt the config block, names and readiness probe.
2. Copy a `taskfiles/*.yml`, point it at the new script and include it in `Taskfile.yml`.
3. Add the `<RECIPE>_*` keys to `.env.example`.
4. Add the recipe name to `$NamePattern` in `scripts/clean.ps1`.
5. Write `docs/<recipe>.md` and add a row to the [Recipes](#recipes) table.

## Layout

```
scripts/
  mssql.ps1                    SQL Server recipe
  mssql-ssms.ps1               launch SSMS against the mssql recipe
  postgresql.ps1               PostgreSQL + pgAdmin recipe
  postgresql+timescale.ps1     PostgreSQL + TimescaleDB + pgAdmin recipe
  clean.ps1                    stop + remove all resources of all recipes
taskfiles/                      one Taskfile per recipe (namespaced in Taskfile.yml)
docs/                          wslc findings, per-recipe connection guides, troubleshooting
.local/                        generated files, git-ignored (pgAdmin servers.json)
```

## Docs

- [WSL containers: CLI, findings, how the recipes map onto wslc](docs/wsl-containers.md)
- [SQL Server and SSMS](docs/mssql.md)
- [PostgreSQL and pgAdmin](docs/postgresql.md)
- [PostgreSQL + TimescaleDB and pgAdmin](docs/postgresql+timescale.md)
- [Troubleshooting](docs/troubleshooting.md)
