#Requires -Version 5.1
<#
.SYNOPSIS
    Creates the eOne Integration for Business Central warehouse schema in Microsoft Fabric.

.DESCRIPTION
    Runs the SQL in .\sql in filename order against a Fabric Warehouse: three
    schemas, one landing table per published eOne API entity set, the
    current-state views over them, and the reporting and lifecycle views over
    those.

        bcRaw    what the maps insert into - every version, never updated
        bc       one row per record, resolved from bcRaw on read
        bcModel  the views Power BI points at, plus the calendar dimension

    There are no control tables and no stored procedures. The warehouse holds
    data and views; everything that MOVES data - cursors, the load plan, run
    history - belongs to the SmartConnect integration that owns the schedule.
    Document exits are not applied by anything: bc derives them from the event
    feed when a view is read.

    Optionally creates the Fabric Warehouse item first (-CreateWarehouse), since
    Fabric has no T-SQL CREATE DATABASE -- a warehouse is a workspace item.

    Authentication is Microsoft Entra only; Fabric Warehouse does not accept SQL
    logins. By default the script signs you in interactively.

.PARAMETER Server
    The warehouse SQL connection string, e.g.
    xxxxxxxx.datawarehouse.fabric.microsoft.com
    Found in Fabric under the warehouse's Settings > SQL connection string.

    Optional. Leave it out and the script signs in, asks which tenant, workspace and warehouse,
    and reads the connection string itself - no portal visit. Supplying it skips all of that, and
    is the only path that never loads Az.Accounts.

    Not needed with -CreateWarehouse either: the new warehouse reports its own.

.PARAMETER Database
    The warehouse name. With -CreateWarehouse, the name to create; otherwise the one to deploy to.

    Optional when the script is choosing a warehouse for you - it takes the name from whichever
    you pick. Supplying it then narrows the list to that name.

.PARAMETER CreateWarehouse
    Create the Fabric Warehouse item before deploying into it, in -WorkspaceId or in a
    workspace chosen from a list. Requires the Az.Accounts module and Contributor on the
    workspace.

.PARAMETER WorkspaceId
    Fabric workspace GUID. Only used with -CreateWarehouse.

    Leave it out and the script asks, listing the workspaces the account can reach. Workspaces
    with no Fabric capacity are shown but marked, because they cannot hold a warehouse; personal
    workspaces are not offered at all, for the same reason.

.PARAMETER Mode
    Install (default) runs every file: the table DDL drops and recreates, so it
    refuses to run against a warehouse that already holds landing tables.

    Update is the non-destructive path. It recreates every view, creates landing
    tables that do not exist yet, and leaves existing tables and their rows
    exactly as they are. This is how you take a new version of the schema
    without reloading.

.PARAMETER Rebuild
    Deliberately discard an existing deployment and build it again from empty.
    Every landed row goes, including the version history in bcRaw that Business
    Central cannot serve a second time, and every document that has already
    exited - BC deletes open documents when they post, so those rows exist
    nowhere else. Only meaningful with -Mode Install.

.PARAMETER ListOnly
    Print the files that would run, and stop.

.PARAMETER TenantId
    The Entra tenant that owns the Fabric workspace. Only used with -CreateWarehouse.

    Leave it out and the script asks. After signing in it lists the tenants the account can see
    and prompts for one - tenants, not Azure subscriptions, because a Fabric workspace does not
    live in a subscription. An account that can see only one tenant is not asked.

.PARAMETER AccessToken
    A database.windows.net bearer token, for unattended use. Supply one and the script does no
    interactive sign-in and never loads Az.Accounts:

        Connect-AzAccount -ServicePrincipal -Tenant <t> -ApplicationId <a> -CertificateThumbprint <c>
        $secure = (Get-AzAccessToken -ResourceUrl 'https://database.windows.net/').Token
        $t = (New-Object System.Net.NetworkCredential('', $secure)).Password
        .\Deploy-EOneWarehouse.ps1 -Server ... -Database ... -AccessToken $t

    The unwrap matters: Az.Accounts 5.x returns a SecureString, and passing that straight through
    sends the text "System.Security.SecureString" as the token.

.EXAMPLE
    .\Deploy-EOneWarehouse.ps1

    Signs in and asks which tenant, workspace and warehouse to deploy to.

.EXAMPLE
    .\Deploy-EOneWarehouse.ps1 -Server abc123.datawarehouse.fabric.microsoft.com -Database BCWarehouse

    Deploys straight to a known warehouse, without signing in to Azure at all.

.EXAMPLE
    .\Deploy-EOneWarehouse.ps1 -CreateWarehouse -Database BCWarehouse

    Asks which tenant and which workspace, then creates the warehouse and deploys into it.

.EXAMPLE
    .\Deploy-EOneWarehouse.ps1 -CreateWarehouse -WorkspaceId 8f2c... -TenantId 1a2b... -Database BCWarehouse

    The same, asking nothing.

