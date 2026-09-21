#Requires -Version 5.1
<#
    eOne.FabricWarehouse - the shipped surface of the warehouse deployment.

    WHY THIS WRAPS A SCRIPT RATHER THAN ABSORBING IT
    Deploy-EOneWarehouse.ps1 carries a lot of hard-won behaviour that has nothing to do with SQL:
    Fabric REST paging, reading the API's own error body out of a 403, the Az.Accounts / SqlServer
    MSAL binding order, WAM, tenant and workspace pickers. Pasting 800 lines of that into a .psm1
    would double-maintain it. The module defines the surface customers see - two verbs, real
    parameter help, ShouldProcess - and hands the work to the script it ships alongside.

    The split is also the reason the module can be published while that script is still being
    worked on: the contract lives here, the mechanics live there.

    INSTALL vs UPDATE
    Install builds a warehouse. Update keeps one current WITHOUT discarding what it holds, which is
    the difference that matters once a customer has loaded data:

        Install-eOneWarehouse every file, tables dropped and recreated. Refuses outright when
                                landing tables already exist; -Rebuild is the deliberate override.
        Update-eOneWarehouse creates landing tables that are MISSING, leaves existing ones and
                                their rows alone, and recreates every view.

    Views are disposable and tables are not. That is the whole of the reasoning: every file
    numbered 12 and above is DROP VIEW / CREATE VIEW and can be re-run against a loaded warehouse
    for free, while 10_tables_core.sql opens each table with DROP TABLE IF EXISTS.
#>
Set-StrictMode -Version Latest

# The deploy script and the SQL both ship inside the module. In the repo they sit one level up, so
# a developer can run the module without a packaging step first; the build copies them in.
function Get-eOneModuleFile {
    param([Parameter(Mandatory)][string] $Leaf)

    foreach ($root in @($PSScriptRoot, (Split-Path -Parent $PSScriptRoot))) {
        $candidate = Join-Path $root $Leaf
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    throw "eOne.FabricWarehouse is incomplete: '$Leaf' was not found beside the module."
}

# Every parameter the script takes, forwarded verbatim. Built from $PSBoundParameters rather than
# from the caller's variables so that an omitted parameter stays omitted - passing `-Server ''`
# and not passing -Server at all mean very different things to the script's discovery path.
function Invoke-eOneDeploy {
    param(
        [Parameter(Mandatory)][hashtable] $Bound,
        [Parameter(Mandatory)][string] $Mode
    )

    $script = Get-eOneModuleFile -Leaf 'Deploy-EOneWarehouse.ps1'
    # NOT $args: it is an automatic variable, PSAvoidAssignmentToAutomaticVariable is always
    # enabled, and the Gallery scans every published package with PSScriptAnalyzer.
    $deployArgs = @{}
    foreach ($name in $Bound.Keys) {
        # Common parameters belong to the wrapper, not to the script.
        if ($name -in 'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
            'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable',
            'OutBuffer', 'PipelineVariable', 'WhatIf', 'Confirm') { continue }
        $deployArgs[$name] = $Bound[$name]
    }
    $deployArgs['Mode'] = $Mode
    if (-not $deployArgs.ContainsKey('SqlPath')) { $deployArgs['SqlPath'] = Get-eOneModuleFile -Leaf 'sql' }

    & $script @deployArgs
}

<#
.SYNOPSIS
    Creates the eOne Integration for Business Central warehouse schema in Microsoft Fabric.

.DESCRIPTION
    Runs every SQL file in order: the three schemas, one bcRaw landing table per published eOne API
    entity set, the bc current-state views over them, and the bcModel reporting views over those.

    This is the FIRST deployment. The table DDL drops and recreates, so the command refuses to run
    against a warehouse that already holds landing tables and points you at Update-eOneWarehouse,
    which brings a loaded warehouse up to date without discarding it.

.PARAMETER Rebuild
    Deliberately discard an existing deployment and build it again from empty. Every landed row is
    lost, including the version history in bcRaw that Business Central cannot serve a second time,
    and every document that has already exited - BC deletes open documents when they post, so those
    rows exist nowhere else. Prompts for confirmation; pass -Confirm:$false to run unattended.

.PARAMETER Server
    The warehouse SQL connection string, e.g. xxxxxxxx.datawarehouse.fabric.microsoft.com. Leave it
    out and the module signs in and offers the warehouses the account can reach.

.PARAMETER Database
    The warehouse name. Required with -CreateWarehouse, which is the name to create.

.PARAMETER CreateWarehouse
    Create the Fabric Warehouse item before deploying into it. Needs Az.Accounts and Contributor on
    the workspace.

.PARAMETER WorkspaceId
    Fabric workspace GUID. Only used with -CreateWarehouse; you are asked if it is omitted.

.PARAMETER TenantId
    The Entra tenant that owns the workspace. You are asked if it is omitted and the account can
    see more than one.

.PARAMETER AccessToken
    A database.windows.net bearer token, for unattended use. Supplying one skips interactive
    sign-in entirely and never loads Az.Accounts.

.PARAMETER SqlPath
    The folder of .sql files. Defaults to the copy inside the module.

.PARAMETER QueryTimeout
    Per-batch timeout in seconds.

.PARAMETER ListOnly
    Print the files that would run, and stop.

.EXAMPLE
    Install-eOneWarehouse -CreateWarehouse -Database BCWarehouse

    Signs in, asks which tenant and workspace, creates the warehouse and deploys into it.

.EXAMPLE
    Install-eOneWarehouse -Server abc123.datawarehouse.fabric.microsoft.com -Database BCWarehouse

    Deploys to a known warehouse without signing in to Azure at all.
#>
function Install-eOneWarehouse {
    # No -Force parameter, deliberately: -Force used to mean "discard my data" on this command,
    # and reintroducing it to mean "skip the prompt" would be a trap. -Confirm:$false is the
    # bypass, and the ShouldContinue below honours it explicitly.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidShouldContinueWithoutForce', '',
        Justification = '-Confirm:$false is the documented bypass; -Rebuild is itself the opt-in.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string] $Server,
        [string] $Database,
        [switch] $CreateWarehouse,
        [string] $WorkspaceId,
        [string] $TenantId,
        [string] $AccessToken,
        [string] $SqlPath,
        [ValidateRange(30, 3600)] [int] $QueryTimeout = 600,
        [switch] $ListOnly,
        [switch] $Rebuild
    )

    $target = if ($Database) { $Database } else { 'the selected warehouse' }

    # ShouldProcess gates BOTH paths, which is what makes -WhatIf mean anything. An earlier
    # version consulted it only when -Rebuild was passed and let everything else fall through, so
    # `Install-eOneWarehouse -WhatIf` against a fresh warehouse deployed it - the one thing -WhatIf
    # exists to promise it will not do.
    #
    # ConfirmImpact is Medium, not High, so an ordinary install does not stop to ask: it creates a
    # schema and destroys nothing. -Rebuild earns its own prompt below.
    $action = if ($Rebuild) { 'DISCARD every landed row and rebuild the schema from empty' }
              else { 'deploy the warehouse schema' }

    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        # -WhatIf should say what WOULD run, not just that something would. -ListOnly prints the
        # file list and returns before it connects to anything, so this is safe under -WhatIf.
        $preview = @{} + $PSBoundParameters
        $preview['ListOnly'] = $true
        Invoke-eOneDeploy -Bound $preview -Mode 'Install'
        return
    }

    # A second, explicit confirmation for the destructive path, because ShouldProcess at Medium
    # impact will not have stopped to ask. -Confirm:$false is how an unattended rebuild opts out.
    if ($Rebuild) {
        $optedOut = $PSBoundParameters.ContainsKey('Confirm') -and -not $PSBoundParameters['Confirm']
        if (-not $optedOut -and -not $PSCmdlet.ShouldContinue(
                "Every row in [$target] will be discarded, including version history Business " +
                'Central cannot serve again. Continue?', 'Rebuild the warehouse')) {
            return
        }
    }

    Invoke-eOneDeploy -Bound $PSBoundParameters -Mode 'Install'
}

