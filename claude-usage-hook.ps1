# Claude Code statusLine command: saves rate_limits (5hr / weekly) to a file the gadget reads,
# and prints a short status line. NOTE: keep this file ASCII-only.
$raw = [Console]::In.ReadToEnd()
try {
    $j = $raw | ConvertFrom-Json
    if ($j.rate_limits) {
        $dir = Join-Path $env:LOCALAPPDATA 'system-monitor'
        New-Item -ItemType Directory -Force $dir | Out-Null
        $tmp = Join-Path $dir 'claude-usage.tmp'
        [pscustomobject]@{
            updatedAt   = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            rate_limits = $j.rate_limits
        } | ConvertTo-Json -Depth 8 | Set-Content $tmp -Encoding UTF8
        Move-Item $tmp (Join-Path $dir 'claude-usage.json') -Force
        $fh = $j.rate_limits.five_hour
        $sd = $j.rate_limits.seven_day
        if ($fh -and $sd) { '5h {0}% | 7d {1}%' -f [math]::Round($fh.used_percentage), [math]::Round($sd.used_percentage) }
    }
} catch { }