.NOTES
    Requires the SqlServer PowerShell module, version 21.1 or newer:

        Install-Module SqlServer -Scope CurrentUser -AllowClobber

    -AllowClobber is not optional on a machine with SQL Server tooling installed. The SQLPS
    module that ships with SSMS already exports Invoke-Sqlcmd, so the install fails with
    CommandAlreadyAvailable without it. SQLPS is left in place; this script imports SqlServer
    explicitly, so the newer cmdlets win for its own session.

    21.1 is the floor because this script passes -AccessToken to Invoke-Sqlcmd, which SQLPS and
    older SqlServer builds do not accept.

    -CreateWarehouse additionally requires Az.Accounts:

        Install-Module Az.Accounts -Scope CurrentUser

    On Windows PowerShell 5.1, module import ORDER matters when both are loaded. Only one
    Microsoft.Identity.Client can bind per process: SqlServer ships 4.65 and Az.Accounts needs
    4.84, so importing SqlServer first pins the old one and Connect-AzAccount then fails with

        Could not load type 'Microsoft.Identity.Client.IMsalSFHttpClientFactory'

    which reads like an authentication problem and is not one. This script imports Az FIRST when
    it needs it at all, and the default path does not load Az, so the clash cannot arise.

    Azure PowerShell is a token source here and nothing more. A Fabric workspace is not an Azure
    subscription and none is required, so the sign-in skips context population rather than asking
    which subscription to make current - a question with no correct answer here, and one that
    fails outright for an account with no Azure subscriptions at all.

    Tokens come back as a SecureString in Az.Accounts 5.x, always - the -AsSecureString switch is
    documented as no longer used. Interpolating one into an Authorization header sends the literal
    text "System.Security.SecureString", and the service rejects it as an invalid token, which
    looks like an expired credential rather than a type mistake. Get-PlainToken unwraps it and
    still accepts the plain string older versions return.

    Sign-in itself also needs help on Windows. Az 5.x uses WAM (the Windows Web Account Manager)
    by default, and WAM wants a parent window handle that a console host does not supply -- "A
    window handle must be configured". The script disables WAM for its own process only, leaving
    the operator's saved Az configuration untouched, and falls back to device code if the browser
    still cannot be used.
