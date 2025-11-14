<#
  .SYNOPSIS
  Applies default user configuration during deployment.

  .DESCRIPTION
  This script modifies registry settings under HKU\DefaultUser to configure
  default preferences for new user profiles. It runs during the specialize
  or default user setup phase and triggers UserOnce.ps1 on first logon.

  .PARAMETER InputPath
  None

  .PARAMETER OutputPath
  None

  .INPUTS
  None. You can't pipe objects to DefaultUser.ps1.

  .OUTPUTS
  None. DefaultUser.ps1 doesn't generate any output.

  .EXAMPLE
  PS> .\DefaultUser.ps1
#>

# ====================================================================
# Event Logging Module Initialization
# ====================================================================
$ModulePath = "$env:SystemRoot\setup\Scripts\Modules\OSDeployLogging\OSDeployLogging.psm1"
if (Test-Path $ModulePath) {
	Import-Module $ModulePath -Force
	Initialize-OSDeployLogging
	Set-PhaseTag "DefaultUser"
	Start-ScriptTimer
} 
else {
	Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Logging module not found at ${ModulePath}" -ForegroundColor Red
}

Write-Activity "==================== BEGIN DEFAULT USER CONFIGURATION ====================" -Level INFO -Source 'DefaultUser'

# ====================================================================
# Event Logging Module
# ====================================================================
Import-Module "$env:SystemRoot\setup\Scripts\Modules\OSDeployLogging\OSDeployLogging.psm1" -Force
Initialize-OSDeployLogging
Set-PhaseTag "DefaultUser"
Start-ScriptTimer

Write-Activity "==================== DEFAULT USER CONFIGURATION ====================" -Level INFO -Source 'DefaultUser'

# ====================================================================
# Elevation Check
# ====================================================================
Write-Activity "Checking for elevation..." -Level INFO -Source 'DefaultUser'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
		[Security.Principal.WindowsBuiltInRole] "Administrator"
	)) {
	Write-Activity "You must run this script as Administrator. Aborting..." -Level ERROR -Source 'DefaultUser'
	Stop-ScriptTimer
	Stop-OSDeployLogging
	exit
}

# ====================================================================
# Default User Registry Configuration
# ====================================================================
Write-Activity "Applying registry modifications to Default User hive..." -Level INFO -Source 'DefaultUser'

$scripts = @(
	{ reg.exe add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f;
		Write-Activity "Disabled Windows Copilot" -Level INFO -Source "Registry"; },

	{ Remove-ItemProperty -LiteralPath 'Registry::HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSetup' -Force -ErrorAction Continue;
		Write-Activity "Removed OneDrive auto-run" -Level INFO -Source "Registry"; },

	{ reg.exe add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\GameDVR" /v AppCaptureEnabled /t REG_DWORD /d 0 /f;
		Write-Activity "Disabled GameDVR capture" -Level INFO -Source "Registry"; },

	{ reg.exe add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\Explorer" /v "StartLayoutFile" /t REG_SZ /d "C:\Windows\Setup\Scripts\TaskbarLayoutModification.xml" /f;
		reg.exe add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\Explorer" /v "LockedStartLayout" /t REG_DWORD /d 1 /f;
		Write-Activity "Applied custom start layout and locked configuration" -Level INFO -Source "Registry"; },

	{ reg.exe add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f;
		Write-Activity "Hide Task View button" -Level INFO -Source "Registry"; },

	{ reg.exe add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v "Wallpaper" /t REG_SZ /d "C:\Windows\Web\Wallpaper\ThemeD\img32.jpg" /f;
		Write-Activity "Set default wallpaper" -Level INFO -Source "Registry"; },

	{ reg.exe add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" /v "NOC_GLOBAL_SETTING_TOASTS_ENABLED" /t REG_DWORD /d 1 /f;
		Write-Activity "Enabled toast notifications" -Level INFO -Source "Registry"; },

	{
		$contentKeys = @(
			'ContentDeliveryAllowed', 'FeatureManagementEnabled', 'OEMPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
			'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled', 'SoftLandingEnabled', 'SubscribedContentEnabled',
			'SubscribedContent-310093Enabled', 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled',
			'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled', 'SubscribedContent-353698Enabled',
			'SystemPaneSuggestionsEnabled'
		)
		foreach ($name in $contentKeys) {
			reg.exe add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v $name /t REG_DWORD /d 0 /f | Out-Null
			Write-Activity "Disabled $name content feature" -Level INFO -Source "Registry"
		}
	},

	{ reg.exe add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsSpotlightFeatures /t REG_DWORD /d 1 /f;
		reg.exe add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\CloudContent" /v ConfigureWindowsSpotlight /t REG_DWORD /d 2 /f;
		Write-Activity "Disabled Windows Spotlight features" -Level INFO -Source "Registry"; },

	{ reg.exe add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f;
		Write-Activity "Disabled search box suggestions" -Level INFO -Source "Registry"; },

	{ reg.exe add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" /v TaskbarEndTask /t REG_DWORD /d 1 /f;
		reg.exe add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\Explorer" /v HideRecommendedPersonalizedSites /t REG_DWORD /d 1 /f;
		Write-Activity "Enabled taskbar end task and hide personalized sites" -Level INFO -Source "Registry"; },

	{ reg.exe add "HKU\DefaultUser\Software\Microsoft\Edge" /v HideFirstRunExperience /t REG_DWORD /d 1 /f;
		Write-Activity "Suppressed Edge FirstRun experience" -Level INFO -Source "Registry"; },

	{ reg.exe add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "UnattendedSetup" /t REG_SZ /d "powershell.exe -WindowStyle Normal -NoProfile -ExecutionPolicy Bypass -Command \""Get-Content -LiteralPath 'C:\Windows\Setup\Scripts\UserOnce.ps1' -Raw | Invoke-Expression;\""" /f;
		Write-Activity "Registered UserOnce script for first logon" -Level INFO -Source "Registry"; }
)

# ====================================================================
# Execute Registry Tasks
# ====================================================================
[float]$complete = 0
[float]$increment = 100 / $scripts.Count

foreach ($scriptBlock in $scripts) {
	Write-Progress -Activity "Configuring Default User registry..." -PercentComplete $complete
	$preview = $scriptBlock.ToString().Trim() -replace '\s+', ' '
	Write-Activity "Executing registry script block: $preview" -Level DEBUG -Source 'DefaultUser'
	try {
		$start = Get-Date
		& $scriptBlock
		$elapsed = (Get-Date) - $start
		Write-Activity "Completed in $($elapsed.TotalMilliseconds) ms" -Level DEBUG -Source 'DefaultUser'
	}
	catch {
		Write-Activity "Error executing registry script block: $_" -Level ERROR -Source 'DefaultUser'
	}
	$complete += $increment
}

# ====================================================================
# Summary and Runtime
# ====================================================================
Write-Activity "==================== END DEFAULT USER CONFIGURATION ====================" -Level INFO -Source 'DefaultUser'
Stop-ScriptTimer
Stop-OSDeployLogging