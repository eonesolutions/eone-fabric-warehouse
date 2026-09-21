@{
    RootModule        = 'eOne.FabricWarehouse.psm1'

    # The schema version, not just the module's. A customer reporting a problem gives you this
    # number and you know exactly which tables, views and derivations they are running.
    ModuleVersion     = '1.0.0'

    GUID              = 'b1f4b7c2-6a3d-4f1e-9d54-7a1c2e5f8b30'
    Author            = 'eOne Solutions'
    CompanyName       = 'eOne Solutions'
    Copyright         = '(c) eOne Solutions. All rights reserved.'

    Description       = @'
Deploys the eOne Integration for Business Central warehouse schema into Microsoft Fabric: the bcRaw
landing tables the SmartConnect maps insert into, the bc current-state views that resolve them to
one row per record, and the bcModel reporting, lifecycle and data-quality views over those.

Install-eOneWarehouse builds a warehouse. Update-eOneWarehouse brings an existing one up to date
without discarding what it holds.

Requires the SqlServer module, version 21.1 or newer:

    Install-Module SqlServer -Scope CurrentUser -AllowClobber

-AllowClobber is not optional on a machine with SSMS installed: its SQLPS module already exports
Invoke-Sqlcmd and the install fails without it. Creating the warehouse item (-CreateWarehouse) also
needs Az.Accounts.
'@

    PowerShellVersion = '5.1'

    # SqlServer is deliberately NOT in RequiredModules. Dependency resolution would install it
    # without -AllowClobber, which fails with CommandAlreadyAvailable on exactly the machines the
    # deployment targets - anything with SQL Server tooling, where SQLPS already exports
    # Invoke-Sqlcmd. The module checks for it at run time and prints the command that works.
    # Az.Accounts stays out for the same reason plus its weight: it is needed only to CREATE a
    # warehouse item, not to deploy into one.
    RequiredModules   = @()

    FunctionsToExport = @('Install-eOneWarehouse', 'Update-eOneWarehouse')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # No FileList. Deploy-EOneWarehouse.ps1 and sql\ are staged into this folder by the packaging
    # step and live one level up in the repo, so listing them here makes Test-ModuleManifest fail
    # during development for files that are correct at publish time. FileList is informational
    # only; it is not worth failing the manifest test over.

    PrivateData       = @{
        PSData = @{
            # No Prerelease line: this is 1.0.0 proper. The two previews were installed from the
            # real Gallery and driven against a real warehouse before it was promoted, which is
            # what the preview versions were for. Gallery versions are immutable, so a fix ships
            # as 1.0.1 rather than as a replacement.

            Tags         = @('Fabric', 'MicrosoftFabric', 'BusinessCentral', 'Dynamics365',
                             'DataWarehouse', 'eOne', 'SmartConnect', 'ETL')
            ProjectUri   = 'https://github.com/eonesolutions/eone-fabric-warehouse'
            # Both taken from the AppSource listing (appsource/Core/listing.md) so the Gallery,
            # AppSource and app.json cannot describe the product three different ways.
            LicenseUri   = 'https://www.eonesolutions.com/end-user-license-agreement/'
            IconUri      = 'https://raw.githubusercontent.com/eonesolutions/eone-fabric-warehouse/main/icon.png'
            ReleaseNotes = @'
1.0.0
  First release.

  - Install-eOneWarehouse deploys the schema: the bcRaw landing tables the SmartConnect maps
    insert into, the bc current-state views that resolve them to one row per record, and the
    bcModel reporting, lifecycle and data-quality views over those.
  - Update-eOneWarehouse recreates every view and adds any missing landing table, leaving existing
    tables and their rows untouched. A first install refuses to run over an existing deployment
    and says so; Install-eOneWarehouse -Rebuild is the deliberate, confirmed way to start again.
  - -CreateWarehouse creates the Fabric warehouse item first, and signs in a second time by itself
    when the second audience needs it.
  - Sign-in checks the session before asking for credentials. A window where another module has
    already bound the assemblies MSAL needs cannot authenticate at all, and now says which module
    and what to do instead of failing on a missing type.
'@
        }
    }
}
