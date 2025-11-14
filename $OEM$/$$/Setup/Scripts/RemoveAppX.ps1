<#
  .SYNOPSIS
  Removes default AppX and provisioned packages.

  .DESCRIPTION
  This script removes pre-installed AppX and provisioned apps from the Windows image
  during the Specialize phase of deployment. It is intended to be nested under Specialize.ps1.
#>

# ====================================================================
# Phase + Logging Context (inherited from parent)
# ====================================================================
Set-PhaseTag "AppXCleanup"
Start-ScriptTimer

Write-Activity "==================== APPX CLEANUP ====================" -Level INFO -Source 'AppXCleanup'

# ====================================================================
# Elevation check
# ====================================================================
Write-Activity "Checking for elevation..." -Level INFO -Source 'AppXCleanup'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole] "Administrator"
    )) {
    Write-Activity "You must run this script as Administrator. Aborting..." -Level ERROR -Source 'AppXCleanup'
    Stop-ScriptTimer
    return
}

# ====================================================================
# AppX Removal Logic
# ====================================================================
Write-Activity "Collecting provisioned AppX packages..." -Level INFO -Source 'AppXCleanup'

$selectors = @(
    'Microsoft.Microsoft3DViewer'; 'Microsoft.BingSearch'; 'Microsoft.WindowsCamera';
    'Clipchamp.Clipchamp'; 'Microsoft.WindowsAlarms'; 'Microsoft.549981C3F5F10';
    'Microsoft.Windows.DevHome'; 'MicrosoftCorporationII.MicrosoftFamily';
    'Microsoft.WindowsFeedbackHub'; 'Microsoft.GetHelp'; 'Microsoft.Getstarted';
    'microsoft.windowscommunicationsapps'; 'Microsoft.WindowsMaps';
    'Microsoft.MixedReality.Portal'; 'Microsoft.BingNews';
    'Microsoft.MicrosoftOfficeHub'; 'Microsoft.Office.OneNote';
    'Microsoft.OutlookForWindows'; 'Microsoft.Paint'; 'Microsoft.MSPaint';
    'Microsoft.People'; 'Microsoft.Windows.Photos'; 'Microsoft.PowerAutomateDesktop';
    'MicrosoftCorporationII.QuickAssist'; 'Microsoft.SkypeApp';
    'Microsoft.MicrosoftSolitaireCollection'; 'Microsoft.MicrosoftStickyNotes';
    'MicrosoftTeams'; 'MSTeams'; 'Microsoft.Todos';
    'Microsoft.WindowsSoundRecorder'; 'Microsoft.Wallet'; 'Microsoft.BingWeather';
    'Microsoft.YourPhone'; 'Microsoft.ZuneMusic'; 'Microsoft.ZuneVideo';
)

$getCommand = { Get-AppxProvisionedPackage -Online }
$filterCommand = { $_.DisplayName -eq $selector }
$removeCommand = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $InputObject
    )
    process {
        $InputObject | Remove-AppxProvisionedPackage -AllUsers -Online -ErrorAction 'Continue'
    }
}

& {
    $installed = & $getCommand
    foreach ($selector in $selectors) {
        $result = [ordered]@{ Selector = $selector }
        $found = $installed | Where-Object -FilterScript $filterCommand

        if ($found) {
            try {
                $found | & $removeCommand
                if ($?) {
                    $result.Message = "App '$selector' removed."
                    Write-Activity "App '$selector' removed." -Level INFO -Source 'AppXCleanup'
                }
                else {
                    $result.Message = "App '$selector' NOT removed."
                    Write-Activity "App '$selector' NOT removed." -Level WARN -Source 'AppXCleanup'
                }
            }
            catch {
                $result.Message = "App '$selector' removal ERROR: $_"
                Write-Activity "App '$selector' removal ERROR: $_" -LEVEL ERROR -Source 'AppXCleanup'
            }
        }
        else {
            $result.Message = "App '$selector' not installed."
            Write-Activity "App '$selector' not installed." -Level ERROR -Source 'AppXCleanup'
        }

        $result | ConvertTo-Json -Depth 3 -Compress
    }
}

# ====================================================================
# Summary and Runtime
# ====================================================================
Write-Activity "==================== END APPX CLEANUP ====================" -Level INFO -Source 'AppXCleanup'
Stop-ScriptTimer