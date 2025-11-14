<#
  .SYNOPSIS
  Final user-level configuration script run once at first logon.  

  .DESCRIPTION
  This script applies per-user customizations after the first logon.
  It removes unwanted packages, updates registry settings for Explorer and Search,
  and refreshes the shell. Logging is handled via the OSDeployLogging module.

  .PARAMETER InputPath
  None

  .PARAMETER OutputPath
  None

  .INPUTS
  None. You can't pipe objects to UserOnce.ps1.

  .OUTPUTS
  None. UserOnce.ps1 doesn't generate any output.

  .EXAMPLE
  PS> .\UserOnce.ps1
#>

# ====================================================================
# Event Logging Module
# ====================================================================
$modulePath = "$env:SystemRoot\setup\Scripts\Modules\OSDeployLogging\OSDeployLogging.psm1"
Import-Module $modulePath -Force

Initialize-OSDeployLogging
Set-PhaseTag "UserOnce"
Start-ScriptTimer

Write-Activity "==================== BEGIN USERONCE CONFIGURATION ====================" -Level INFO -Source 'UserOnce'

# ====================================================================
# Scripted user actions
# ====================================================================

$scripts = @(
  {
    Write-Activity "Removing Windows Copilot package for user $env:USERNAME" -Level INFO -Source 'UserOnce'
    Get-AppxPackage -Name 'Microsoft.Windows.Ai.Copilot.Provider' -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
  };
  {
    Write-Activity "Unlocking Start menu layout for user $env:USERNAME" -Level INFO -Source 'UserOnce'
    # (previously wrote an event log entry — now handled by module)
  };
  {
    Write-Activity "Setting File Explorer launch mode to 'This PC'" -Level INFO -Source 'UserOnce'
    Set-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'LaunchTo' -Type 'DWord' -Value 1
  };
  {
    Write-Activity "Hiding search box from taskbar" -Level INFO -Source 'UserOnce'
    Set-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Type 'DWord' -Value 0
  };
  {
    Write-Activity "Restarting File Explorer for user session" -Level INFO -Source 'UserOnce'
    Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Where-Object {
      $_.SessionId -eq (Get-Process -Id $PID).SessionId
    } | Stop-Process -Force
  }
)

# ====================================================================
# Execution
# ====================================================================
[float] $complete = 0
[float] $increment = 100 / $scripts.Count

foreach ($script in $scripts) {
  Write-Progress -Activity "Applying user-level settings..." -PercentComplete $complete
  try {
    $start = Get-Date
    & $script
    $elapsed = (Get-Date) - $start
    Write-Activity "Script block completed in $($elapsed.TotalMilliseconds) ms" -Level INFO -Source 'UserOnce'
  }
  catch {
    Write-Activity "Error executing user configuration block: $_" -Level ERROR -Source 'UserOnce'
  }
  $complete += $increment
}

# ====================================================================
# Wrap-up
# ====================================================================
Write-Activity "==================== END USERONCE CONFIGURATION ====================" -Level INFO -Source 'UserOnce'
Stop-ScriptTimer
Stop-OSDeployLogging