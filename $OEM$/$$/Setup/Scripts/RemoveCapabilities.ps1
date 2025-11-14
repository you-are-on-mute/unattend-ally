<#
  .SYNOPSIS
  Removes unwanted Windows capabilities during the Specialize phase.

  .DESCRIPTION
  This script removes preinstalled Windows optional capabilities such as Paint,
  WordPad, IE, Hello Face, and others. It is called from autounattend.xml during
  the Specialize phase.ing the WinPE phase of the deployment. It is called from the autounattend.xml file.

  .PARAMETER InputPath
  None

  .PARAMETER OutputPath
  None

  .INPUTS
  None. You can't pipe objects to RemoveCapabilities.ps1.

  .OUTPUTS
  None. RemoveCapabilities.ps1 doesn't generate any output.

  .EXAMPLE
  PS> .\RemoveCapabilities.ps1
#>

# ====================================================================
# Logging
# ====================================================================
Set-PhaseTag "Capabilities"
Start-ScriptTimer
Write-Activity "==================== REMOVE CAPABILITIES ====================" -Level INFO -Source 'Capabilities'

# ====================================================================
# Elevation check
# ====================================================================
Write-Activity "Checking for elevation..." -Level INFO -Source 'StartPins'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
		[Security.Principal.WindowsBuiltInRole] "Administrator")) {
	Write-Activity "You must run this script as Administrator. Aborting..." -Level ERROR -Source 'Capabilities'
	Stop-ScriptTimer
	exit
}

# ====================================================================
# Capability Removal Logic
# ====================================================================
$selectors = @(
	'Print.Fax.Scan';
	'Language.Handwriting';
	'Browser.InternetExplorer';
	'MathRecognizer';
	'OneCoreUAP.OneSync';
	'OpenSSH.Client';
	'Microsoft.Windows.MSPaint';
	'App.Support.QuickAssist';
	'Language.Speech';
	'Language.TextToSpeech';
	'App.StepsRecorder';
	'Hello.Face.18967';
	'Hello.Face.Migration.18967';
	'Hello.Face.20134';
	'Media.WindowsMediaPlayer';
	'Microsoft.Windows.WordPad';
);

Write-Activity "Enumerating installed Windows capabilities..." -Level INFO -Source 'Capabilities'

try {
	$installedCapabilities = Get-WindowsCapability -Online | Where-Object {
		$_.State -notin @('NotPresent', 'Removed')
	}
}
catch {
	Write-Activity "Error retrieving capabilities: ${($_.Exception.Message)}" -Level ERROR -Source 'Capabilities'
	Stop-ScriptTimer "RemoveCapabilities.ps1"
	Stop-OSDeployLogging
	exit 1
}

foreach ($selector in $selectors) {
	try {
		$found = $installedCapabilities | Where-Object { ($_.Name -split '~')[0] -eq $selector }

		if ($found) {
			Write-Activity "Removing capability: ${selector}" -Level INFO -Source 'Capabilities'
			$found | Remove-WindowsCapability -Online -ErrorAction Continue | Out-Null

			if ($?) {
				Write-Activity "Capability ${selector} removed successfully." -Level INFO -Source 'Capabilities'
			}
			else {
				Write-Activity "Failed to remove capability ${selector}." -Level ERROR -Source 'Capabilities'
			}
		}
		else {
			Write-Activity "Capability ${selector} not installed or already removed." -Level WARN -Source 'Capabilities'
		}
	}
	catch {
		Write-Activity "Error while processing ${selector}: ${($_.Exception.Message)}" -Level ERROR -Source 'Capabilities'
	}
}

# ====================================================================
# Summary and Runtime
# ====================================================================
Write-Activity "==================== END CAPABILITY REMOVAL ====================" -Level INFO -Source 'Capabilities'
Stop-ScriptTimer