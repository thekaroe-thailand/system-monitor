# system-monitor uninstaller. One-liner:
#   powershell -NoProfile -Command "irm https://raw.githubusercontent.com/thekaroe-thailand/system-monitor/v1.3.0/uninstall.ps1 | iex"
# NOTE: keep this file ASCII-only.
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\system-monitor'
$dataDir    = Join-Path $env:LOCALAPPDATA 'system-monitor'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$installDir*monitor.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'system-monitor.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force }

# remove the Claude statusLine only if it points at our hook
$settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
if (Test-Path $settingsPath) {
    try {
        $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
        if ($json.statusLine -and $json.statusLine.command -like '*claude-usage-hook.ps1*') {
            Copy-Item $settingsPath "$settingsPath.bak-system-monitor" -Force
            $json.PSObject.Properties.Remove('statusLine')
            [IO.File]::WriteAllText($settingsPath, ($json | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
            Write-Host 'Removed the Claude Code statusLine entry (backup: settings.json.bak-system-monitor).'
        }
    } catch { Write-Host "Could not edit Claude settings: $($_.Exception.Message)" }
}

Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'system-monitor uninstalled.'
