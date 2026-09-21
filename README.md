# eOne Integration for Business Central — Fabric Warehouse

Deploys a Microsoft Fabric warehouse for Business Central data, ready for the eOne integration maps
to load into and for Power BI to report from.

## What it creates

Three schemas, and the split between them is the thing to know:

| Schema | Holds | You |
| --- | --- | --- |
| `bcRaw` | What the maps insert. Every version of every row, never updated | Leave alone |
| `bc` | One row per record, resolved from `bcRaw` | Query this |
| `bcModel` | Reporting, lifecycle and data-quality views, plus a calendar dimension | Point Power BI here |

The reports are already there — trial balance, AR and AP aging, customer and vendor statements,
sales and purchase analysis, inventory valuation, gross margin, open order backlog — as plain views
over the landed data. No modelling step, no DAX, nothing to load first.

## Before you start

- A **Fabric workspace on a capacity**, and Contributor on it.
- The **SqlServer** PowerShell module, 21.1 or newer:

  ```
  Install-Module SqlServer -Scope CurrentUser -AllowClobber
  ```

  `-AllowClobber` is needed on any machine with SQL Server Management Studio installed. It leaves
  SSMS alone; it just lets the newer module load beside it.

- **Business Central** with the eOne Integration app installed, and **Document Events turned on** in
  the eOne Integration Setup page. Nothing records document lifecycle until you do.
- Creating the warehouse for you also needs the **Az.Accounts** module. Deploying into one that
  already exists does not.

## Install

```
Install-Module eOne.FabricWarehouse -Scope CurrentUser
```

Create the warehouse and deploy into it:

```
Install-eOneWarehouse -CreateWarehouse -Database BCWarehouse
```

You'll be asked which tenant and which workspace. To deploy into a warehouse that already exists,
leave `-CreateWarehouse` off and you'll be offered the ones you can reach — or pass its connection
string directly:

```
Install-eOneWarehouse -Server abc123.datawarehouse.fabric.microsoft.com -Database BCWarehouse
```

To see what would run without touching anything, add `-ListOnly`.

## Update

When a new version ships:

```
Update-Module eOne.FabricWarehouse
Update-eOneWarehouse -Server abc123.datawarehouse.fabric.microsoft.com -Database BCWarehouse
```

`Update-eOneWarehouse` recreates every view and creates any new tables. **It does not touch existing
tables or the rows in them**, so you can take a new version without reloading.

`Install-eOneWarehouse` is the opposite: it builds from empty and will refuse to run against a
warehouse that already holds data. If you genuinely want to start again, `-Rebuild` does it and asks
first.

## After deploying

1. Load the data. The integration maps that fill this warehouse are supplied by eOne — **contact
   eOne to get them set up**. They insert into `bcRaw` and match on nothing: duplicates are
   expected, and the `bc` views resolve the latest version of each record.
2. Point Power BI at the **`bcModel`** schema.
3. Watch `bcModel.vw_loadHealth`. One row per feed per company: how many records, when a map last
   wrote, and how current the data is. Alert on `lastLoadedUtc` going stale — a map that quietly
   stops is the failure that costs you, because the warehouse keeps answering with old numbers.

`bcModel.vw_dataQuality` answers the other question: whether what landed hangs together. No rows
means clean.

## Authentication

Microsoft Entra only — Fabric Warehouse accepts no SQL logins. The commands sign you in
interactively by default. For unattended runs, pass `-AccessToken` with a `database.windows.net`
token.

## Support

The full deployment guide is in `docs/`. For help, contact eOne Solutions support.
