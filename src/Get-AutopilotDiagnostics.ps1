[CmdletBinding()]
param(
    [Parameter()]
    [ValidateRange(1, 720)]
    [int]$Hours = 48,

    [Parameter()]
    [string]$OutputPath = (Join-Path -Path $PWD -ChildPath ("Autopilot-Diagnostics-{0:yyyyMMdd_HHmmss}" -f (Get-Date)))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$ErrorLog = Join-Path $OutputPath 'command-errors.log'
$SummaryJson = Join-Path $OutputPath 'summary.json'
$SummaryCsv = Join-Path $OutputPath 'summary.csv'
$HtmlReport = Join-Path $OutputPath 'Autopilot-Diagnostics.html'
$DsRegFile = Join-Path $OutputPath 'dsregcmd-status.txt'

function Invoke-Safe {
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][string]$Label
    )
    try {
        & $ScriptBlock
    }
    catch {
        "[$(Get-Date -Format o)] $Label :: $($_.Exception.Message)" | Add-Content -Path $ErrorLog
        $null
    }
}

function Get-RegistryTree {
    param([Parameter(Mandatory)][string]$Path)
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path $Path)) { return @() }
    foreach ($key in Get-ChildItem -Path $Path -Recurse -ErrorAction SilentlyContinue) {
        $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $props) { continue }
        foreach ($property in $props.PSObject.Properties) {
            if ($property.Name -match '^PS(Path|ParentPath|ChildName|Drive|Provider)$') { continue }
            $rows.Add([pscustomobject]@{
                RegistryPath = $key.Name
                Name         = $property.Name
                Value        = [string]$property.Value
            })
        }
    }
    $rows
}

$startTime = (Get-Date).AddHours(-$Hours)
$computer = Invoke-Safe -Label 'Computer information' -ScriptBlock { Get-CimInstance Win32_ComputerSystem }
$os = Invoke-Safe -Label 'Operating system' -ScriptBlock { Get-CimInstance Win32_OperatingSystem }
$bios = Invoke-Safe -Label 'BIOS' -ScriptBlock { Get-CimInstance Win32_BIOS }
$tpm = Invoke-Safe -Label 'TPM' -ScriptBlock { Get-Tpm }
$secureBoot = Invoke-Safe -Label 'Secure Boot' -ScriptBlock { Confirm-SecureBootUEFI }

$dsreg = Invoke-Safe -Label 'dsregcmd' -ScriptBlock { (& dsregcmd.exe /status 2>&1 | Out-String) }
if ($dsreg) { $dsreg | Set-Content -Path $DsRegFile -Encoding UTF8 }

function Get-DsRegValue {
    param([string]$Name)
    if (-not $dsreg) { return $null }
    $match = [regex]::Match($dsreg, "(?m)^\s*$([regex]::Escape($Name))\s*:\s*(.+?)\s*$")
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    $null
}

$joinState = [pscustomobject]@{
    AzureAdJoined = Get-DsRegValue 'AzureAdJoined'
    DomainJoined  = Get-DsRegValue 'DomainJoined'
    WorkplaceJoined = Get-DsRegValue 'WorkplaceJoined'
    DeviceId      = Get-DsRegValue 'DeviceId'
    TenantId      = Get-DsRegValue 'TenantId'
    AzureAdPrt    = Get-DsRegValue 'AzureAdPrt'
}

$autopilotRegistry = Invoke-Safe -Label 'Autopilot registry' -ScriptBlock {
    Get-RegistryTree 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot'
}
$enrolmentRegistry = Invoke-Safe -Label 'MDM enrolments' -ScriptBlock {
    Get-RegistryTree 'HKLM:\SOFTWARE\Microsoft\Enrollments'
}

$eventLogs = @(
    'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin',
    'Microsoft-Windows-ModernDeployment-Diagnostics-Provider/Autopilot',
    'Microsoft-Windows-Provisioning-Diagnostics-Provider/Admin',
    'Microsoft-Windows-AAD/Operational'
)
$events = New-Object System.Collections.Generic.List[object]
foreach ($logName in $eventLogs) {
    $items = Invoke-Safe -Label "Event log $logName" -ScriptBlock {
        Get-WinEvent -FilterHashtable @{ LogName = $logName; StartTime = $startTime } -ErrorAction Stop |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message
    }
    foreach ($item in @($items)) {
        if ($null -ne $item) {
            $events.Add([pscustomobject]@{
                LogName          = $logName
                TimeCreated      = $item.TimeCreated
                Id               = $item.Id
                LevelDisplayName = $item.LevelDisplayName
                ProviderName     = $item.ProviderName
                Message          = $item.Message
            })
        }
    }
}
$events | Export-Csv -Path (Join-Path $OutputPath 'autopilot-events.csv') -NoTypeInformation -Encoding UTF8

