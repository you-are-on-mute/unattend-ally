<#
  .SYNOPSIS
  Adds Apps from Winget during first logon.

  .DESCRIPTION
  The PackagedApps script installs any applications from Winget as required / desired. As long as the application is available in the Winget catalog.
  Edit Winget Apps Array under line 142 as required.

  .PARAMETER InputPath
  None

  .PARAMETER OutputPath
  None

  .INPUTS
  None. You can't pipe objects to PackagedApps.ps1.

  .OUTPUTS
  None. PackagedApps.ps1 doesn't generate any output.

  .EXAMPLE
  PS> .\PackagedApps.ps1
#>

# ====================================================================
# Logging
# ====================================================================
Set-PhaseTag "Apps"
Start-ScriptTimer
Write-Activity "==================== PACKAGED APPS ====================" -Level INFO -Source 'Apps'

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

# ====================================================================
# Function: Locate Winget
# ====================================================================
function GetWingetPath() {
    $ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue
    if ($ResolveWingetPath) {
        $WingetPath = $ResolveWingetPath[-1].Path
        return $WingetPath + "\winget.exe"
    }
    Write-Activity "Failed to resolve Winget path." -Level ERROR -Source 'Winget'
}

# ====================================================================
# Function: Confirm app exists in Winget repo
# ====================================================================
function Confirm-Exist {
    param([string]$AppID)
    $OutputFile = "$env:TEMP\winget_check.txt"
    Start-Process $wingetpath -ArgumentList "show --id $AppID -e --accept-source-agreements -s winget" -NoNewWindow -RedirectStandardOutput $OutputFile -Wait
    $result = Get-Content $OutputFile -Raw
    Remove-Item $OutputFile -Force
    if ($result -match [regex]::Escape($AppID)) {
        Write-Activity "→ $AppID found in WinGet repository." -Source 'Winget'
        return $true
    }
    Write-Activity "→ $AppID not found in WinGet repository; skipping." -Level WARN -Source 'Winget'
    return $false
}

# ====================================================================
Write-Activity "Application install script beginning." -Level INFO -Source 'Winget'

# ====================================================================
# WebClient setup
# ====================================================================
$dc = New-Object net.webclient
$dc.UseDefaultCredentials = $true
$dc.Headers.Add("user-agent", "Inter Explorer")
$dc.Headers.Add("X-FORMS_BASED_AUTH_ACCEPTED", "f")

# Temp folder
$InstallerFolder = Join-Path $env:ProgramData CustomScripts
if (!(Test-Path $InstallerFolder)) {
    New-Item -Path $InstallerFolder -ItemType Directory -Force | Out-Null
    Write-Activity "Created installer folder at $InstallerFolder." -Level INFO -Source 'Winget'
}

# ====================================================================
# Check for Winget
# ====================================================================
Write-Activity "Checking if Winget is installed..." -Level INFO -Source 'Winget'
$TestWinget = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq "Microsoft.DesktopAppInstaller" }

if ([Version]$TestWinGet.Version -gt "2022.506.16.0") {
    Write-Activity "Winget is installed." -Level INFO -Source 'Winget'
}
else {
    Write-Activity "Winget not found or outdated — downloading installer bundle..." -Level WARN -Source 'Winget'
    $WinGetURL = "https://aka.ms/getwinget"
    $bundlePath = "$InstallerFolder\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $dc.DownloadFile($WinGetURL, $bundlePath)

    try {
        Write-Activity "Installing App Installer (Winget) bundle..." -Level INFO -Source 'Winget'
        Add-AppxProvisionedPackage -Online -PackagePath $bundlePath -SkipLicense
        Write-Activity "App Installer successfully installed." -Level INFO -Source 'Winget'
    }
    catch {
        Write-Activity "Failed to install App Installer: $($_.Exception.Message)" -Level ERROR -Source 'Winget'
    }
    finally {
        Remove-Item $InstallerFolder -Force -Recurse -ErrorAction SilentlyContinue
    }
}

# ====================================================================
# Update and Pin Winget
# ====================================================================
$wingetpath = GetWingetPath

Write-Activity "Checking for Winget updates..." -Level INFO -Source 'Winget'
$updateWinget = Start-Process $wingetpath -ArgumentList "upgrade Microsoft.AppInstaller --accept-package-agreements --accept-source-agreements --silent" -PassThru -Wait
switch ($updateWinget.ExitCode) {
    -1978335189 { Write-Activity "No Winget update required." -Level INFO -Source 'Winget' }
    default { Write-Activity "Winget updated; refreshing path." -Level INFO -Source 'Winget'; $wingetpath = GetWingetPath }
}

$pinWinget = Start-Process $wingetpath -ArgumentList "pin add --id Microsoft.AppInstaller" -PassThru
$pinWinget.WaitForExit()
Write-Activity "Winget pinned to current version." -Level INFO -Source 'Winget'

# ====================================================================
# Upgrade all existing apps
# ====================================================================
Write-Activity "Upgrading existing apps via Winget..." -Level INFO -Source 'Winget'
$upgrade = Start-Process $wingetpath -ArgumentList "upgrade --all --accept-package-agreements --accept-source-agreements --silent" -PassThru
$upgrade.WaitForExit()
Write-Activity "App upgrades completed successfully." -Level INFO -Source 'Winget'

# ====================================================================
# App installation list
# ====================================================================
$wingetApps = @(
    @{ ID = "Microsoft.DotNet.DesktopRuntime.8"; MachineScope = $true },
    @{ ID = "seerge.g-helper"; MachineScope = $true },
    @{ ID = "thebookisclosed.Vive"; MachineScope = $true }
)

foreach ($app in $wingetApps) {
    $AppID = $app.ID

    if (-not (Confirm-Exist -AppID $AppID)) {
        continue
    }

    $argument = "install --exact --id $AppID --silent --accept-package-agreements --accept-source-agreements"
    if ($app.MachineScope) { $argument += " --scope machine" }

    Write-Activity "Installing $AppID..." -Level INFO -Source 'Winget'
    $proc = Start-Process $wingetpath -ArgumentList $argument -PassThru -Wait

    if ($proc.ExitCode -eq 0) {
        Write-Activity "$AppID installed successfully." -Level INFO -Source 'Winget'
    }
    else {
        Write-Activity "$AppID failed with exit code $($proc.ExitCode)." -Level WARN -Source 'Winget'
    }
}

# ====================================================================
# Remove unwanted apps
# ====================================================================
$appstoremove = "9NRX63209R7B", "Microsoft.OutlookForWindows", "Microsoft.DevHome", "Microsoft.Windows.DevHome"
foreach ($app in $appstoremove) {
    Write-Activity "Removing $app..." -Level INFO -Source 'Winget'
    $argument = "uninstall --exact --id $app"
    $proc = Start-Process $wingetpath -ArgumentList $argument -PassThru -Wait
    Write-Activity "$app removal process completed." -Level INFO -Source 'Winget'
}

# ====================================================================
# Verify installs
# ====================================================================
$wingetpath.Replace("winget.exe", "") | Set-Location
.\winget.exe list --source winget | Out-Host
Write-Activity "Winget list command executed for verification." -Level INFO -Source 'Winget'

# ====================================================================
# Summary and Runtime
# ====================================================================
Write-Activity "==================== END PACKAGED APPS ====================" -Level INFO -Source 'Apps'
Stop-ScriptTimer