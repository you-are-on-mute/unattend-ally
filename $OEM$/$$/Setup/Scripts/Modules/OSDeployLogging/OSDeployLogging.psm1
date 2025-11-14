# ====================================================================
# Module: OSDeployLogging.psm1
# Purpose: Unified logging for Windows Autounattend deployments
# Author: ChatGPT + User collaboration
# ====================================================================

# Set global module root path
$Global:OSDeployModuleRoot = $PSScriptRoot

# Define constants
$Global:LogFilePath = "C:\Logs\OS_Deploy.log"
$Global:EventSources = @(
    'ADK', 'Adobe', 'AppxPackage', 'Applications', 'Capabilities',
    'Chocolatey', 'Configuration', 'Deployment', 'Drivers',
    'Features', 'LGPO', 'MSStore', 'Network', 'Office',
    'PackagedApps', 'Registry', 'Teams', 'UserAccounts', 'UserSettings',
    'ViVe', 'WinGet'
)

# ====================================================================
# Function: Initialize-OSDeployLogging
# ====================================================================
function Initialize-OSDeployLogging {
    [CmdletBinding()]
    param()

    # Ensure log folder exists
    $logDir = Split-Path $Global:LogFilePath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # Build dynamic event log name from OS caption
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    $Global:EventLogName = "$os Deployment"

    # Create event log if missing
    if (-not [System.Diagnostics.EventLog]::SourceExists('Deployment')) {
        try {
            New-EventLog -LogName $Global:EventLogName -Source $Global:EventSources
            Limit-EventLog -OverflowAction OverWriteAsNeeded -MaximumSize 64KB -LogName $Global:EventLogName
            Write-EventLog -LogName $Global:EventLogName -Source 'Deployment' -EventId 1 -EntryType Information -Message "Event log created."
        }
        catch {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Failed to create event log: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Start transcript (single file shared across session)
    $transcriptPath = "C:\Logs\OS_Deploy_Transcript.txt"
    if (-not (Test-Path $transcriptPath)) {
        Start-Transcript -Path $transcriptPath -Append -Force | Out-Null
    }

    # Log session start
    Write-Activity "==================== DEPLOYMENT SESSION START ====================" -Level INFO
}

# ====================================================================
# Function: Stop-OSDeployLogging
# ====================================================================
function Stop-OSDeployLogging {
    [CmdletBinding()]
    param()

    Write-Activity "==================== DEPLOYMENT SESSION END ======================" -Level INFO
    try { Stop-Transcript | Out-Null } catch {}
}

# ====================================================================
# Function: Set-PhaseTag
# ====================================================================
function Set-PhaseTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            "AppXCleanup", "Specialize", "Drivers", "DefaultUser", "OOBE",
            "FirstLogon", "UserOnce", "Generalize", "Features", "Capabilities", "Apps", "WiFi"
        )]
        [string]$Phase
    )

    $Global:PhaseTag = "[$Phase]"
    Write-Activity "Phase tag set to $Global:PhaseTag" -Level DEBUG
}

# ====================================================================
# Function: Start-ScriptTimer
# ====================================================================
function Start-ScriptTimer {
    [CmdletBinding()]
    param()

    $Global:ScriptStartTime = Get-Date
}

# ====================================================================
# Function: Stop-ScriptTime
# ====================================================================
function Stop-ScriptTimer {
    [CmdletBinding()]
    param(
        [string]$ScriptName
    )

    # Auto-resolve if not provided or empty
    if (-not $ScriptName -or $ScriptName -eq "") {
        if ($PSCommandPath) {
            $ScriptName = Split-Path -Leaf $PSCommandPath
        }
        elseif ($MyInvocation.MyCommand.Path) {
            $ScriptName = Split-Path -Leaf $MyInvocation.MyCommand.Path
        }
        else {
            $ScriptName = "UnknownScript"
        }
    }

    if (-not $Global:ScriptStartTime) {
        Write-Activity "Stop-ScriptTimer called before Start-ScriptTimer." -Level WARN
        return
    }

    $endTime = Get-Date
    $duration = New-TimeSpan -Start $Global:ScriptStartTime -End $endTime
    $elapsed = "{0:D2}h:{1:D2}m:{2:D2}s" -f $duration.Hours, $duration.Minutes, $duration.Seconds

    Write-Activity "$ScriptName completed in $elapsed." -Level INFO
    $Global:ScriptStartTime = $null
}

# ====================================================================
# Function: Write-Activity
# ====================================================================
function Write-Activity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO",

        [string]$Source = "Deployment"
    )

    # Determine log prefix
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $phase = if ($Global:PhaseTag) { $Global:PhaseTag } else { "UNKNOWN" }
    $prefix = "[$timestamp][$Level][$phase]"

    # Write to host with color
    switch ($Level) {
        "INFO" { Write-Host "$prefix $Message" -ForegroundColor Cyan }
        "WARN" { Write-Host "$prefix $Message" -ForegroundColor Yellow }
        "ERROR" { Write-Host "$prefix $Message" -ForegroundColor Red }
        "DEBUG" { Write-Host "$prefix $Message" -ForegroundColor Gray }
    }

    # Write to file
    Add-Content -Path $Global:LogFilePath -Value "$prefix $Message"

    # Write to event log (safely)
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($Source)) {
            $etype = switch ($Level) {
                "INFO" { "Information" }
                "WARN" { "Warning" }
                "ERROR" { "Error" }
                default { "Information" }
            }
            Write-EventLog -LogName $Global:EventLogName -Source $Source -EventId 1 -EntryType $etype -Message "${Source}: $Message"
        }
    }
    catch {
        # ignore event log write failures
    }
}
