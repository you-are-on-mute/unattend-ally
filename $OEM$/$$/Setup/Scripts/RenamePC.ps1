<#
  .SYNOPSIS
  Renames the devices.

  .DESCRIPTION
  The RenamePC.ps1 script renames the device using simple logic. If you are confident changing this file, the computer name can be set at Line 59

  .PARAMETER InputPath
  None

  .PARAMETER OutputPath
  None

  .INPUTS
  None. You can't pipe objects to RenamePC.ps1.

  .OUTPUTS
  None. RenamePC.ps1 doesn't generate any output.

  .EXAMPLE
  PS> .\RenamePC.ps1
#>

# ====================================================================
# Execution Policy
# ====================================================================
Write-Host "Set Execution Policy to Bypass for this script.."
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# ====================================================================
# Event Logging Module
# ====================================================================
Import-Module "$env:SystemRoot\setup\Scripts\Modules\OSDeployLogging\OSDeployLogging.psm1" -Force
Initialize-OSDeployLogging
Set-PhaseTag "OOBE"
Start-ScriptTimer

Write-Activity "==================== RENAME PC ====================" -Level INFO -Source 'Configuration'

# ====================================================================
# Elevation check
# ====================================================================
Write-Activity "Checking for elevation..." -Level INFO -Source 'Configuration'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Activity "You must run this script as Administrator. Aborting..." -Level ERROR -Source 'Configuration'
    Stop-Transcript
    exit
}

# Get the model prefix and rename the computer idempotently
$model = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model
$NewComputerName = ""

# Skip if Virtual Machine
if ($model -match "^ROG") {
    # For ROG Models, use the Mode Name
    $NewComputerName = "ALLY-X"
}
else {
    $msg = "Model type not recognised - Custom logic needed for: $model"
    Write-Activity $msg -Level WARN -Source 'Configuration'
    exit
}

Rename-Computer -NewName $NewComputerName -Force
Write-Activity "Setting PC Hostname to $NewComputerName" -Level INFO -Source 'Configuration'

# ====================================================================
# Summary and runtime
# ====================================================================
Write-Activity "==================== END PC RENAME INSTALL ====================" -Level INFO -Source 'Configuration'
Stop-ScriptTimer