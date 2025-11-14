<#
  .SYNOPSIS
  Performs final first-logon tasks during OOBE.

  .DESCRIPTION
  FirstLogon.ps1 runs during the Windows FirstLogonCommands phase.
  It performs final post-deployment actions including registry cleanup,
  packaged app installation, ViVe configuration, and environment preparation.

  .PARAMETER InputPath
  None

  .PARAMETER OutputPath
  None

  .INPUTS
  None. You can't pipe objects to FirstLogon.ps1.

  .OUTPUTS
  None. FirstLogon.ps1 doesn't generate any output.

  .EXAMPLE
  PS> .\FirstLogon.ps1
#>

# ====================================================================
# Event Logging Module
# ====================================================================
$modulePath = "$env:SystemRoot\setup\Scripts\\Modules\OSDeployLogging\OSDeployLogging.psm1"
Import-Module $modulePath -Force

Initialize-OSDeployLogging
Set-PhaseTag "FirstLogon"
Start-ScriptTimer

Write-Activity "==================== BEGIN FIRST LOGON PHASE ====================" -Level INFO -Source 'FirstLogon'

# ====================================================================
# Elevation check
# ====================================================================
Write-Activity "Checking for elevation..." -Level INFO -Source 'FirstLogon'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Activity "You must run this script as Administrator. Aborting..." -Level ERROR -Source 'FirstLogon'
  Stop-ScriptTimer
  Stop-OSDeployLogging
  exit
}

# ====================================================================
# Define and execute script tasks
# ====================================================================
$scriptPath = "$env:SystemRoot\Setup\Scripts"
Write-Activity "Script path set to $scriptPath" -Level INFO -Source 'FirstLogon'

$nestedScripts = @(
  @{
    Name   = "Set AutoLogonCount to 0"
    Action = {
      Set-ItemProperty -LiteralPath 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' `
        -Name 'AutoLogonCount' -Type 'DWord' -Force -Value 0
    }
  },
  @{
    Name   = "Install Packaged Apps"
    Action = {
      $file = Join-Path $scriptPath "PackagedApps.ps1"
      if (Test-Path $file) {
        Write-Activity "Running nested script: PackagedApps.ps1" -Level INFO -Source 'FirstLogon'
        & $file
        Write-Activity "Packaged apps installation completed." -Level INFO -Source 'FirstLogon'
      }
      else {
        Write-Activity "PackagedApps.ps1 not found at $file" -Level WARN -Source 'FirstLogon'
      }
    }
  },
  @{
    Name   = "Set Network Profile to Private"
    Action = {
      Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
      Write-Activity "Network connection profile set to Private" -Level INFO -Source 'FirstLogon'
    }
  },
  @{
    Name   = "Enable ViVe Features"
    Action = {
      $file = Join-Path $scriptPath "Enable-Vive.ps1"
      if (Test-Path $file) {
        Write-Activity "Running nested script: Enable-Vive.ps1" -Level INFO -Source 'FirstLogon'
        & $file
        Write-Activity "ViVe feature configuration completed." -Level INFO -Source 'FirstLogon'
      }
      else {
        Write-Activity "Enable-Vive.ps1 not found at $file" -Level WARN -Source 'FirstLogon'
      }
    }
  },
  @{
    Name   = "Remove Windows.old directory"
    Action = {
      if (Test-Path "C:\Windows.old") {
        cmd.exe /c "rmdir /s /q C:\Windows.old"
        Write-Activity "Removed Windows.old directory" -Level INFO -Source 'FirstLogon'
      }
      else {
        Write-Activity "Windows.old directory not found; skipping cleanup." -Level WARN -Source 'FirstLogon'
      }
    }
  }
)

# ====================================================================
# Execute tasks with progress
# ====================================================================
[float] $complete = 0
[float] $increment = 100 / $nestedScripts.Count

foreach ($script in $nestedScripts) {
  Write-Progress -Activity "Executing first-logon tasks..." -Status $script.Name -PercentComplete $complete
  Write-Activity "Starting task: $($script.Name)" -Level INFO -Source 'FirstLogon'

  try {
    $start = Get-Date
    & $script.Action
    $elapsed = (Get-Date) - $start
    Write-Activity "Completed task: $($script.Name) in $([math]::Round($elapsed.TotalSeconds,2)) seconds" -Level INFO -Source 'FirstLogon'
  }
  catch {
    Write-Activity "Error during task: $($script.Name) - $_" -Level ERROR -Source 'FirstLogon'
  }

  $complete += $increment
}

# ====================================================================
# Final Cleanup
# ====================================================================
Write-Activity "Performing script cleanup..." -Level INFO -Source 'FirstLogon'
$FinalCleanup = @()
$FinalCleanup += Get-ChildItem $scriptPath -File | Where-Object { $_.Name -notin "FirstLogon.ps1" } | Select-Object -ExpandProperty FullName
$FinalCleanup += Get-ChildItem $scriptPath -Directory -Recurse | Select-Object -ExpandProperty FullName

foreach ($item in $FinalCleanup) {
  try {
    Remove-Item $item -Recurse -Force -ErrorAction SilentlyContinue
  }
  catch {
    Write-Activity "Failed to remove ${item}: $($_.Exception.Message)" -Level WARN -Source 'FirstLogon'
  }
}

Write-Activity "Cleanup completed successfully." -Level INFO -Source 'FirstLogon'

# ====================================================================
# Post actions
# ====================================================================
Write-Activity "Forcing Group Policy update..." -Level INFO -Source 'FirstLogon'
Invoke-Command -ScriptBlock { GPUpdate /Force }

Write-Activity "Restarting computer to complete configuration..." -Level INFO -Source 'FirstLogon'
Restart-Computer -Force

# ====================================================================
# Summary
# ====================================================================
Write-Activity "==================== END FIRST LOGON PHASE ====================" -Level INFO -Source 'FirstLogon'
Stop-ScriptTimer
Stop-OSDeployLogging