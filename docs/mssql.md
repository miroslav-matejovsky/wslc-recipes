# SQL Server

Script: `scripts/mssql.ps1` (+ `scripts/mssql-ssms.ps1`). Tasks: `task mssql:<command>`. This recipe is independent
of the PostgreSQL recipes.

| Setting | Value |
|---------|-------|
| Container | `wslc-mssql` |
| Image | `mcr.microsoft.com/mssql/server:2025-latest` (Developer edition) |
| Host endpoint | `127.0.0.1,1433` (note the **comma**, SQL Server syntax for a port) |
| Login | `sa` / `MSSQL_SA_PASSWORD` (default `Dev_Passw0rd!`) |
| Encryption | Self-signed certificate, so tick **Trust server certificate** |
| Data | volume `wslc-mssql-data` mounted at `/var/opt/mssql` |

```powershell
task mssql:up
task mssql:shell         # sqlcmd inside the container
```

## Can SSMS run "in" wslc?

No. SQL Server Management Studio is a Windows desktop application, and wslc runs **Linux** containers.
That's fine, because SSMS runs on the Windows host and connects to the published port like any remote
SQL Server.

## Connect with SSMS

Shortcut: `task mssql:ssms` (`scripts/mssql-ssms.ps1`) finds the newest installed SSMS and opens it with the server and login
prefilled. You still type the password.

Manual steps:

1. Start the container: `task mssql:up`.
2. Open SSMS, then **Connect > Database Engine**.
3. **Server type:** Database Engine
4. **Server name:** `127.0.0.1,1433` (or `127.0.0.1,<MSSQL_PORT>` if you changed it in `.env`)
5. **Authentication:** SQL Server Authentication
6. **Login:** `sa`, **Password:** value of `MSSQL_SA_PASSWORD`
7. **Encryption:** Mandatory (default) is fine. Tick **Trust server certificate**.
   - SSMS 20: tick it on the *Login* tab.
   - SSMS 21+: the *Trust server certificate* checkbox is in the main connect dialog.
8. Click **Connect**.

If SSMS isn't installed: `winget install Microsoft.SQLServerManagementStudio`.

## Other clients

| Client | How |
|--------|-----|
| VS Code + *SQL Server (mssql)* extension | New connection > Server `127.0.0.1,1433`, SQL Login `sa`, trust server certificate. |
| sqlcmd on Windows | `sqlcmd -S 127.0.0.1,1433 -U sa -P "Dev_Passw0rd!" -C` (`-C` = trust certificate) |
| .NET connection string | `Server=127.0.0.1,1433;User Id=sa;Password=Dev_Passw0rd!;TrustServerCertificate=True` |
| JDBC | `jdbc:sqlserver://127.0.0.1:1433;user=sa;password=...;trustServerCertificate=true` |
| DBeaver / DataGrip / Rider | SQL Server driver, host `127.0.0.1`, port `1433`, enable "trust server certificate". |

Azure Data Studio was retired by Microsoft in 2026; use SSMS or the VS Code extension instead.

## Notes

- Existing containers keep their original image. Back up databases before changing from SQL Server
  2022 to 2025, then run `task mssql:down` and `task mssql:up` to recreate the container with the
  new image and the existing data volume. SQL Server upgrades the data files on first start.
- Changing `MSSQL_SA_PASSWORD` after the first start has **no effect**, because the password is
  stored in the data volume. Use `task mssql:reset` to start fresh, or change it with `ALTER LOGIN`.
- If port 1433 is taken by a local SQL Server instance, set `MSSQL_PORT=14330` in `.env` and
  `task mssql:down; task mssql:up`.
- The container is limited to 2 GB RAM (`MSSQL_MEMORY=2G`). SQL Server needs at least 2 GB.
