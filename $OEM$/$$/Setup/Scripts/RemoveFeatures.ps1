<#
  .SYNOPSIS
  Removes unwanted Windows Optional Features during the Specialize phase.

  .DESCRIPTION
  This script disables or removes specified Windows optional features that are not required in the deployment.
  It logs to the host, event log, and the unified deployment log via the OSDeployLogging module.
  
  .PARAMETER InputPath
  None

  .PARAMETER OutputPath
  None

  .INPUTS
  None. You can't pipe objects to RemoveFeatures.ps1.

  .OUTPUTS
  None. RemoveFeatures.ps1 doesn't generate any output.

  .EXAMPLE
  PS> .\RemoveFeatures.ps1
#>

# ====================================================================
# Logging
# ====================================================================
Set-PhaseTag "Features"
Start-ScriptTimer
Write-Activity "==================== REMOVE FEATURES ====================" -Level INFO -Source 'Features'

# ====================================================================
# Elevation check
# ====================================================================
Write-Activity "Checking for elevation..." -Level INFO -Source 'StartPins'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
		[Security.Principal.WindowsBuiltInRole] "Administrator")) {
	Write-Activity "You must run this script as Administrator. Aborting..." -Level ERROR -Source 'Features'
	Stop-ScriptTimer
	exit
}
# ====================================================================
# Feature Removal Logic
# ====================================================================
$selectors = @(
	'MediaPlayback'
	'MicrosoftWindowsPowerShellV2Root'
	'Recall'
)

Write-Activity "Beginning removal of $($selectors.Count) features..." -Level INFO -Source 'Features'

try {
	$installed = Get-WindowsOptionalFeature -Online | Where-Object {
		$_.State -notin @('Disabled', 'DisabledWithPayloadRemoved')
	}

	foreach ($selector in $selectors) {
		Write-Activity "Checking feature: ${selector}" -Level DEBUG -Source 'Features'
		$found = $installed | Where-Object { $_.FeatureName -eq $selector }

		if ($found) {
			Write-Activity "Attempting to remove ${selector}..." -Level INFO -Source 'Features'
			try {
				$found | Disable-WindowsOptionalFeature -Online -Remove -NoRestart -ErrorAction Stop
				Write-Activity "${selector} removed successfully." -Level INFO -Source 'Features'
			}
			catch {
				Write-Activity "Failed to remove ${selector}: ${($_.Exception.Message)}" -Level ERROR -Source 'Features'
			}
		}
		else {
			Write-Activity "${selector} not installed or already removed." -Level WARN -Source 'Features'
		}
	}
}
catch {
	Write-Activity "Unexpected error during feature removal: ${($_.Exception.Message)}" -Level ERROR -Source 'Features'
}

# ====================================================================
# Summary and Runtime
# ====================================================================
Write-Activity "==================== END FEATURE REMOVAL ====================" -Level INFO -Source 'Features'
Stop-ScriptTimer