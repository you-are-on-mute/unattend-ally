<#
  .SYNOPSIS
  Runs OS specialization tasks during deployment.  

  .DESCRIPTION
  Specialize.ps1 runs during the Windows "specialize" phase, handling 
  power configuration, feature removal, capability trimming, and other setup tasks.

  .PARAMETER InputPath
  None

  .PARAMETER OutputPath
  None

  .INPUTS
  None. You can't pipe objects to specialize.ps1.

  .OUTPUTS
  None. specialize.ps1 doesn't generate any output.

  .EXAMPLE
  PS> .\specialize.ps1
#>

# ====================================================================
# Event Logging Module Initialization
# ====================================================================
$ModulePath = "$env:SystemRoot\setup\Scripts\Modules\OSDeployLogging\OSDeployLogging.psm1"
if (Test-Path $ModulePath) {
	Import-Module $ModulePath -Force
	Initialize-OSDeployLogging
	Set-PhaseTag "Specialize"
	Start-ScriptTimer
} 
else {
	Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Logging module not found at ${ModulePath}" -ForegroundColor Red
}

Write-Activity "==================== BEGIN SPECIALIZE INSTALL ====================" -Level INFO -Source 'Specialize'

# ====================================================================
# Elevation check
# ====================================================================
Write-Activity "Checking for elevation..." -Level INFO -Source 'Drivers'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
	Write-Activity "You must run this script as Administrator. Aborting..." -Level ERROR -Source 'Specialize'
	Stop-ScriptTimer
	Stop-OSDeployLogging
	exit
}

# ====================================================================
# Configure Power Plan
# ====================================================================
Write-Activity "Configuring temporary High Performance power plan..." -Level INFO -Source 'Specialize'
$highPerfGuid = powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Select-String -Pattern "Power Scheme GUID: ([\w-]+)" | % { $_.Matches[0].Groups[1].Value }

# Activate the temporary "High Performance" plan
Write-Activity "Activate the High Performance Plan" -Level INFO -Source 'Specialize'
powercfg -setactive $highPerfGuid

# Disable sleep parameters on this temporary plan
@(	"hibernate-timeout-ac", "hibernate-timeout-dc",
	"disk-timeout-ac", "disk-timeout-dc",
	"monitor-timeout-ac", "monitor-timeout-dc",
	"standby-timeout-ac", "standby-timeout-dc"
) | ForEach-Object { powercfg /x -$_ 0 }

# ====================================================================
# Registry Tweaks
# ====================================================================
Write-Activity "Applying registry customizations..." -Level INFO -Source 'Specialize'