#>
[CmdletBinding()]
param(
    [string]   $Server,
    [string]   $Database,
    [switch]   $CreateWarehouse,
    [string]   $WorkspaceId,
    [switch]   $Rebuild,
    [ValidateSet('Install', 'Update')]
    [string]   $Mode = 'Install',
    [switch]   $ListOnly,
    [string]   $AccessToken,
    [string]   $TenantId,
    [string]   $SqlPath = (Join-Path $PSScriptRoot 'sql'),
    [int]      $QueryTimeout = 600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Declared up front because StrictMode makes reading an unset variable an error, and the connect
# section tests it whether or not -CreateWarehouse ran.
$azToken = $null

# Checked here rather than where it is used. -CreateWarehouse needs a name to create, and finding
# that out after the operator has signed in, chosen a tenant and chosen a workspace is a waste of
# their time for something knowable before anything happens.
if ($CreateWarehouse -and -not $Database) {
    throw '-Database is required with -CreateWarehouse: it is the name of the warehouse to create.'
}

function Write-Step { param([string]$Text) Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Note { param([string]$Text) Write-Host "    $Text" -ForegroundColor DarkGray }

# "Contoso (contoso.onmicrosoft.com)  1234abcd-..." - enough to recognise without being a wall.
function Format-Tenant {
    param($Tenant)
    $name   = if ($Tenant.Name) { $Tenant.Name } else { '(unnamed)' }
    $domain = if ($Tenant.DefaultDomain) { " ($($Tenant.DefaultDomain))" } else { '' }
    "{0}{1}  {2}" -f $name, $domain, $Tenant.Id
}

# "Finance Analytics  8f2c...   (no capacity)"
function Format-Workspace {
    param($Workspace)
    $name = if ($Workspace.displayName) { $Workspace.displayName } else { '(unnamed)' }

    # ABSENT is not EMPTY. GET /v1/workspaces does not always return capacityId, and treating a
    # missing field as "no capacity" labelled every workspace in the list as unable to host a
    # warehouse - including the one that was already hosting the warehouse this script had just
    # created in it. Only say it when the field is present and blank.
    $note = ''
    if ($Workspace.PSObject.Properties['capacityId'] -and
        [string]::IsNullOrWhiteSpace($Workspace.capacityId)) {
        $note = '   (no capacity assigned)'
    }
    if ($Workspace.PSObject.Properties['type'] -and $Workspace.type -eq 'Personal') {
        $note = '   (personal workspace - cannot host a warehouse)'
    }
    "{0}  {1}{2}" -f $name, $Workspace.id, $note
}

# Az.Accounts 5.x ALWAYS returns the token as a SecureString - its own help for -AsSecureString
# reads "The parameter is no longer used ... the output token is a SecureString" - and its
# OutputType is PSSecureAccessToken. Interpolating that into a header sends the literal text
# "System.Security.SecureString" and the service answers InvalidToken, which reads like an
# expired or wrong-tenant token and is neither.
#
# Older Az returns a plain string, so both shapes are handled rather than assuming a version.
function Get-PlainToken {
    param(
        [Parameter(Mandatory)] [string] $ResourceUrl,
        [string] $Tenant
    )
    $tokenArgs = @{ ResourceUrl = $ResourceUrl }
    if ($Tenant) { $tokenArgs['TenantId'] = $Tenant }

    $token = (Get-AzAccessToken @tokenArgs -WarningAction SilentlyContinue).Token
    if ($token -is [System.Security.SecureString]) {
        # NetworkCredential does the unwrap without a manual Marshal free, and works on both
        # Windows PowerShell 5.1 and PowerShell 7.
        (New-Object System.Net.NetworkCredential('', $token)).Password
    }
    else {
        $token
    }
}

# "BCWarehouse  abc123.datawarehouse.fabric.microsoft.com"
function Format-Warehouse {
    param($Warehouse)
    $name = if ($Warehouse.displayName) { $Warehouse.displayName } else { '(unnamed)' }
    $conn = if ($Warehouse.PSObject.Properties['properties'] -and $Warehouse.properties -and
                $Warehouse.properties.PSObject.Properties['connectionString']) {
                "  $($Warehouse.properties.connectionString)"
            } else { '' }
    "{0}{1}" -f $name, $conn
}

# Fabric REST, with the two things the raw cmdlets do not do here.
#
# PAGING. The list endpoints return a page plus a continuationToken, and a workspace list that
# stops at the first page is worse than no list: it silently hides the workspace the operator is
# looking for and then says "1 workspace available", which reads as fact.
#
# ERRORS. Invoke-WebRequest on Windows PowerShell 5.1 throws away the response body, so a Fabric
# refusal arrives as "(403) Forbidden" and nothing else - while the body it discarded held an
# errorCode and a sentence saying exactly what was wrong.
function Invoke-FabricList {
    param([Parameter(Mandatory)][string] $Uri, [Parameter(Mandatory)][hashtable] $Headers)

    $items = @()
    $next = $Uri
    $pages = 0
    while ($next) {
        $page = Invoke-FabricApi -Uri $next -Headers $Headers -Method Get
        if ($page.PSObject.Properties['value']) { $items += @($page.value) }
        $next = if ($page.PSObject.Properties['continuationUri']) { $page.continuationUri } else { $null }
        $pages++
        if ($pages -gt 50) { throw "Refusing to follow more than 50 pages from $Uri." }
    }
    # `,` so PowerShell does not unroll a one-element array on the way out. Without it a single
    # workspace returns as a bare object and $spaces.Count throws under StrictMode - which is the
    # common case, not an edge one.
    #
    # ASSIGN the result; do not pipe this function straight into Where-Object. The wrapper array is
    # what the pipeline enumerates, so a downstream $_ receives the INNER array rather than each
    # item, and $_.displayName then fails under StrictMode. Assigning unrolls the wrapper once and
    # gives back the real list.
    return ,@($items)
}

# The body of a failed response, as a sentence. Separate from the caller so it can be tested
# against a fake response instead of against a live 403.
function Read-FabricError {
    param($Response)
    if (-not $Response) { return '' }
    $raw = ''
    try {
        $stream = $Response.GetResponseStream()
        if (-not $stream) { return '' }
        $reader = New-Object System.IO.StreamReader($stream)
        $raw = $reader.ReadToEnd()
        $reader.Close()
    }
    catch { return '' }

    if (-not $raw) { return '' }
    try {
        $j = $raw | ConvertFrom-Json
        # Fabric nests it as {error:{code,message}} on some routes and flattens it on others.
        $node = if ($j.PSObject.Properties['error']) { $j.error } else { $j }
        $code = ''
        foreach ($n in 'errorCode', 'code') {
            if ($node.PSObject.Properties[$n] -and $node.$n) { $code = $node.$n; break }
        }
        $msg = ''
        foreach ($n in 'message', 'errorMessage') {
            if ($node.PSObject.Properties[$n] -and $node.$n) { $msg = $node.$n; break }
        }
        if ($code -and $msg) { return "$code - $msg" }
        if ($code) { return $code }
        if ($msg) { return $msg }
        return $raw.Trim()
    }
    catch { return $raw.Trim() }
}

function Invoke-FabricApi {
    param(
        [Parameter(Mandatory)][string] $Uri,
        [Parameter(Mandatory)][hashtable] $Headers,
        [string] $Method = 'Get',
        [string] $Body
    )
    $splat = @{ Uri = $Uri; Headers = $Headers; Method = $Method; UseBasicParsing = $true }
    if ($Body) { $splat['Body'] = $Body }

    try {
        $resp = Invoke-WebRequest @splat
        if ($resp.StatusCode -eq 202) { return [pscustomobject]@{ _accepted = $true } }
        if (-not $resp.Content) { return $null }
        return $resp.Content | ConvertFrom-Json
    }
    catch {
        $r = $_.Exception.Response
        $status = $null
        # Best effort: some failures carry no usable StatusCode, and the message below is built
        # from whatever IS available. Verbose rather than empty so the swallow is visible.
        if ($r) { try { $status = [int]$r.StatusCode } catch { Write-Verbose "No status code on the response: $($_.Exception.Message)" } }
        $detail = Read-FabricError $r
        $hint = ''
        if ($status -eq 403) {
            $hint = @'

A 403 on this call is usually one of:
  - the signing-in account is a Viewer on the workspace, not a Contributor/Member/Admin
  - the workspace is not on a Fabric capacity, so it cannot hold a warehouse
  - a tenant setting blocks service-principal or API access to Fabric

Reading worked, so the token and the tenant are fine; it is this workspace or this operation.
'@
        }
        throw ("Fabric API $Method $Uri failed" +
               $(if ($status) { " with $status" } else { '' }) +
               $(if ($detail) { ": $detail" } else { '.' }) + $hint)
    }
}

# Ask which one. Shared by the tenant, workspace and warehouse pickers so they behave identically: no
# question when there is only one answer, a named error when the host cannot prompt, and the same
# validation on the way in.
function Select-FromList {
    param(
        # AllowEmptyCollection, because Mandatory rejects an empty array during binding - before
        # the count check below runs - and the operator would get PowerShell's binding error
        # instead of the message explaining that they have no workspaces.
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Items,
        [Parameter(Mandatory)] [string]      $Title,
        [Parameter(Mandatory)] [scriptblock] $Label,
        [Parameter(Mandatory)] [string]      $Parameter,
        [string] $NoneMessage = 'Nothing to choose from.'
    )

    if ($Items.Count -eq 0) { throw $NoneMessage }
    if ($Items.Count -eq 1) { return $Items[0] }

    Write-Host ''
    Write-Step $Title
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host ("      [{0}] {1}" -f ($i + 1), (& $Label $Items[$i]))
    }
    Write-Host ''

    $pick = 0
    try {
        do {
            $answer = Read-Host "Select (1-$($Items.Count))"
            $valid = [int]::TryParse($answer, [ref]$pick) -and
                     $pick -ge 1 -and $pick -le $Items.Count
            if (-not $valid) { Write-Warning "Enter a number from 1 to $($Items.Count)." }
        } while (-not $valid)
    }
    catch {
        # Read-Host throws in a non-interactive host. Name the options so the operator can pass
        # one, rather than only reporting that a prompt failed.
        $list = ($Items | ForEach-Object { "    $(& $Label $_)" }) -join [Environment]::NewLine
        throw @"
$($Items.Count) options are available and this session cannot prompt.
Re-run with $Parameter <id>, choosing from:

$list
"@
    }

    return $Items[$pick - 1]
}

# ---------------------------------------------------------------------------
# 1. Which files, in which order
# ---------------------------------------------------------------------------
if (-not (Test-Path $SqlPath)) { throw "SQL folder not found: $SqlPath" }

$files = Get-ChildItem -Path $SqlPath -Filter '*.sql' | Sort-Object Name
if (-not $files) { throw "No .sql files in $SqlPath" }

if ($ListOnly) {
    # -Database is optional now, so do not print "against []" when it was not given.
    $against = if ($Database) { " against [$Database]" } else { '' }
    Write-Step "$Mode would run $($files.Count) file(s)${against}:"

    # Say what each file would DO, not just that it would run. In Update the same list means
    # something different file by file, and a plain list of names implies a rebuild it will not do.
    foreach ($f in $files) {
        $n = if ($f.Name -match '^(\d+)_') { [int]$Matches[1] } else { 99 }
        # Ordered narrowest first. An earlier draft tested -ge 10 before the view range and
        # labelled every view file as a table, which is the opposite of what Update does to them.
        $what = if ($Mode -ne 'Update') { '' }
                elseif ($n -lt 10) { '   schemas: created only if missing' }
                elseif ($n -eq 10) { '   tables: only the ones that do not exist yet' }
                elseif ($n -eq 11) { '   calendar: only if dimDate is missing' }
                else               { '   views: dropped and recreated' }
        Write-Note ("{0,-34}{1}" -f $f.Name, $what)
    }
    if ($Mode -eq 'Update') {
        Write-Note ''
        Write-Note 'Views are dropped and recreated. No landing table is dropped and no row is lost.'
    }
    return
}

# ---------------------------------------------------------------------------
# 2. Prerequisites
# ---------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    throw @'
The SqlServer PowerShell module is required.

    Install-Module SqlServer -Scope CurrentUser -AllowClobber

-AllowClobber is needed when SQL Server tooling (SSMS) is installed: its SQLPS module already
exports Invoke-Sqlcmd, and the install fails without it. SQLPS is not removed or changed.
'@
}

