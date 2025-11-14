<#
  .SYNOPSIS
  Adds VIVE components to allow XBOX FSE

  .DESCRIPTION
  The Enable-Vive.ps1 script loads the Vive tool (installed from packaged apps script) and adds the required regkeys and device forms for XBOX FSE to work

  .PARAMETER InputPath
  None

  .PARAMETER OutputPath
  None

  .INPUTS
  None. You can't pipe objects to this script.

  .OUTPUTS
  None. Enable-Vive.ps1 doesn't generate any output.

  .EXAMPLE
  PS> .\Enable-Vive.ps1
#>

# ====================================================================
# Logging
# ====================================================================
Set-PhaseTag "Apps"
Start-ScriptTimer
Write-Activity "==================== VIVE INSTALL ====================" -Level INFO -Source 'Apps'

# ====================================================================
# Elevation check
# ====================================================================
Write-Activity "Checking for elevation..." -Level INFO -Source 'Apps'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Activity "You must run this script as Administrator. Aborting..." -Level ERROR -Source 'Apps'
    Stop-ScriptTimer
    exit
}

# Path to ViVeTool
$viveToolPath = "C:\Program Files (x86)\WinGet\Packages\thebookisclosed.Vive_Microsoft.Winget.Source_8wekyb3d8bbwe\ViVeTool.exe"

# Check if ViVeTool exists
if (-not (Test-Path $viveToolPath)) {
    Write-Activity "Error: ViVeTool not found at '$viveToolPath'." -Level ERROR -Source 'ViVe'
    exit 1
}

# Registry path and value
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OEM"
$regName = "DeviceForm"
$regValue = 0x2E  # Hexadecimal 2E = 46 decimal

# Ensure the registry key exists
if (-not (Test-Path $regPath)) {
    Write-Activity "Creating registry key: $regPath" -Level INFO -Source 'ViVe'
    New-Item -Path $regPath -Force | Out-Null
}

# Check and set the DeviceForm value
$currentValue = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue).$regName
if ($null -eq $currentValue) {
    Write-Activity "Creating DeviceForm DWORD value..." -Level INFO -Source 'ViVe'
    New-ItemProperty -Path $regPath -Name $regName -PropertyType DWord -Value $regValue | Out-Null
}
elseif ($currentValue -ne $regValue) {
    Write-Activity "Updating DeviceForm value to 0x2E..." -Level INFO -Source 'ViVe'
    Set-ItemProperty -Path $regPath -Name $regName -Value $regValue
}
else {
    Write-Activity "DeviceForm already set to 0x2E." -Level WARN -Source 'ViVe'
}

# List of feature IDs to enable
$featureIds = @(52580392, 50902630)

# Loop through each ID and enable it
foreach ($id in $featureIds) {
    Write-Activity "Enabling feature ID: $id..." -Level INFO -Source 'ViVe'
    Start-Process -FilePath $viveToolPath -ArgumentList "/enable", "/id:$id" -Wait -NoNewWindow
}

Write-Activity "All settings configured successfully." -Level INFO -Source 'ViVe'

# ====================================================================
# Summary and Runtime
# ====================================================================
Write-Activity "==================== END VIVE INSTALLL ====================" -Level INFO -Source 'Apps'
Stop-ScriptTimer