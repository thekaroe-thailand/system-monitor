# system-monitor installer. One-liner (run in cmd or PowerShell):
#   powershell -NoProfile -Command "irm https://raw.githubusercontent.com/thekaroe-thailand/system-monitor/v1.3.0/install.ps1 | iex"
# Re-running it installs/updates to the version pinned in $ref below (the gadget also checks for updates itself, daily).
# NOTE: keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI).
$ErrorActionPreference = 'Stop'
$repo       = 'thekaroe-thailand/system-monitor'
$ref        = 'v1.3.0'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\system-monitor'
$files      = 'monitor.ps1', 'start-monitor.vbs', 'claude-usage-hook.ps1', 'uninstall.ps1', 'README.md'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "Installing system-monitor $ref ..."

# stop a running installed copy so files can be replaced
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$installDir*monitor.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

# download + unpack
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('system-monitor-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    $zip = Join-Path $tmp 'src.zip'
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$repo/archive/$ref.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $src = Get-ChildItem $tmp -Directory | Select-Object -First 1
    New-Item -ItemType Directory -Force $installDir | Out-Null
    foreach ($f in $files) { Copy-Item (Join-Path $src.FullName $f) $installDir -Force }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# start with Windows
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'system-monitor.lnk'
$sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$sc.TargetPath = Join-Path $installDir 'start-monitor.vbs'
$sc.WorkingDirectory = $installDir
$sc.Save()

# optional: show Claude Code 5hr / weekly usage in the gadget (edits ~\.claude\settings.json)
function Enable-ClaudeUsage {
    $settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
    try {
        $json = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
        $cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $installDir 'claude-usage-hook.ps1') + '"'
        if ($json.PSObject.Properties['statusLine']) {
            $existing = [string]$json.statusLine.command
            if ($existing -notlike '*claude-usage-hook.ps1*') {
                Write-Host 'Claude Code already has a different statusLine configured - left it unchanged, so Claude usage will show "--".'
                return
            }
            if ($existing -like "*$installDir*") {
                Write-Host 'Claude usage is already set up.'
                return
            }
            # ours, but pointing at another copy (e.g. a source folder): point it at the installed copy
            Copy-Item $settingsPath "$settingsPath.bak-system-monitor" -Force
            $json.statusLine.command = $cmd
        } else {
            if (Test-Path $settingsPath) { Copy-Item $settingsPath "$settingsPath.bak-system-monitor" -Force }
            $json | Add-Member -NotePropertyName statusLine -NotePropertyValue ([pscustomobject]@{ type = 'command'; command = $cmd })
        }
        New-Item -ItemType Directory -Force (Split-Path $settingsPath) | Out-Null
        [IO.File]::WriteAllText($settingsPath, ($json | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
        Write-Host 'Claude usage enabled (backup: settings.json.bak-system-monitor). It updates while you use the Claude Code CLI.'
    } catch {
        Write-Host "Could not edit Claude settings automatically: $($_.Exception.Message)"
    }
}

$answer = $env:SM_CLAUDE_USAGE
if (-not $answer) {
    try { $answer = Read-Host 'Show Claude Code usage (5hr / weekly) in the gadget? This edits ~\.claude\settings.json [y/N]' } catch { $answer = 'n' }
}
if ($answer -match '^(y|yes)$') { Enable-ClaudeUsage }

# launch
Start-Process wscript.exe -ArgumentList ('"' + (Join-Path $installDir 'start-monitor.vbs') + '"')
Write-Host "Done. Installed to $installDir. Right-click the gadget for Settings / Exit."