# NOTE: SqlServer is deliberately NOT imported here. Importing it loads Microsoft.Identity.Client
# 4.65, and on Windows PowerShell 5.1 that is the version the whole process is then stuck with --
# which breaks Az.Accounts, and -CreateWarehouse needs Az. The import happens in step 4, after any
# Az work is done. Checking availability is free; importing is what binds the assembly.

# ---------------------------------------------------------------------------
# 3. Create the Fabric Warehouse item, if asked
#
# Fabric Warehouse has no T-SQL CREATE DATABASE. The warehouse is an item in a
# Fabric workspace, created through the portal or the Fabric REST API -- this is
# the REST route so the whole thing is one command.
# ---------------------------------------------------------------------------
# Fabric is consulted when creating a warehouse, and also when the operator has not said which
# existing one to deploy to. -Server short-circuits both: give a connection string and the script
# never signs in to Azure at all.
$discover = -not $Server -and -not $CreateWarehouse

if ($CreateWarehouse -or $discover) {
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        throw "-CreateWarehouse needs the Az.Accounts module. Run: Install-Module Az.Accounts -Scope CurrentUser"
    }
    # Az BEFORE SqlServer, deliberately. See the notes at the top: on Windows PowerShell 5.1 the
    # first Microsoft.Identity.Client to load wins for the whole process, and SqlServer ships an
    # older one than Az.Accounts can work with.
    #
    # Ordering inside this script is not enough on its own. Module state lives as long as the
    # session, so an earlier run -- or anything else that touched SqlServer or SQLPS in this
    # window -- has already put the old resolver in place, and no import order here can undo it.
    #
    # Test for the loaded MODULE, not for a loaded assembly. Importing SqlServer loads no
    # Microsoft.Identity.Client at all; it registers a resolver, and the old 4.65 is pulled in
    # lazily at the moment Az asks for MSAL. Measured:
    #
    #     Az alone          -> 4.84            works
    #     Az then SqlServer -> 4.84            works
    #     SqlServer then Az -> 4.65 AND 4.84   Az binds 4.65 and fails
    #
    # So an assembly check before the Az import always finds nothing, and never fires.
    # Measured BEFORE Az is imported, because importing it is what changes the answer. Loading
    # SqlServer only matters if it got in FIRST - if Az.Accounts is already loaded then its own
    # Microsoft.Identity.Client already won, and the session is fine.
    $sqlFirst = [bool](Get-Module -Name SqlServer, SQLPS) -and -not (Get-Module -Name Az.Accounts)

    Import-Module Az.Accounts -ErrorAction Stop

    if (-not (Get-AzContext)) {
        # Only now does the import order matter. An existing context needs no sign-in, so a
        # session that already authenticated - the usual reason to be re-running this - is not
        # turned away for a problem it does not have.
        #
        # Belt and braces: an old Microsoft.Identity.Client already bound is the same trouble even
        # if Az happens to be loaded, because it means Az lost the race earlier.
        $oldMsalBound = @([AppDomain]::CurrentDomain.GetAssemblies() |
                          Where-Object { $_.GetName().Name -eq 'Microsoft.Identity.Client' -and
                                         $_.GetName().Version -lt [version]'4.84' })
        if ($sqlFirst -or $oldMsalBound.Count -gt 0) {
            throw @'
This PowerShell session loaded the SqlServer (or SQLPS) module before Azure PowerShell, so
Connect-AzAccount cannot work in it.

Nothing is wrong with your browser or your account. That module makes an older
Microsoft.Identity.Client available to the process, Azure PowerShell binds to it, and the failure
surfaces as a missing type plus a suggestion to try -DeviceCode. -DeviceCode fails the same way.

It cannot be undone in this session -- Remove-Module does not unbind it.

    Open a NEW PowerShell window and run this command again.

Only the Azure sign-in is affected. Against a warehouse that already exists, pass -Server with its
connection string: that path never loads Az, and works even in this session.
'@
        }

        # Azure PowerShell 5.x signs in through WAM (the Windows Web Account Manager) by default,
        # and WAM needs a parent window handle that a plain console host does not supply:
        #
        #     A window handle must be configured. See https://aka.ms/msal-net-wam
        #
        # Process scope, so the operator's saved Az configuration is left exactly as it was.
        try {
            Update-AzConfig -EnableLoginByWam $false -Scope Process -WarningAction SilentlyContinue |
                Out-Null
        } catch {
            Write-Note 'Could not disable WAM for this process; continuing.'
        }

        # A Fabric workspace is NOT an Azure subscription, and nothing here needs one. Azure
        # PowerShell is used only as a token source, for two audiences: api.fabric.microsoft.com
        # to create the warehouse, and database.windows.net to run the SQL.
        #
        # -SkipContextPopulation stops Az enumerating subscriptions and asking which to make
        # current, which is a question with no correct answer here and which fails outright on an
        # account that has no Azure subscriptions at all. LoginExperienceV2 is the setting behind
        # the interactive picker; off for this process only.
        try {
            Update-AzConfig -LoginExperienceV2 Off -Scope Process -WarningAction SilentlyContinue |
                Out-Null
        } catch {
            # Older Az.Accounts has no LoginExperienceV2 setting. Sign-in still works; it just asks
            # a subscription question this script does not need an answer to.
            Write-Verbose "Could not disable the interactive login experience: $($_.Exception.Message)"
        }

        $connect = @{ SkipContextPopulation = $true; ErrorAction = 'Stop' }
        if ($TenantId) { $connect['Tenant'] = $TenantId }

        try {
            Connect-AzAccount @connect | Out-Null
        }
        catch {
            # Device code works where neither WAM nor a local browser can: a remote session, a
            # server core box, or a host that cannot hand MSAL a window.
            Write-Note 'Browser sign-in was not possible. Falling back to device code.'
            Write-Note 'Open the URL below and enter the code shown.'
            Connect-AzAccount @connect -UseDeviceAuthentication | Out-Null
        }
    }

    # Which TENANT, which is the question that actually has an answer here. Azure's own picker
    # offers subscriptions, and a Fabric workspace does not live in one.
    #
    # Skipped entirely when -TenantId was supplied, and when the account can only see one tenant,
    # so the common single-tenant case is silent.
    if (-not $TenantId) {
        $tenants = @()
        try { $tenants = @(Get-AzTenant -ErrorAction Stop) }
        catch { Write-Note 'Could not list tenants; continuing with the signed-in one.' }

        if ($tenants.Count -ge 1) {
            $chosen = Select-FromList -Items $tenants `
                -Title 'Which tenant holds the Fabric workspace?' `
                -Label { param($t) Format-Tenant $t } `
                -Parameter '-TenantId'
            $TenantId = $chosen.Id
            Write-Note "Tenant: $(Format-Tenant $chosen)"
        }

        # The sign-in landed in whichever tenant was default. If that is not the chosen one, sign
        # in again against it; a cached account usually makes this silent.
        $currentTenant = (Get-AzContext).Tenant.Id
        if ($TenantId -and $currentTenant -and $TenantId -ne $currentTenant) {
            $connect['Tenant'] = $TenantId
            Connect-AzAccount @connect | Out-Null
        }
    }

    $fabricToken = Get-PlainToken -ResourceUrl 'https://api.fabric.microsoft.com' -Tenant $TenantId
    $headers = @{ Authorization = "Bearer $fabricToken"; 'Content-Type' = 'application/json' }

    # Which workspace? Same treatment as the tenant: ask rather than demand a GUID the operator
    # would otherwise go and copy out of the portal.
    if (-not $WorkspaceId) {
        $spaces = Invoke-FabricList -Uri 'https://api.fabric.microsoft.com/v1/workspaces' `
                                    -Headers $headers

        # Personal workspaces cannot hold a Fabric Warehouse, so they are dropped - but say how
        # many, because "the workspace I expected is not in this list" is otherwise unexplainable
        # from the outside, and the cause might equally be the wrong tenant or a missing role.
        $allCount = $spaces.Count
        $spaces = @($spaces | Where-Object { $_.type -ne 'Personal' } |
                              Sort-Object -Property displayName)
        if ($allCount -ne $spaces.Count) {
            Write-Note "$($allCount - $spaces.Count) personal workspace(s) not shown: they cannot hold a warehouse."
        }
        Write-Note "$($spaces.Count) workspace(s) available to this account in this tenant."

        $chosen = Select-FromList -Items $spaces `
            -Title 'Which workspace should hold the warehouse?' `
            -Label { param($w) Format-Workspace $w } `
            -Parameter '-WorkspaceId' `
            -NoneMessage @'
This account can see no Fabric workspaces that could hold a warehouse.

Create one in the Fabric portal, on a capacity, and make sure the signing-in account is a
workspace Contributor. If you expected to see one, check you picked the right tenant.
'@
        $WorkspaceId = $chosen.id
        Write-Note "Workspace: $(Format-Workspace $chosen)"
    }

    $listUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/warehouses"

    # Deploying to a warehouse that already exists, and the operator did not say which. Ask,
    # rather than making them open the portal to copy a connection string.
    # Set when the create path should run: either asked for up front, or offered below and taken.
    $doCreate = [bool]$CreateWarehouse

    if ($discover) {
        $existingWarehouses = Invoke-FabricList -Uri $listUri -Headers $headers
        if ($Database) {
            $existingWarehouses = @($existingWarehouses | Where-Object { $_.displayName -eq $Database })
        }

        if ($existingWarehouses.Count -eq 0) {
            # An empty workspace is a normal state, not an error. Offer the obvious next step
            # rather than stopping to say "run the same command again with a different switch" -
            # the operator is already here, signed in, with a workspace chosen.
            Write-Host ''
            if ($Database) {
                Write-Step "No warehouse called '$Database' here, so one will be created."
            }
            else {
                Write-Step 'This workspace has no warehouses yet, so one will be created.'
            }
            $suggested = if ($Database) { $Database } else { 'BCWarehouse' }
            Write-Host ''

            # One question, and one way to accept the default. The first version of this asked
            # "Create one? Name [BCWarehouse], or Ctrl+C to stop", which is a yes/no question and
            # a free-text question at once, and left it unclear what typing anything would do.
            try {
                $answer = Read-Host "    Warehouse name (Enter for '$suggested')"
            }
            catch {
                throw @"
This workspace has no warehouse to deploy to, and this session cannot prompt.

Re-run with -CreateWarehouse -Database <name> to create one, or pass -Server with the connection
string of a warehouse that already exists.
"@
            }

            if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $suggested }
            $Database = $answer.Trim()
            $doCreate = $true
        }
        else {
            $chosenWh = Select-FromList -Items @($existingWarehouses | Sort-Object -Property displayName) `
                -Title 'Which warehouse should this be deployed to?' `
                -Label { param($w) Format-Warehouse $w } `
                -Parameter '-Server'
            $Database = $chosenWh.displayName
            Write-Note "Warehouse: $(Format-Warehouse $chosenWh)"
            $warehouse = $chosenWh
        }
    }

    if ($doCreate) {
        Write-Step "Creating Fabric Warehouse '$Database' in workspace $WorkspaceId"

        # First match, not all matches: Fabric allows two items with the same display name, and an
        # array here would put "$($existing.id)" in the message and an array into $warehouse.
        $found = Invoke-FabricList -Uri $listUri -Headers $headers
        $existing = @($found | Where-Object { $_.displayName -eq $Database }) | Select-Object -First 1

        if ($existing) {
            Write-Note "Warehouse already exists (id $($existing.id)) -- using it."
            $warehouse = $existing
        }
        else {
            $body = @{ displayName = $Database; description = 'Business Central data via the eOne Integration APIs' } | ConvertTo-Json
            $resp = Invoke-FabricApi -Uri $listUri -Headers $headers -Method Post -Body $body
            if ($resp -and $resp.PSObject.Properties['_accepted']) {
                # Long-running operation: poll until the item exists.
                Write-Note 'Provisioning (this takes up to a minute)...'
                $deadline = (Get-Date).AddMinutes(5)
                do {
                    Start-Sleep -Seconds 10
                    $polled = Invoke-FabricList -Uri $listUri -Headers $headers
                    $warehouse = @($polled | Where-Object { $_.displayName -eq $Database }) |
                                 Select-Object -First 1
                } while (-not $warehouse -and (Get-Date) -lt $deadline)
                if (-not $warehouse) { throw "Timed out waiting for warehouse '$Database' to be provisioned." }
            }
            else {
                $warehouse = $resp
            }
            Write-Note "Created (id $($warehouse.id))."
        }
    }
    if (-not $Server) {
        $detail = Invoke-FabricApi -Uri "$listUri/$($warehouse.id)" -Headers $headers
        $Server = $detail.properties.connectionString
        if (-not $Server) { throw "Could not read the SQL connection string. Copy it from Fabric and re-run with -Server." }
        Write-Note "SQL endpoint: $Server"
    }

    # Reuse this session for the SQL connection rather than signing in twice.
    $azToken = Get-PlainToken -ResourceUrl 'https://database.windows.net/' -Tenant $TenantId
}

if (-not $Server) {
    throw @'
Nothing identifies the warehouse to deploy to.

Pass -Server with its SQL connection string, or leave -Server off and the script will sign in and
offer the warehouses you can reach. -CreateWarehouse makes a new one.
'@
}
if (-not $Database) { throw '-Database is required: the warehouse name.' }

# ---------------------------------------------------------------------------
# 4. Connect
#
# SqlServer is imported HERE, not in step 2, so that anything needing Az.Accounts has already
# loaded its own Microsoft.Identity.Client. See the notes at the top of this file.
# ---------------------------------------------------------------------------
Import-Module SqlServer -ErrorAction Stop

# -AccessToken needs SqlServer 21.1+. An older build imports fine and then fails on a parameter
# that does not exist, which reads like an auth problem rather than a module problem.
$sqlModule = (Get-Module SqlServer).Version
if ($sqlModule -lt [version]'21.1') {
    throw "SqlServer $sqlModule is too old; 21.1 or newer is required. Run: Install-Module SqlServer -Scope CurrentUser -AllowClobber -Force"
}

$sqlArgs = @{
    QueryTimeout = $QueryTimeout
    ErrorAction  = 'Stop'
}

# Three ways in, in order of preference. The default deliberately does NOT touch Az.Accounts:
# loading it alongside SqlServer on Windows PowerShell 5.1 is what produces the MSAL
# missing-type error described in the notes at the top of this file.
#
# Invoke-Sqlcmd has no -Authentication parameter (checked against SqlServer 22.4.5.1), so the
# interactive Entra sign-in goes through a connection string, which is SqlClient's own MSAL and
# needs nothing else installed.
if ($AccessToken) {
    Write-Note 'Authenticating with the supplied access token.'
    $sqlArgs['ServerInstance'] = $Server
    $sqlArgs['Database']       = $Database
    $sqlArgs['AccessToken']    = $AccessToken
}
elseif ($azToken) {
    # -CreateWarehouse ran, so Az is already loaded and a token is already in hand.
    Write-Note 'Authenticating with the Azure session used to create the warehouse.'
    $sqlArgs['ServerInstance'] = $Server
    $sqlArgs['Database']       = $Database
    $sqlArgs['AccessToken']    = $azToken
}
else {
    Write-Note 'Signing in interactively through Microsoft Entra.'
    $sqlArgs['ConnectionString'] =
        "Server=$Server;Database=$Database;Authentication=Active Directory Interactive;" +
        "Encrypt=True;TrustServerCertificate=False;Connect Timeout=60;"
}

Write-Step "Connecting to $Server / $Database"
$probe = Invoke-Sqlcmd @sqlArgs -Query "SELECT DB_NAME() AS db, SUSER_SNAME() AS [user];"
Write-Note "Connected as $($probe.user)."

# ---------------------------------------------------------------------------
# 5. What is already there, and which of it may be touched
#
# 10_tables_core.sql opens every table with DROP TABLE IF EXISTS, so Install is
# destructive by construction. Two things make that worse than it sounds:
#
#   - bcRaw holds every VERSION of every row, and BC cannot re-serve history.
#     A reload rebuilds current state; the history is gone.
#   - Open documents are deleted by Business Central when they post, so a row
#     that already exited is not re-readable from the source at all.
#
# Which is why Update exists, and why it is the path an installed customer
# should ever be on. The file numbering already draws the line: 01-11 create
# tables, everything from 12 up is DROP VIEW / CREATE VIEW and costs nothing to
# re-run. Update runs all of the second group, and from the first group only the
# tables that are missing.
#
# The count looks in bcRaw, because that is where the data is. Looking in bc
# would find only views and report a loaded warehouse as empty.
# ---------------------------------------------------------------------------
$existingTables = @(Invoke-Sqlcmd @sqlArgs -Query @"
SELECT TABLE_SCHEMA AS s, TABLE_NAME AS t FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('bcRaw','bcModel') AND TABLE_TYPE = 'BASE TABLE';
"@)
$landing = @($existingTables | Where-Object { $_.s -eq 'bcRaw' } | ForEach-Object { $_.t })
$haveCalendar = [bool](@($existingTables | Where-Object { $_.s -eq 'bcModel' -and $_.t -eq 'dimDate' }).Count)

if ($Mode -eq 'Install' -and $landing.Count -gt 0 -and -not $Rebuild) {
    Write-Host ''
    Write-Warning "[$Database] already holds $($landing.Count) eOne landing table(s)."
    Write-Warning 'Install rebuilds them from empty, which discards every landed row - including the'
    Write-Warning 'version history in bcRaw that Business Central cannot serve again.'
    Write-Host ''
    Write-Warning 'To take this version WITHOUT losing data, run:  -Mode Update'
    Write-Warning 'To rebuild anyway, deliberately:                -Rebuild'
    throw 'Refusing to rebuild a loaded warehouse. Use -Mode Update, or -Rebuild to discard it.'
}

if ($Mode -eq 'Install' -and $Rebuild -and $landing.Count -gt 0) {
    Write-Warning "Rebuilding: $($landing.Count) landing table(s) and everything in them will be dropped."
}

# ---------------------------------------------------------------------------
# 6. Deploy
#
# Install runs every file as it is. Update runs the view files whole - they drop
# and recreate views, which hold no data - and takes the table files apart so it
# can create only what is missing.
#
# A table whose COLUMNS changed is not handled here, deliberately. Adding a
# column to a landing table that already holds rows is a real migration, and
# quietly dropping the table to get there is exactly the behaviour Update exists
# to avoid. It reports the difference and leaves it to you.
# ---------------------------------------------------------------------------
$fileNumber = { param($n) if ($n -match '^(\d+)_') { [int]$Matches[1] } else { 99 } }

# Each table's DDL is one contiguous block: its DROP TABLE line through the ');'
# that closes the CREATE. Splitting on that means Update can run a subset without
# a second generated file to keep in step.
function Split-TableDdl {
    param([Parameter(Mandatory)][string] $Sql)
    $pattern = '(?ms)^DROP TABLE IF EXISTS \[(\w+)\]\.\[(\w+)\];.*?^\);\s*$'
    $out = @()
    foreach ($m in [regex]::Matches($Sql, $pattern)) {
        $out += [pscustomobject]@{
            Schema = $m.Groups[1].Value
            Table  = $m.Groups[2].Value
            Sql    = $m.Value
        }
    }
    return ,@($out)
}

$added   = @()
$skipped = 0

Write-Step $(if ($Mode -eq 'Update') { 'Updating' } else { "Deploying $($files.Count) file(s)" })
$sw = [Diagnostics.Stopwatch]::StartNew()

foreach ($f in $files) {
    $num = & $fileNumber $f.Name
    $t = [Diagnostics.Stopwatch]::StartNew()

    # Update skips the calendar once it exists: it is static reference data, and
    # dropping it would take Power BI's relationship with it along too.
    if ($Mode -eq 'Update' -and $num -eq 11 -and $haveCalendar) {
        Write-Host ("    {0,-34}" -f $f.Name) -NoNewline
        Write-Host 'skipped (calendar present)' -ForegroundColor DarkGray
        continue
    }

    Write-Host ("    {0,-34}" -f $f.Name) -NoNewline
    try {
        if ($Mode -eq 'Update' -and $num -ge 10 -and $num -le 11) {
            $blocks = Split-TableDdl -Sql (Get-Content -Path $f.FullName -Raw)
            $missing = @($blocks | Where-Object { $landing -notcontains $_.Table })
            $skipped += ($blocks.Count - $missing.Count)
            foreach ($b in $missing) {
                Invoke-Sqlcmd @sqlArgs -Query $b.Sql
                $added += $b.Table
            }
            $note = if ($missing.Count) { "ok  +$($missing.Count) table(s)" } else { 'ok  no new tables' }
            Write-Host ("{0,-24}{1,6:N1}s" -f $note, $t.Elapsed.TotalSeconds) -ForegroundColor Green
        }
        else {
            Invoke-Sqlcmd @sqlArgs -InputFile $f.FullName
            Write-Host ("ok  {0,6:N1}s" -f $t.Elapsed.TotalSeconds) -ForegroundColor Green
        }
    }
    catch {
        Write-Host 'FAILED' -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        throw
    }
}

# ---------------------------------------------------------------------------
# 7. Report
# ---------------------------------------------------------------------------
$summary = Invoke-Sqlcmd @sqlArgs -Query @"
SELECT
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'bcRaw' AND TABLE_TYPE = 'BASE TABLE') AS landingTables,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.VIEWS  WHERE TABLE_SCHEMA = 'bc')                                  AS currentViews,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.VIEWS  WHERE TABLE_SCHEMA = 'bcModel')                             AS modelViews;
"@

$sw.Stop()
Write-Host ''
Write-Step ("Done in {0:N0}s" -f $sw.Elapsed.TotalSeconds)
if ($Mode -eq 'Update') {
    Write-Note $(if ($added.Count) { "$($added.Count) landing table(s) added: $($added -join ', ')" }
                 else { 'no new landing tables' })
    Write-Note "$skipped existing landing table(s) left untouched, rows and all"
}
Write-Note "$($summary.landingTables) landing tables in [bcRaw]"
Write-Note "$($summary.currentViews) current-state views in [bc]"
Write-Note "$($summary.modelViews) reporting views in [bcModel]"
Write-Host ''
# The connection details, together, at the end. They are what every map needs, and hunting them
# back out of the scrollback - or out of the Fabric portal - is a step nobody should have to take
# after the tool that just used them has them in hand.
Write-Host 'Connection' -ForegroundColor Cyan
Write-Host '    Server    ' -NoNewline -ForegroundColor DarkGray
Write-Host $Server -ForegroundColor White
Write-Host '    Database  ' -NoNewline -ForegroundColor DarkGray
Write-Host $Database -ForegroundColor White
Write-Note  'Authentication: Microsoft Entra. Fabric Warehouse accepts no SQL logins.'
Write-Host ''
Write-Note  'As an ADO.NET connection string:'
Write-Host  "    Server=$Server;Database=$Database;Authentication=Active Directory Interactive;Encrypt=True;" -ForegroundColor White
Write-Host ''
Write-Note  'For an unattended map, use Active Directory Service Principal instead and supply the'
Write-Note  'application id and secret in the connection string.'
Write-Host ''

Write-Host 'Next:' -ForegroundColor Cyan
Write-Note '1. Turn on Document Events in the eOne Integration Setup page in Business Central.'
Write-Note '   Nothing records lifecycle transitions until you do, and the feed errors while it is off.'
Write-Note '2. Build the integration maps. The deployment guide in docs\ names each one, its'
Write-Note '   every map INSERTS into [bcRaw] and matches on nothing. Duplicates are expected -'
Write-Note '   the [bc] views resolve the latest version per id.'
Write-Note '   Each map holds its own cursor in a global variable; the warehouse keeps no load state.'
Write-Note '3. Add the documentEvents map. Nothing applies its exits: bcModel.vw_documentExit'
Write-Note '   derives them, so no integration has to run before another. Run it often anyway -'
Write-Note '   lifecycle freshness is only as good as its schedule.'
Write-Host ''
Write-Note 'Reports are already there: point Power BI at the [bcModel] schema.'
Write-Host ''
Write-Note 'Full instructions: docs\eOne-BC-Fabric-Warehouse-Deployment-Guide.docx'