<#
.SYNOPSIS
    Brings an existing eOne warehouse up to the module's version without discarding its data.

.DESCRIPTION
    The non-destructive half of the pair, and the one to run after Update-Module:

      * every view is dropped and recreated - they hold no data, and this is how a new report, a
        changed derivation or a new data-quality check arrives;
      * landing tables that do not exist yet are created, which is how a newly shipped entity set
        arrives;
      * landing tables that DO exist are left exactly as they are, rows and all.

    What it deliberately does not do is alter a landing table whose columns have changed. A new
    column on an existing entity set is a real migration: this command reports it rather than
    quietly rebuilding the table underneath you. Deal with it explicitly, or accept the reload and
    run Install-eOneWarehouse -Rebuild.

.PARAMETER Server
    The warehouse SQL connection string. Leave it out to be offered the warehouses you can reach.

.PARAMETER Database
    The warehouse name.

.PARAMETER TenantId
    The Entra tenant that owns the workspace.

.PARAMETER AccessToken
    A database.windows.net bearer token, for unattended use.

.PARAMETER SqlPath
    The folder of .sql files. Defaults to the copy inside the module.

.PARAMETER QueryTimeout
    Per-batch timeout in seconds.

.PARAMETER ListOnly
    Print the files that would run, and stop.

.EXAMPLE
    Update-Module eOne.FabricWarehouse
    Update-eOneWarehouse -Server abc123.datawarehouse.fabric.microsoft.com -Database BCWarehouse

    The ordinary upgrade: take the new module version, then apply its views and any new tables.
#>
function Update-eOneWarehouse {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $Server,
        [string] $Database,
        [string] $TenantId,
        [string] $AccessToken,
        [string] $SqlPath,
        [ValidateRange(30, 3600)] [int] $QueryTimeout = 600,
        [switch] $ListOnly
    )

    $target = if ($Database) { $Database } else { 'the selected warehouse' }
    if (-not $PSCmdlet.ShouldProcess($target, 'recreate the views and add any missing landing tables')) { return }

    Invoke-eOneDeploy -Bound $PSBoundParameters -Mode 'Update'
}

Export-ModuleMember -Function 'Install-eOneWarehouse', 'Update-eOneWarehouse'