$regTasks = @(
	@{ Path = 'HKLM:\Software\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe'; Name = 'DevHomeUpdate'; Action = 'Remove' },
	@{ Path = 'HKLM:\Software\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe'; Name = 'OutlookUpdate'; Action = 'Remove' },
	@{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications'; Name = 'ConfigureChatAutoInstall'; Value = 0; Type = 'DWORD' },
	@{ Path = 'HKLM:\Software\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableCloudOptimizedContent'; Value = 1; Type = 'DWORD' },
	@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Value = 0; Type = 'DWORD' },
	@{ Path = 'HKLM:\Software\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Value = 1; Type = 'DWORD' },
	@{ Path = 'HKLM:\Software\Policies\Microsoft\Edge'; Name = 'HideFirstRunExperience'; Value = 1; Type = 'DWORD' },
	@{ Path = 'HKLM:\Software\Policies\Microsoft\Edge\Recommended'; Name = 'BackgroundModeEnabled'; Value = 0; Type = 'DWORD' },
	@{ Path = 'HKLM:\Software\Policies\Microsoft\Edge\Recommended'; Name = 'StartupBoostEnabled'; Value = 0; Type = 'DWORD' },
	@{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'EnableFirstLogonAnimation'; Value = 0; Type = 'DWORD' },
	@{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; Name = 'EnableFirstLogonAnimation'; Value = 0; Type = 'DWORD' }
)

foreach ($task in $regTasks) {
	try {
		if ($task.Action -eq 'Remove') {
			Remove-ItemProperty -Path $task.Path -Name $task.Name -ErrorAction SilentlyContinue
			Write-Activity "Removed registry key $($task.Path)\$($task.Name)" -Level INFO -Source 'Specialize'
		}
		else {
			if (-not (Test-Path $task.Path)) { New-Item -Path $task.Path -Force | Out-Null }
			New-ItemProperty -Path $task.Path -Name $task.Name -PropertyType $task.Type -Value $task.Value -Force | Out-Null
			Write-Activity "Set registry $($task.Path)\$($task.Name) = $($task.Value)" -Level INFO -Source 'Specialize'
		}
	}
 catch {
		Write-Activity "Error modifying registry $($task.Path)\$($task.Name): $_" -Level ERROR -Source 'Specialize'
	}
}

# ====================================================================
# Run Nested Scripts (Drivers first)
# ====================================================================
$scriptPath = "$env:SystemRoot\Setup\Scripts"
$nestedScripts = @(
	"Drivers.ps1",   
	"RemoveAppX.ps1",      
	"RemoveFeatures.ps1",
	"RemoveCapabilities.ps1",
	"SetStartPins.ps1",
	"RenamePC.ps1"
)

foreach ($scriptName in $nestedScripts) {
	$fullPath = Join-Path $scriptPath $scriptName
	if (Test-Path $fullPath) {
		Write-Activity "Running nested script: ${scriptName}" -Level INFO -Source 'Specialize'
		$start = Get-Date
		try {
			& $fullPath
			$duration = (Get-Date) - $start
			Write-Activity "${scriptName} completed in $($duration.ToString('hh\:mm\:ss'))" -Level INFO -Source 'Specialize'
		}
		catch {
			Write-Activity "Error executing ${scriptName}: $_" -Level ERROR -Source 'Specialize'
		}
	}
 else {
		Write-Activity "Nested script not found: ${scriptName}" -Level WARN -Source 'Specialize'
	}
}

# ====================================================================
# Import Wi-Fi Profiles (if present)
# ====================================================================
Write-Activity "Checking for WiFi adapters before importing profiles..." -Level INFO -Source 'WiFi'
Get-ChildItem $scriptPath | Where-Object { $_.Name -match "WiFi" } | ForEach-Object { netsh wlan add profile filename=(Join-Path $scriptPath $_.Name) } -Verbose;
Start-Sleep -Seconds 5;
Write-Activity "Add WiFi Profile" -Level INFO -Source 'WiFi'

# ====================================================================
# Local Account Policy - Password Age
# ====================================================================
try {
	net.exe accounts /maxpwage:UNLIMITED | Out-Null
	Write-Activity "Max Password Age set to Unlimited" -Level INFO -Source 'Specialize'
}
catch {
	Write-Activity "Failed to set Max Password Age: $_" -Level ERROR -Source 'Specialize'
}

# ====================================================================
# Restore Power Plan
# ====================================================================
Write-Activity "Restoring Balanced power plan..." -Level INFO -Source 'Specialize'
$balancedGuid = powercfg -list | Select-String -Pattern "\((Balanced)\)" | ForEach-Object { $_.Line.Split()[3].Trim('(', ')') }
powercfg -setactive $balancedGuid; powercfg -delete $highPerfGuid

## If no battery is present, disable hibernation and fast startup
if ((@(Get-WmiObject Win32_Battery).count) -eq 0) { powercfg -h off }

# ====================================================================
# System Info
# ====================================================================
$osInfo = Get-ComputerInfo | Select-Object -First 1 OSName, OSVersion, OsHardwareAbstractionLayer
$osVersionString = "$($osInfo.OSName); $($osInfo.OSVersion); $($osInfo.OsHardwareAbstractionLayer)"
$buildVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion

$hostinfo = [PSCustomObject]@{
	Name         = $env:COMPUTERNAME
	OSVersion    = $osVersionString
	BuildVersion = $buildVersion
}
$hostinfo | Out-File -FilePath "C:\host.txt" -Force
Write-Activity "System Info: $($hostinfo | Out-String)" -Level INFO -Source 'Specialize'

# ====================================================================
# Wrap up
# ====================================================================
Write-Activity "==================== END SPECIALIZE PHASE ====================" -Level INFO -Source 'Specialize'
Stop-ScriptTimer
Stop-OSDeployLogging