# Troubleshooting

`<recipe>` below is `mssql`, `postgresql` or `timescale`.

| Symptom | Fix |
|---------|-----|
| `wslc not found` | `wsl --update`, then reopen the terminal. `wslc` lives in `C:\Program Files\WSL\`. |
| Client can't connect to `localhost` | Use `127.0.0.1`. Published ports are IPv4 loopback only. |
| `up` times out | `task <recipe>:logs` (or `-- pgadmin`). For SQL Server this is usually a password that is too weak (complexity rules) or not enough memory. |
| Port already in use | A local DB is already listening. Change the `*_PORT` key in `.env`, then `task <recipe>:down` and `task <recipe>:up`. |
| Changed password in `.env`, no effect | Credentials are fixed on first init. Run `task <recipe>:reset` (destroys data). |
| pgAdmin doesn't show the server / wrong user | `servers.json` is imported only on the first start. Run `task <recipe>:reset`. |
| `kernel does not support swap limit` warning | Harmless. It comes from `--memory` on the SQL Server container. |
| Leftover containers / ports still taken after a session | `task clean` stops and removes the containers and networks of all recipes (data kept). `task purge` also deletes the data. `task ps` shows what's left. |
| Something not from a recipe is left over | `clean` only touches this repo's resources. Remove others with `wslc remove -f <name>` / `wslc volume remove <name>`. |

## Command lifecycle

| Command | Containers | Data volumes | Network |
|---------|-----------|--------------|---------|
| `task <recipe>:stop` | stopped (kept) | kept | kept |
| `task <recipe>:down` | removed | kept | kept |
| `task <recipe>:reset` | removed | **deleted** (asks for confirmation) | removed |
| `task <recipe>:up` | created or started | created if missing | created if missing |
| `task clean` | all recipes: stopped and removed | kept | all recipes: removed |
| `task purge` | all recipes: stopped and removed | all recipes: **deleted** (asks for confirmation) | all recipes: removed |

After changing ports, images or env in `.env`, run `task <recipe>:down` and then `task <recipe>:up`.
Containers are re-created with the new settings and the data is kept. Each `<recipe>:` command
touches only its own recipe; `clean` and `purge` touch all of them.