$imeService = Invoke-Safe -Label 'Intune Management Extension service' -ScriptBlock {
    Get-Service -Name IntuneManagementExtension -ErrorAction Stop |
        Select-Object Name, Status, StartType
}
$imeLogs = Invoke-Safe -Label 'Intune Management Extension logs' -ScriptBlock {
    $imePath = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
    if (Test-Path $imePath) {
        Get-ChildItem -Path $imePath -File -ErrorAction Stop |
            Select-Object Name, Length, LastWriteTime
    }
}
$imeLogs | Export-Csv -Path (Join-Path $OutputPath 'ime-log-inventory.csv') -NoTypeInformation -Encoding UTF8

$endpoints = @(
    'login.microsoftonline.com',
    'device.login.microsoftonline.com',
    'enterpriseregistration.windows.net',
    'enrollment.manage.microsoft.com'
)
$connectivity = foreach ($endpoint in $endpoints) {
    $dnsOk = $false
    try { [void][System.Net.Dns]::GetHostAddresses($endpoint); $dnsOk = $true } catch {}
    $tcp = Invoke-Safe -Label "Connectivity $endpoint" -ScriptBlock {
        Test-NetConnection -ComputerName $endpoint -Port 443 -WarningAction SilentlyContinue
    }
    [pscustomobject]@{
        Endpoint         = $endpoint
        DnsResolved      = $dnsOk
        Tcp443Successful = if ($tcp) { [bool]$tcp.TcpTestSucceeded } else { $false }
        RemoteAddress    = if ($tcp) { [string]$tcp.RemoteAddress } else { $null }
    }
}
$connectivity | Export-Csv -Path (Join-Path $OutputPath 'connectivity.csv') -NoTypeInformation -Encoding UTF8

$summary = [pscustomobject]@{
    CollectedAt         = (Get-Date).ToString('o')
    ComputerName        = $env:COMPUTERNAME
    Manufacturer        = $computer.Manufacturer
    Model               = $computer.Model
    WindowsCaption      = $os.Caption
    WindowsVersion      = $os.Version
    WindowsBuild        = $os.BuildNumber
    BiosVersion         = ($bios.SMBIOSBIOSVersion -join ', ')
    TpmPresent          = if ($tpm) { [bool]$tpm.TpmPresent } else { $false }
    TpmReady            = if ($tpm) { [bool]$tpm.TpmReady } else { $false }
    SecureBoot          = if ($null -ne $secureBoot) { [bool]$secureBoot } else { $null }
    AzureAdJoined       = $joinState.AzureAdJoined
    DomainJoined        = $joinState.DomainJoined
    WorkplaceJoined     = $joinState.WorkplaceJoined
    AzureAdPrt          = $joinState.AzureAdPrt
    IntuneServiceStatus = if ($imeService) { [string]$imeService.Status } else { 'Not detected' }
    EventCount          = $events.Count
    ErrorEventCount     = @($events | Where-Object { $_.LevelDisplayName -in @('Error','Critical') }).Count
    ConnectivityPassed  = @($connectivity | Where-Object Tcp443Successful).Count
    ConnectivityTotal   = $connectivity.Count
}

$summary | Export-Csv -Path $SummaryCsv -NoTypeInformation -Encoding UTF8
$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $SummaryJson -Encoding UTF8
$autopilotRegistry | Export-Csv -Path (Join-Path $OutputPath 'autopilot-registry.csv') -NoTypeInformation -Encoding UTF8
$enrolmentRegistry | Export-Csv -Path (Join-Path $OutputPath 'mdm-enrolment-registry.csv') -NoTypeInformation -Encoding UTF8

$style = @'
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:28px;color:#172033;background:#f6f8fb}
h1,h2{color:#0b3558}.card{background:white;border:1px solid #d8e0ea;border-radius:8px;padding:18px;margin:14px 0}
table{border-collapse:collapse;width:100%}th,td{border:1px solid #d8e0ea;padding:7px;text-align:left;vertical-align:top}th{background:#eaf2f8}
</style>
'@
$body = @()
$body += $summary | ConvertTo-Html -Fragment -PreContent '<h2>Summary</h2>'
$body += $connectivity | ConvertTo-Html -Fragment -PreContent '<h2>Microsoft Endpoint Connectivity</h2>'
$body += $events | Select-Object -First 200 | ConvertTo-Html -Fragment -PreContent '<h2>Recent Events</h2>'
$body += '<p>Diagnostic-only collection. Review and redact identifiers before external sharing.</p>'
ConvertTo-Html -Title 'Windows Autopilot Diagnostics' -Head $style -Body $body |
    Set-Content -Path $HtmlReport -Encoding UTF8

Write-Host "Autopilot diagnostic collection completed: $OutputPath"
