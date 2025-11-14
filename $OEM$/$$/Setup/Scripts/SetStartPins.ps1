<#
  .SYNOPSIS
  Configures the Start menu pinned layout during deployment.

  .DESCRIPTION
  Clears and sets the Start menu pinned layout using the PolicyManager registry key.
  This script runs as part of the specialize phase to ensure a clean Start experience.

  .PARAMETER InputPath
  None

  .PARAMETER OutputPath
  None

  .INPUTS
  None. You can't pipe objects to SetStartPins.ps1.

  .OUTPUTS
  None. SetStartPins.ps1 doesn't generate any output.

  .EXAMPLE
  PS> .\SetStartPins.ps1
#>

# ====================================================================
# Logging (inherits from specialize.ps1)
# ====================================================================
Set-PhaseTag "OOBE"
Start-ScriptTimer
Write-Activity "==================== SET START PINS ====================" -Level INFO -Source 'StartPins'

# ====================================================================
# Elevation check
# ====================================================================
Write-Activity "Checking for elevation..." -Level INFO -Source 'StartPins'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Activity "You must run this script as Administrator. Aborting..." -Level ERROR -Source 'StartPins'
  Stop-ScriptTimer
  exit
}

# ====================================================================
# Configure Start Menu Pinned Layout
# ====================================================================
$json = '{"pinnedList":[]}'
try {
  if ([System.Environment]::OSVersion.Version.Build -lt 20000) {
    Write-Activity "Skipping Start Pins configuration: build is older than Windows 11." -Level WARN -Source 'StartPins'
    Stop-ScriptTimer
    return
  }

  $key = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start'
  if (-not (Test-Path $key)) {
    New-Item -Path $key -ItemType Directory -Force | Out-Null
    Write-Activity "Created registry key: ${key}" -Level INFO -Source 'StartPins'
  }

  Set-ItemProperty -Path $key -Name 'ConfigureStartPins' -Value $json -Type String -Force
  Write-Activity "Set Start Pins policy with pinnedList JSON: ${json}" -Level INFO -Source 'StartPins'
}
catch {
  Write-Activity "Failed to configure Start Pins: $_" -Level ERROR -Source 'StartPins'
}

# ====================================================================
# Summary and Runtime
# ====================================================================
Write-Activity "==================== END START PIN CONFIGURATION ====================" -Level INFO -Source 'StartPins'
Stop-ScriptTimer