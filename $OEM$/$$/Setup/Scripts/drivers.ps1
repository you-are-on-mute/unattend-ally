<#
  .SYNOPSIS
  Adds Drivers from a WIM image during WinPE.

  .DESCRIPTION
  The drivers.ps1 script installs *.inf drivers from WIM files located on the bootable media
  during the WinPE phase of the deployment. It is called from the autounattend.xml file.

  .PARAMETER InputPath
  None

  .PARAMETER OutputPath
  None

  .INPUTS
  None. You can't pipe objects to drivers.ps1.

  .OUTPUTS
  None. drivers.ps1 doesn't generate any output.

  .EXAMPLE
  PS> .\drivers.ps1
#>

# ====================================================================
# Logging
# ====================================================================
Set-PhaseTag "Drivers"
Start-ScriptTimer
Write-Activity "==================== INSTALL DRIVERS ====================" -Level INFO -Source 'Drivers'

# ====================================================================
# Elevation check
# ====================================================================
Write-Activity "Checking for elevation..." -Level INFO -Source 'StartPins'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Activity "You must run this script as Administrator. Aborting..." -Level ERROR -Source 'Drivers'
    Stop-ScriptTimer
    exit
}

# ====================================================================
# Environment
# ====================================================================
$driversPath = "$env:SystemRoot\Setup\Scripts\Drivers"
$wimTempDriverFolder = "$env:SystemDrive\DriverTemp"
$model = (Get-CimInstance -Class Win32_ComputerSystem).Model.Trim()

if (-not (Test-Path $wimTempDriverFolder)) {
    Write-Activity "Driver temp folder not found at $wimTempDriverFolder — creating..." -Level WARN -Source 'Drivers'
    try {
        New-Item -Path $wimTempDriverFolder -ItemType Directory -Force | Out-Null
    }
    catch {
        Write-Activity "Failed to create $wimTempDriverFolder — $_" -Level ERROR -Source 'Drivers'
        throw "Cannot continue without driver mount folder."
    }
}

# ====================================================================
# Model-specific WIM selection
# ====================================================================
$wimFile = switch -Wildcard ($model) {
    "ROG*" { "ROG_ALLY.wim" }
    default { $null }
}

if (-not $wimFile) {
    Write-Activity "No matching driver package found for model '$model'." -Level ERROR -Source 'Drivers'
    Stop-ScriptTimer
    return
}

$wimFullPath = Join-Path $driversPath $wimFile
if (-not (Test-Path $wimFullPath)) {
    Write-Activity "Driver WIM not found: $wimFullPath" -Level ERROR -Source 'Drivers'
    Stop-ScriptTimer
    return
}

Write-Activity "Model detected: $model — Using driver image: $wimFile" -Level INFO -Source 'Drivers'

# ====================================================================
# Mount the WIM
# ====================================================================
try {
    Write-Activity "Mounting driver WIM to $wimTempDriverFolder..." -Level INFO -Source 'Drivers'
    dism.exe /mount-wim /wimfile:"$wimFullPath" /index:1 /mountdir:"$wimTempDriverFolder" | Out-Null
}
catch {
    Write-Activity "Failed to mount driver WIM: $_" -Level ERROR -Source 'Drivers'
    Stop-ScriptTimer
    return
}

# ====================================================================
# Install Drivers
# ====================================================================
$infFiles = Get-ChildItem -Path $wimTempDriverFolder -Recurse -Filter "*.inf" -ErrorAction SilentlyContinue
if (-not $infFiles) {
    Write-Activity "No INF files found in mounted WIM." -Level WARN -Source 'Drivers'
}
else {
    foreach ($inf in $infFiles) {
        try {
            Write-Activity "Installing driver: $($inf.Name)" -Level INFO -Source 'Drivers'
            pnputil /add-driver "`"$($inf.FullName)`"" /install | Out-Null
        }
        catch {
            Write-Activity "Failed to install driver $($inf.Name): $_" -Level ERROR -Source 'Drivers'
        }
    }
}

# ====================================================================
# Unmount and cleanup
# ====================================================================
try {
    Write-Activity "Unmounting driver WIM and cleaning up..." -Level INFO -Source 'Drivers'
    dism.exe /unmount-wim /mountdir:"$wimTempDriverFolder" /discard | Out-Null
    Remove-Item $wimTempDriverFolder -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Activity "Cleanup failed: $_" -Level WARN -Source 'Drivers'
}

# ====================================================================
# Device re-scan
# ====================================================================
Write-Activity "Re-enumerating devices..." -Level INFO -Source 'Drivers'
pnputil /scan-devices | Out-Null

# ====================================================================
# Summary and Runtime
# ====================================================================
Write-Activity "==================== END DRIVER INSTALL ====================" -Level INFO -Source 'Drivers'
Stop-ScriptTimer