# WSL containers (`wslc`)

WSL containers is a container runtime built into WSL. The CLI is `wslc.exe`, which ships with WSL
itself. You don't need Docker Desktop, and you don't need a distro running. Containers run in a
WSL-managed utility VM, and images come from normal OCI registries (Docker Hub, MCR).

This page is the `wslc` reference part of **wslc-recipes**: what the CLI looks like, how it behaves,
and how the recipes in this repo use it.

> The Microsoft page linked when this repo was started
> (<https://learn.microsoft.com/en-us/virtualization/windowscontainers/about/>) is the general
> _Windows containers_ overview and does not document `wslc`. Everything below was verified hands-on
> with `wslc --help` and real runs.

## Tested environment

| Component  | Version                                                     |
| ---------- | ----------------------------------------------------------- |
| Windows    | 11 Pro 10.0.26300                                           |
| WSL        | 3.0.1.0 (kernel 6.18.40.1-1)                                |
| wslc       | 3.0.1.0                                                     |
| Task       | go-task (`scoop install task` / `winget install Task.Task`) |
| PowerShell | 7+ (`pwsh`)                                                 |

Check your own setup with `task check` (it runs `wslc version` and `wslc info`).

## CLI at a glance

`wslc` deliberately mirrors the Docker CLI:

| Docker                                                        | wslc                                                         |
| ------------------------------------------------------------- | ------------------------------------------------------------ |
| `docker run -d --name x -p 5432:5432 -e K=V -v vol:/data img` | `wslc run -d --name x -p 5432:5432 -e K=V -v vol:/data img`  |
| `docker ps -a`                                                | `wslc list --all` (aliases: `ls`, `ps`)                      |
| `docker rm -f x`                                              | `wslc remove -f x`                                           |
| `docker stop x y`                                             | `wslc stop x y` (several names at once)                      |
| `docker run --label k=v` / `ps --filter label=k`              | `wslc run --label k=v` / `wslc list --filter label=k`        |
| `docker exec -it x sh`                                        | `wslc exec -it x sh`                                         |
| `docker logs x`                                               | `wslc logs x`                                                |
| `docker volume create/ls/rm`                                  | `wslc volume create/list/remove`                             |
| `docker network create`                                       | `wslc network create` (default driver: `bridge`)             |
| `docker inspect x`                                            | `wslc inspect x` (exit code 1 if not found)                  |
| `docker compose`                                              | **not available** - this repo uses PowerShell + Task instead |

Useful extras:

- `wslc list --all --format json` prints one JSON object per line (good for scripting). The same
  works for `wslc volume list` and `wslc network list`.
- `--label` exists on `run`, `volume create` and `network create`, and `--filter label=<key>`
  (key present, any value) works on all three `list` commands.
- `wslc settings` opens `%LOCALAPPDATA%\wslc\settings.yaml`.
- `--session` (global option) targets a specific wslc session.

## Behaviour observed while building this repo

| Topic               | Finding                                                                                                                                                                                            |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Port publishing     | `-p 5432:5432` binds to **`127.0.0.1` only**. Connecting to `localhost` may first try `::1`, which fails, so use `127.0.0.1` in clients. The DBs are not reachable from other machines on the LAN. |
| Container DNS       | Containers on the same user-defined network resolve each other by container name (pgAdmin reaches `wslc-postgresql` / `wslc-timescale` this way). Containers on different networks cannot.         |
| Bind mounts         | Windows paths work directly: `-v C:\path\file.json:/target:ro`. Used for pgAdmin's `servers.json`.                                                                                                 |
| Named volumes       | Default driver `guest` (a `vhd` driver also exists). Data survives `remove` + re-create of the container.                                                                                          |
| Anonymous volumes   | Images that declare `VOLUME` leave anonymous volumes behind unless you remove the container with `--volumes`. The scripts' `down` does this.                                                       |
| Labels              | Set only at creation time; there is no way to add one to an existing container/volume. `-v name:/path` auto-creates an **unlabelled** volume, so the recipes `volume create --label` first.        |
| `--memory`          | Works, but prints `Your kernel does not support swap limit capabilities ...`. This is harmless.                                                                                                    |
| Startup times       | SQL Server ~5-10 s, PostgreSQL/TimescaleDB ~2 s, pgAdmin ~40-60 s (first start is the slowest).                                                                                                    |
| SQL Server on Linux | `mcr.microsoft.com/mssql/server:2025-latest` is the recipe default (Developer edition, 2 GB memory limit set); this version has not yet been run in this environment.                              |

Not tested yet: whether containers/volumes survive `wsl --shutdown` or a reboot, GPU flags, `wslc build`.

## How the recipes map onto wslc

There are three independent recipes. Each has its own script, containers, volumes and network, and
nothing is shared:

```
Windows host (127.0.0.1)

 scripts/mssql.ps1
   SSMS / sqlcmd ── :1433 ──► wslc-mssql                (wslc-mssql-data)        default bridge network

 scripts/postgresql.ps1                                          network wslc-postgresql-net
   psql / IDE ───── :5432 ──► wslc-postgresql           (wslc-postgresql-18-data)       ▲
   Browser ──────── :5050 ──► wslc-postgresql-pgadmin   (wslc-postgresql-pgadmin-data) ─┘ by name

 scripts/postgresql+timescale.ps1                                network wslc-timescale-net
   psql / IDE ───── :5433 ──► wslc-timescale            (wslc-timescale-18-data)        ▲
   Browser ──────── :5051 ──► wslc-timescale-pgadmin    (wslc-timescale-pgadmin-data)  ─┘ by name
```

The scripts are self-contained on purpose, with no shared module, so each one can be copied to
another project on its own. Defaults live at the top of each script, and `.env` overrides them.
`Taskfile.yml` includes one Taskfile per recipe (`taskfile/`) as the namespaces `mssql:`,
`postgresql:` and `timescale:`. The full list of conventions is in the
[README](../README.md#recipe-conventions).

Verified isolation: pgAdmin of the PostgreSQL recipe cannot resolve `wslc-timescale`, and
`task postgresql:reset` leaves the other two recipes untouched.

## Finding the repo's resources

Every container, named volume and network a recipe creates carries the label
`wslc-recipes=<recipe>`:

```powershell
wslc list --all --filter label=wslc-recipes        # all recipes
wslc list --all --filter label=wslc-recipes=mssql  # one recipe
wslc volume list --filter label=wslc-recipes
wslc network list --filter label=wslc-recipes
```

`scripts/clean.ps1` (`task clean` / `task purge`) uses the label plus a name match
(`^wslc-(mssql|postgresql|timescale)(-|$)`). The name match is needed because labels can't be added
after creation, so resources created before the label was introduced, or by hand, would otherwise be
missed.
