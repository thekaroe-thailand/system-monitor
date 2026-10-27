param([switch]$Remove)

# Adds (or removes with -Remove) a shortcut in the user's Startup folder so the gadget opens at login.
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'system-monitor.lnk'

if ($Remove) {
    if (Test-Path $lnk) { Remove-Item $lnk; 'Removed startup shortcut.' } else { 'No startup shortcut found.' }
    return
}

$shell = New-Object -ComObject WScript.Shell
$s = $shell.CreateShortcut($lnk)
$s.TargetPath = Join-Path $PSScriptRoot 'start-monitor.vbs'
$s.WorkingDirectory = $PSScriptRoot
$s.Save()
"Created: $lnk"
