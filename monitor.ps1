param([switch]$DumpMetrics)

# System monitor gadget: CPU / RAM / Disk / Network, bottom-right, always on top.
# NOTE: keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI).

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName Microsoft.VisualBasic

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
}
"@

$GWL_EXSTYLE      = -20
$WS_EX_TOOLWINDOW = 0x00000080
$WS_EX_NOACTIVATE = 0x08000000
$HWND_TOPMOST     = [IntPtr](-1)
$SWP_FLAGS        = 0x0001 -bor 0x0002 -bor 0x0010 -bor 0x0040   # NOSIZE | NOMOVE | NOACTIVATE | SHOWWINDOW

# ---- counters ----
$cpuCounter = New-Object Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total')
$null = $cpuCounter.NextValue()

$nicNames = (New-Object Diagnostics.PerformanceCounterCategory('Network Interface')).GetInstanceNames() |
    Where-Object { $_ -notmatch 'Loopback|isatap' }
$rxCounters = @($nicNames | ForEach-Object { New-Object Diagnostics.PerformanceCounter('Network Interface', 'Bytes Received/sec', $_) })
$txCounters = @($nicNames | ForEach-Object { New-Object Diagnostics.PerformanceCounter('Network Interface', 'Bytes Sent/sec', $_) })
foreach ($c in $rxCounters + $txCounters) { $null = $c.NextValue() }

$sysDrive = $env:SystemDrive.TrimEnd('\')
$compInfo = New-Object Microsoft.VisualBasic.Devices.ComputerInfo

function Format-Speed([double]$bytes) {
    if ($bytes -ge 1MB) { '{0:N1} MB/s' -f ($bytes / 1MB) }
    elseif ($bytes -ge 1KB) { '{0:N0} KB/s' -f ($bytes / 1KB) }
    else { '{0:N0} B/s' -f $bytes }
}

function Get-Metrics {
    $total = [double]$compInfo.TotalPhysicalMemory
    $used  = $total - [double]$compInfo.AvailablePhysicalMemory
    $drive = New-Object IO.DriveInfo($sysDrive)
    $rx = 0.0; foreach ($c in $rxCounters) { $rx += $c.NextValue() }
    $tx = 0.0; foreach ($c in $txCounters) { $tx += $c.NextValue() }
    [pscustomobject]@{
        Cpu       = [math]::Min(100, [math]::Round($cpuCounter.NextValue(), 0))
        RamPct    = [math]::Round($used / $total * 100, 0)
        RamUsedGB = $used / 1GB
        RamTotGB  = $total / 1GB
        DiskPct   = [math]::Round(($drive.TotalSize - $drive.AvailableFreeSpace) / $drive.TotalSize * 100, 0)
        DiskFreeGB = $drive.AvailableFreeSpace / 1GB
        Down      = $rx
        Up        = $tx
    }
}

if ($DumpMetrics) {
    Start-Sleep -Seconds 1
    Get-Metrics | Format-List
    return
}

# ---- UI ----
# ---- user settings (saved to %LOCALAPPDATA%\system-monitor\settings.json) ----
$settingsFile = Join-Path $env:LOCALAPPDATA 'system-monitor\settings.json'
$AppVersion = '1.3.0'
$repoSlug   = 'thekaroe-thailand/system-monitor'
# <Provider>Key values are DPAPI-encrypted (ConvertFrom-SecureString)
$settings = @{ Transparency = 25; ShowCalendar = $true; ShowClaude = $true; Collapsed = $false
               AutoCheckUpdates = $true; LastUpdateCheck = 0; LatestTag = ''
               AutoInstallUpdates = $true; LastAutoAttemptTag = ''; LastAutoAttemptAt = 0
               LiveClaudeUsage = $false; ShowCodex = $true
               OllamaKey = ''; ShowOllama = $true; OpenRouterKey = ''; ShowOpenRouter = $true; DeepSeekKey = ''; ShowDeepSeek = $true }
if (Test-Path $settingsFile) {
    try {
        $saved = Get-Content $settingsFile -Raw | ConvertFrom-Json
        foreach ($k in @($settings.Keys)) { if ($null -ne $saved.$k) { $settings[$k] = $saved.$k } }
    } catch { }
}
$settings.Transparency = [math]::Min(90, [math]::Max(0, [int]$settings.Transparency))

function Save-Settings {
    New-Item -ItemType Directory -Force (Split-Path $settingsFile) | Out-Null
    $settings | ConvertTo-Json | Set-Content $settingsFile -Encoding UTF8
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" Topmost="True" ResizeMode="NoResize"
        Width="210" SizeToContent="Height" ShowActivated="False">
  <Border Name="Root" CornerRadius="8" Background="#C0181818" Padding="10,8">
    <Border.ContextMenu>
      <ContextMenu>
        <MenuItem Name="MenuVer" IsEnabled="False"/>
        <Separator/>
        <MenuItem Name="MenuSettings" Header="Settings..."/>
        <MenuItem Name="MenuHide" Header="Hide"/>
        <MenuItem Name="MenuExit" Header="Exit"/>
      </ContextMenu>
    </Border.ContextMenu>
    <Grid>
    <StackPanel Name="FullPanel">
    <Grid Margin="0,-3,-4,0">
    <TextBlock Name="VerText" Foreground="#9AA0A6" FontSize="11" VerticalAlignment="Center" HorizontalAlignment="Left"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <TextBlock Name="BtnUpdate" Foreground="#26A69A" FontSize="11" Cursor="Hand" Visibility="Collapsed"
                 VerticalAlignment="Center" Padding="4,0" ToolTip="Update available - click to open Settings"/>
      <TextBlock Name="BtnSettings" Foreground="#9AA0A6" FontFamily="Segoe UI Symbol" FontSize="13" Cursor="Hand"
                 ToolTip="Settings" Padding="4,0"/>
      <TextBlock Name="BtnHide" Foreground="#9AA0A6" FontFamily="Segoe UI Symbol" FontSize="13" Cursor="Hand"
                 ToolTip="Collapse" Padding="4,0"/>
    </StackPanel>
    </Grid>
    <Grid Name="MainGrid" Height="117">
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/><RowDefinition Height="*"/><RowDefinition Height="*"/><RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="42"/><ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Row="0" Foreground="#9AA0A6" FontSize="12" Text="CPU" VerticalAlignment="Center"/>
      <StackPanel Grid.Row="0" Grid.Column="1" VerticalAlignment="Center">
        <TextBlock Name="CpuText" Foreground="White" FontSize="12" HorizontalAlignment="Right"/>
        <ProgressBar Name="CpuBar" Height="4" Maximum="100" Foreground="#4FC3F7" Background="#33FFFFFF" BorderThickness="0"/>
      </StackPanel>
      <TextBlock Grid.Row="1" Foreground="#9AA0A6" FontSize="12" Text="RAM" VerticalAlignment="Center"/>
      <StackPanel Grid.Row="1" Grid.Column="1" VerticalAlignment="Center">
        <TextBlock Name="RamText" Foreground="White" FontSize="12" HorizontalAlignment="Right"/>
        <ProgressBar Name="RamBar" Height="4" Maximum="100" Foreground="#81C784" Background="#33FFFFFF" BorderThickness="0"/>
      </StackPanel>
      <TextBlock Grid.Row="2" Foreground="#9AA0A6" FontSize="12" Text="Disk" VerticalAlignment="Center"/>
      <StackPanel Grid.Row="2" Grid.Column="1" VerticalAlignment="Center">
        <TextBlock Name="DiskText" Foreground="White" FontSize="12" HorizontalAlignment="Right"/>
        <ProgressBar Name="DiskBar" Height="4" Maximum="100" Foreground="#FFB74D" Background="#33FFFFFF" BorderThickness="0"/>
      </StackPanel>
      <TextBlock Grid.Row="3" Foreground="#9AA0A6" FontSize="12" Text="Net" VerticalAlignment="Center"/>
      <TextBlock Grid.Row="3" Grid.Column="1" Name="NetText" Foreground="White" FontSize="11"
                 HorizontalAlignment="Right" VerticalAlignment="Center"/>
    </Grid>
    <StackPanel Name="UsagePanel"/>
    <StackPanel Name="CalPanel" Margin="0,8,0,0">
      <Rectangle Height="1" Fill="#33FFFFFF" Margin="0,0,0,6"/>
      <Grid>
        <TextBlock Name="CalPrev" Text="&lt;" Foreground="#9AA0A6" FontSize="12" Cursor="Hand" Padding="4,0" HorizontalAlignment="Left"/>
        <TextBlock Name="CalTitle" Foreground="White" FontSize="12" FontWeight="SemiBold" Cursor="Hand" HorizontalAlignment="Center"/>
        <TextBlock Name="CalNext" Text="&gt;" Foreground="#9AA0A6" FontSize="12" Cursor="Hand" Padding="4,0" HorizontalAlignment="Right"/>
      </Grid>
      <UniformGrid Name="CalGrid" Columns="7" Margin="0,4,0,0"/>
    </StackPanel>
    </StackPanel>
    <Grid Name="MiniPanel" Visibility="Collapsed" Background="Transparent" Cursor="Hand" ToolTip="Click to expand">
      <StackPanel Name="MiniStack" VerticalAlignment="Center" Margin="0,2,16,2">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" Margin="0,0,8,0">
          <TextBlock Name="MiniCpuText" Foreground="White" FontSize="11"/>
          <ProgressBar Name="MiniCpuBar" Height="4" Maximum="100" Foreground="#4FC3F7" Background="#33FFFFFF" BorderThickness="0" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel Grid.Column="1">
          <TextBlock Name="MiniRamText" Foreground="White" FontSize="11"/>
          <ProgressBar Name="MiniRamBar" Height="4" Maximum="100" Foreground="#81C784" Background="#33FFFFFF" BorderThickness="0" Margin="0,2,0,0"/>
        </StackPanel>
      </Grid>
      </StackPanel>
      <TextBlock Name="MiniPlus" Foreground="#9AA0A6" FontFamily="Segoe UI Symbol" FontSize="13" Text="+"
                 HorizontalAlignment="Right" VerticalAlignment="Center" Padding="4,0"/>
    </Grid>
    </Grid>
  </Border>
</Window>
"@

$win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'CpuText','CpuBar','RamText','RamBar','DiskText','DiskBar','NetText','CalPanel','CalPrev','CalTitle','CalNext','CalGrid','Root','MainGrid','VerText','MenuVer','BtnUpdate','BtnSettings','BtnHide','FullPanel','MiniPanel','MiniStack','MiniCpuText','MiniCpuBar','MiniRamText','MiniRamBar','MenuSettings','MenuHide','MenuExit','UsagePanel') { $ui[$n] = $win.FindName($n) }
$ui.MenuExit.Add_Click({ $win.Close() })

# ---- usage sections: one group per AI provider, built from the same template ----
# Full gadget: divider, colored dot + title, a small note on the right, then two usage rows.
# Collapsed bar: one line per provider with the same colored dots. Add a provider with New-UsageSection.
$sectionXaml = @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="0,8,0,0">
  <Rectangle Height="1" Fill="#33FFFFFF" Margin="0,0,0,5"/>
  <Grid>
    <StackPanel Orientation="Horizontal">
      <Ellipse Width="7" Height="7" Fill="{ACCENT}" VerticalAlignment="Center" Margin="0,1,6,0"/>
      <TextBlock Text="{TITLE}" Foreground="#E8EAED" FontSize="11" FontWeight="SemiBold"/>
    </StackPanel>
    <TextBlock Name="Note" Foreground="#9AA0A6" FontSize="10" HorizontalAlignment="Right" VerticalAlignment="Center"/>
  </Grid>
  <Grid Height="29">
    <Grid.ColumnDefinitions><ColumnDefinition Width="42"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <TextBlock Name="Lbl1" Foreground="#9AA0A6" FontSize="12" Text="{L1}" VerticalAlignment="Center"/>
    <StackPanel Grid.Column="1" VerticalAlignment="Center">
      <TextBlock Name="Text1" Foreground="White" FontSize="12" HorizontalAlignment="Right"/>
      <ProgressBar Name="Bar1" Height="4" Maximum="100" Foreground="#26A69A" Background="#33FFFFFF" BorderThickness="0"/>
    </StackPanel>
  </Grid>
  <Grid Name="Row2" Height="29">
    <Grid.ColumnDefinitions><ColumnDefinition Width="42"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <TextBlock Name="Lbl2" Foreground="#9AA0A6" FontSize="12" Text="{L2}" VerticalAlignment="Center"/>
    <StackPanel Grid.Column="1" VerticalAlignment="Center">
      <TextBlock Name="Text2" Foreground="White" FontSize="12" HorizontalAlignment="Right"/>
      <ProgressBar Name="Bar2" Height="4" Maximum="100" Foreground="#26A69A" Background="#33FFFFFF" BorderThickness="0"/>
    </StackPanel>
  </Grid>
</StackPanel>
'@
$miniXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="0,6,0,0" ToolTip="{TITLE} - click to expand">
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
  <StackPanel Margin="0,0,8,0">
    <StackPanel Orientation="Horizontal">
      <Ellipse Width="6" Height="6" Fill="{ACCENT}" VerticalAlignment="Center" Margin="0,1,4,0"/>
      <TextBlock Name="Text1" Foreground="White" FontSize="11"/>
    </StackPanel>
    <ProgressBar Name="Bar1" Height="4" Maximum="100" Foreground="#26A69A" Background="#33FFFFFF" BorderThickness="0" Margin="0,2,0,0"/>
  </StackPanel>
  <StackPanel Name="Cell2" Grid.Column="1">
    <StackPanel Orientation="Horizontal">
      <Ellipse Width="6" Height="6" Fill="{ACCENT}" VerticalAlignment="Center" Margin="0,1,4,0"/>
      <TextBlock Name="Text2" Foreground="White" FontSize="11"/>
    </StackPanel>
    <ProgressBar Name="Bar2" Height="4" Maximum="100" Foreground="#26A69A" Background="#33FFFFFF" BorderThickness="0" Margin="0,2,0,0"/>
  </StackPanel>
</Grid>
'@

function New-UsageSection([string]$title, [string]$accent, [string]$lbl1 = '5hr', [string]$lbl2 = 'Week') {
    $t = [Security.SecurityElement]::Escape($title)
    $full = [Windows.Markup.XamlReader]::Parse($sectionXaml.Replace('{TITLE}', $t).Replace('{ACCENT}', $accent).Replace('{L1}', $lbl1).Replace('{L2}', $lbl2))
    $mini = [Windows.Markup.XamlReader]::Parse($miniXaml.Replace('{TITLE}', $t).Replace('{ACCENT}', $accent))
    [void]$ui.UsagePanel.Children.Add($full)
    [void]$ui.MiniStack.Children.Add($mini)
    $s = @{ Panel = $full; Mini = $mini }
    foreach ($n in 'Note','Lbl1','Text1','Bar1','Row2','Lbl2','Text2','Bar2') { $s[$n] = $full.FindName($n) }
    foreach ($n in 'Text1','Bar1','Cell2','Text2','Bar2') { $s["Mini$n"] = $mini.FindName($n) }
    $s
}

# gadget order: Claude, Codex, then the API-key providers
$claudeSec = New-UsageSection 'Claude' '#D97757'
$codexSec  = New-UsageSection 'Codex' '#10A37F'

# API-key providers: settings "<Id>Key" + "Show<Id>"; Urls[0] is the main endpoint, extra Urls are optional.
# Parse gets the reply bodies (null where an extra request failed) and returns a view (see Update-KeyProvider).
$keyProviders = [ordered]@{}
foreach ($d in @(
    @{ Id = 'Ollama'; Title = 'Ollama Cloud'; Accent = '#B0BEC5'; KeyUrl = 'https://ollama.com/settings/keys'
       Urls = @('https://ollama.com/api/balance'); Labels = @('5hr', 'Week')
       Info = 'Shows the session (5hr) and weekly limits, or the included credits used this month on newer plans.'
       Parse = { param($r) ConvertFrom-OllamaBalance $r[0] } }
    @{ Id = 'OpenRouter'; Title = 'OpenRouter'; Accent = '#8C8FF7'; KeyUrl = 'https://openrouter.ai/settings/keys'
       Urls = @('https://openrouter.ai/api/v1/key', 'https://openrouter.ai/api/v1/credits'); Labels = @('Left', '')
       Info = "Shows the credits left on your account (and the key's limit, if it has one). If OpenRouter won't show the balance to this key, it shows the key's spend today and this month instead."
       Parse = { param($r) ConvertFrom-OpenRouterKey $r[0] $(if ($r.Count -gt 1) { $r[1] }) } }
    @{ Id = 'DeepSeek'; Title = 'DeepSeek'; Accent = '#4D6BFE'; KeyUrl = 'https://platform.deepseek.com/api_keys'
       Urls = @('https://api.deepseek.com/user/balance'); Labels = @('Left', '')
       Info = 'Shows your remaining balance. DeepSeek is pay-as-you-go, so there is no 5hr / weekly limit.'
       Parse = { param($r) ConvertFrom-DeepSeekBalance $r[0] } }
)) {
    $d.AllUrls = $d.Urls; $d.Host = ([Uri]$d.Urls[0]).Host
    # first request a few seconds after start: starting a request blocks the UI briefly (proxy / DNS lookup)
    $d.Tasks = $null; $d.TaskUrls = @(); $d.NextAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3; $d.View = $null; $d.Stamp = 0; $d.Error = ''; $d.P = @{}
    $d.Sec = New-UsageSection $d.Title $d.Accent $d.Labels[0] $d.Labels[1]
    $keyProviders[$d.Id] = $d
}

function Set-Position {
    $wa = [Windows.SystemParameters]::WorkArea
    $h = if ($win.ActualHeight -gt 0) { $win.ActualHeight } else { 192 }
    $win.Left = $wa.Right - $win.Width - 12
    $win.Top  = $wa.Bottom - $h - 12
}

# ---- desk calendar (Thai culture: Thai month names, Buddhist year) ----
$thai = [Globalization.CultureInfo]::GetCultureInfo('th-TH')
$calState = @{ Offset = 0; Key = '' }
$calBrush = New-Object Windows.Media.BrushConverter
$calText = $calBrush.ConvertFromString('#E8EAED'); $calSun = $calBrush.ConvertFromString('#E57373')
$calDim = $calBrush.ConvertFromString('#9AA0A6');  $calToday = $calBrush.ConvertFromString('#26A69A')

function Add-CalCell([string]$text, $fg, $bg) {
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $text; $tb.FontSize = 11; $tb.Foreground = $fg
    $tb.HorizontalAlignment = 'Center'; $tb.VerticalAlignment = 'Center'
    $b = New-Object Windows.Controls.Border
    $b.Height = 19; $b.CornerRadius = New-Object Windows.CornerRadius 9.5; $b.Child = $tb
    if ($bg) { $b.Background = $bg }
    [void]$ui.CalGrid.Children.Add($b)
}

function Update-Calendar {
    $today = (Get-Date).Date
    $key = '{0:yyyyMMdd}|{1}' -f $today, $calState.Offset
    if ($key -eq $calState.Key) { return }
    $calState.Key = $key
    $first = [DateTime]::new($today.Year, $today.Month, 1).AddMonths($calState.Offset)
    $ui.CalTitle.Text = $first.ToString('MMMM yyyy', $thai)
    $ui.CalGrid.Children.Clear()
    $dn = $thai.DateTimeFormat.AbbreviatedDayNames
    for ($i = 0; $i -lt 7; $i++) { Add-CalCell $dn[$i].TrimEnd('.') $(if ($i -eq 0) { $calSun } else { $calDim }) $null }
    $lead = [int]$first.DayOfWeek
    $days = [DateTime]::DaysInMonth($first.Year, $first.Month)
    for ($c = 0; $c -lt 42; $c++) {
        $d = $c - $lead + 1
        if ($d -lt 1 -or $d -gt $days) { Add-CalCell '' $calText $null; continue }
        $date = $first.AddDays($d - 1)
        if ($date -eq $today) { Add-CalCell "$d" 'White' $calToday }
        elseif ($date.DayOfWeek -eq 'Sunday') { Add-CalCell "$d" $calSun $null }
        else { Add-CalCell "$d" $calText $null }
    }
}
$ui.CalPrev.Add_MouseLeftButtonUp({ $calState.Offset--; Update-Calendar })
$ui.CalNext.Add_MouseLeftButtonUp({ $calState.Offset++; Update-Calendar })
$ui.CalTitle.Add_MouseLeftButtonUp({ $calState.Offset = 0; Update-Calendar })

# ---- apply settings to the gadget ----
function Apply-Settings {
    $alpha = [byte][math]::Round((100 - $settings.Transparency) / 100 * 255)
    $ui.Root.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb($alpha, 0x18, 0x18, 0x18))
    $ui.CalPanel.Visibility = if ($settings.ShowCalendar) { 'Visible' } else { 'Collapsed' }
    # collapsed = small bar (CPU / RAM + one line per provider) instead of the full gadget
    $ui.FullPanel.Visibility = if ($settings.Collapsed) { 'Collapsed' } else { 'Visible' }
    $ui.MiniPanel.Visibility = if ($settings.Collapsed) { 'Visible' } else { 'Collapsed' }
    $vis = if ($settings.ShowClaude) { 'Visible' } else { 'Collapsed' }
    $claudeSec.Panel.Visibility = $vis; $claudeSec.Mini.Visibility = $vis
    # Codex appears when its session folder exists ($codexState is set further down; null on the first call)
    $vis = if ($settings.ShowCodex -and $codexState.Found) { 'Visible' } else { 'Collapsed' }
    $codexSec.Panel.Visibility = $vis; $codexSec.Mini.Visibility = $vis
    # API-key providers appear once a key is connected
    foreach ($p in $keyProviders.Values) {
        $vis = if ($settings["$($p.Id)Key"] -and $settings["Show$($p.Id)"]) { 'Visible' } else { 'Collapsed' }
        $p.Sec.Panel.Visibility = $vis; $p.Sec.Mini.Visibility = $vis
    }
}

function Set-Collapsed([bool]$collapsed) {
    $settings.Collapsed = $collapsed
    Apply-Settings; Save-Settings
    $win.UpdateLayout()
    Set-Position
}

# ---- settings window (opened from the right-click menu) ----
# Left: one tab per area (General, then one per provider with its colored dot). Right: the pages, stacked in one
# Grid; the hidden ones use Visibility=Hidden (not Collapsed) so the window keeps the size of the tallest page.
[xml]$setXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="System Monitor Settings" Width="470" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True" Background="#202124">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border Background="#17181A"><StackPanel Name="TabList" Margin="8,12"/></Border>
    <Grid Name="PageHost" Grid.Column="1" Margin="18,16,18,18">
      <StackPanel Name="PageGeneral">
        <TextBlock Name="TransLabel" Foreground="White" FontSize="13"/>
        <Slider Name="TransSlider" Minimum="0" Maximum="90" TickFrequency="5" IsSnapToTickEnabled="True" Margin="0,6,0,2"/>
        <TextBlock Text="0% = solid, higher = more see-through" Foreground="#9AA0A6" FontSize="11" Margin="0,0,0,14"/>
        <CheckBox Name="ChkCal" Content="Show calendar" Foreground="White"/>
        <Rectangle Height="1" Fill="#33FFFFFF" Margin="0,14,0,12"/>
        <TextBlock Name="VerLabel" Foreground="#E8EAED" FontSize="13" FontWeight="SemiBold"/>
        <CheckBox Name="ChkUpdate" Content="Check for updates automatically (daily)" Foreground="White" Margin="0,8,0,8"/>
        <CheckBox Name="ChkAutoInstall" Content="Install updates automatically" Foreground="White" Margin="0,0,0,8"/>
        <StackPanel Orientation="Horizontal">
          <Button Name="BtnCheck" Content="Check now" Padding="10,3"/>
          <Button Name="BtnDoUpdate" Content="Update now" Padding="10,3" Margin="8,0,0,0" Visibility="Collapsed"/>
        </StackPanel>
        <TextBlock Name="UpdStatus" Foreground="#9AA0A6" FontSize="11" Margin="0,8,0,0" TextWrapping="Wrap"/>
        <TextBlock Text="Update checks only contact api.github.com." Foreground="#6B7075" FontSize="10" Margin="0,6,0,0"/>
      </StackPanel>
      <StackPanel Name="PageClaude" Visibility="Hidden">
        <StackPanel Orientation="Horizontal">
          <Ellipse Width="8" Height="8" Fill="#D97757" VerticalAlignment="Center" Margin="0,1,7,0"/>
          <TextBlock Text="Claude" Foreground="#E8EAED" FontSize="14" FontWeight="SemiBold"/>
        </StackPanel>
        <CheckBox Name="ChkClaude" Content="Show Claude usage (5hr / Week)" Foreground="White" Margin="0,10,0,0"/>
        <CheckBox Name="ChkLive" Content="Live usage (uses your Claude login)" Foreground="White" Margin="0,8,0,0"/>
        <TextBlock Text="Off by default. Reads the login token in ~\.claude\.credentials.json (read-only) and asks api.anthropic.com every 2 minutes, so the numbers match Claude even when you only use VS Code. Unofficial endpoint: it may stop working."
                   Foreground="#6B7075" FontSize="10" TextWrapping="Wrap" Margin="22,2,0,0"/>
        <TextBlock Text="With Live off, the numbers come from Claude Code's statusLine and only update while you use the Claude CLI."
                   Foreground="#9AA0A6" FontSize="11" TextWrapping="Wrap" Margin="0,12,0,0"/>
      </StackPanel>
      <StackPanel Name="PageCodex" Visibility="Hidden">
        <StackPanel Orientation="Horizontal">
          <Ellipse Width="8" Height="8" Fill="#10A37F" VerticalAlignment="Center" Margin="0,1,7,0"/>
          <TextBlock Text="Codex" Foreground="#E8EAED" FontSize="14" FontWeight="SemiBold"/>
        </StackPanel>
        <CheckBox Name="ChkCodex" Content="Show Codex usage (5hr / Week)" Foreground="White" Margin="0,10,0,0"/>
        <TextBlock Text="Read from the Codex CLI's own session files in ~\.codex\sessions on this PC. Nothing is sent anywhere and no login is needed. The numbers update while you use Codex."
                   Foreground="#9AA0A6" FontSize="11" TextWrapping="Wrap" Margin="0,12,0,0"/>
        <TextBlock Name="CodexStatus" Foreground="#9AA0A6" FontSize="11" Margin="0,10,0,0" TextWrapping="Wrap"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
"@
# page for an API-key provider (one per entry in $keyProviders)
$keyPageXaml = @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Visibility="Hidden">
  <StackPanel Orientation="Horizontal">
    <Ellipse Width="8" Height="8" Fill="{ACCENT}" VerticalAlignment="Center" Margin="0,1,7,0"/>
    <TextBlock Text="{TITLE}" Foreground="#E8EAED" FontSize="14" FontWeight="SemiBold"/>
  </StackPanel>
  <CheckBox Name="ChkShow" Content="Show {TITLE} usage" Foreground="White" Margin="0,10,0,0"/>
  <TextBlock Foreground="#9AA0A6" FontSize="11" TextWrapping="Wrap" Margin="0,12,0,6">Paste an API key from
    <Hyperlink Name="KeyLink" Foreground="#4FC3F7">{KEYTEXT}</Hyperlink> and press Connect.</TextBlock>
  <PasswordBox Name="KeyBox" Padding="3,2"/>
  <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
    <Button Name="BtnConnect" Content="Connect" Padding="10,3"/>
    <Button Name="BtnDisconnect" Content="Disconnect" Padding="10,3" Margin="8,0,0,0"/>
  </StackPanel>
  <TextBlock Name="Status" Foreground="#9AA0A6" FontSize="11" Margin="0,8,0,0" TextWrapping="Wrap"/>
  <TextBlock Text="{INFO}" Foreground="#9AA0A6" FontSize="11" TextWrapping="Wrap" Margin="0,10,0,0"/>
  <TextBlock Text="The key is stored encrypted for your Windows account and is only sent to {HOST} (checked once a minute)."
             Foreground="#6B7075" FontSize="10" TextWrapping="Wrap" Margin="0,6,0,0"/>
</StackPanel>
'@
$script:setWin  = $null
$script:setUi   = @{}
$script:setTabs = @()
$script:setTab  = 'General'
$tabOnBrush = (New-Object Windows.Media.BrushConverter).ConvertFromString('#33FFFFFF')

function Add-SettingsTab([string]$title, [string]$accent, $page) {
    $b = New-Object Windows.Controls.Border
    $b.CornerRadius = New-Object Windows.CornerRadius 4
    $b.Padding = New-Object Windows.Thickness 8, 6, 8, 6
    $b.Margin = New-Object Windows.Thickness 0, 0, 0, 2
    $b.Cursor = [Windows.Input.Cursors]::Hand
    $b.Background = [Windows.Media.Brushes]::Transparent
    $b.Tag = $title
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    $dot = New-Object Windows.Shapes.Ellipse
    $dot.Width = 7; $dot.Height = 7; $dot.VerticalAlignment = 'Center'; $dot.Margin = New-Object Windows.Thickness 0, 1, 8, 0
    $dot.Fill = if ($accent) { (New-Object Windows.Media.BrushConverter).ConvertFromString($accent) } else { [Windows.Media.Brushes]::Transparent }
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $title; $tb.Foreground = $calText; $tb.FontSize = 12
    [void]$sp.Children.Add($dot); [void]$sp.Children.Add($tb)
    $b.Child = $sp
    $b.Add_MouseLeftButtonUp({ param($s, $e) Select-SettingsTab $s.Tag })
    [void]$script:setUi.TabList.Children.Add($b)
    $script:setTabs += @{ Title = $title; Tab = $b; Page = $page }
}

function Select-SettingsTab([string]$title) {
    if (-not ($script:setTabs | Where-Object { $_.Title -eq $title })) { $title = 'General' }
    $script:setTab = $title
    foreach ($t in $script:setTabs) {
        $on = $t.Title -eq $title
        $t.Page.Visibility = if ($on) { 'Visible' } else { 'Hidden' }
        $t.Tab.Background = if ($on) { $tabOnBrush } else { [Windows.Media.Brushes]::Transparent }
    }
}

function Show-Settings([string]$tab = '') {
    if ($script:setWin) { if ($tab) { Select-SettingsTab $tab }; [void]$script:setWin.Activate(); return }
    $w = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $setXaml))
    $script:setWin = $w
    $script:setTabs = @()
    foreach ($n in 'TabList','PageHost','PageGeneral','PageClaude','PageCodex','TransLabel','TransSlider','ChkCal','ChkClaude','ChkLive','ChkCodex','CodexStatus',
                'VerLabel','ChkUpdate','ChkAutoInstall','BtnCheck','BtnDoUpdate','UpdStatus') { $script:setUi[$n] = $w.FindName($n) }
    $script:setUi.TransSlider.Value = $settings.Transparency
    $script:setUi.TransLabel.Text = 'Transparency: {0}%' -f $settings.Transparency
    $script:setUi.ChkCal.IsChecked = [bool]$settings.ShowCalendar
    $script:setUi.ChkClaude.IsChecked = [bool]$settings.ShowClaude
    $script:setUi.TransSlider.Add_ValueChanged({
        $settings.Transparency = [int]$script:setUi.TransSlider.Value
        $script:setUi.TransLabel.Text = 'Transparency: {0}%' -f $settings.Transparency
        Apply-Settings; Save-Settings
    })
    $script:setUi.ChkCal.Add_Click({ $settings.ShowCalendar = [bool]$script:setUi.ChkCal.IsChecked; Apply-Settings; Save-Settings })
    $script:setUi.ChkClaude.Add_Click({ $settings.ShowClaude = [bool]$script:setUi.ChkClaude.IsChecked; Apply-Settings; Save-Settings })
    $script:setUi.VerLabel.Text = "System Monitor v$AppVersion"
    $w.Title = "System Monitor Settings - v$AppVersion"
    $script:setUi.ChkUpdate.IsChecked = [bool]$settings.AutoCheckUpdates
    $script:setUi.ChkUpdate.Add_Click({ $settings.AutoCheckUpdates = [bool]$script:setUi.ChkUpdate.IsChecked; Save-Settings })
    $script:setUi.ChkLive.IsChecked = [bool]$settings.LiveClaudeUsage
    $script:setUi.ChkLive.Add_Click({ $settings.LiveClaudeUsage = [bool]$script:setUi.ChkLive.IsChecked; $liveState.NextAt = 0; Save-Settings })
    $script:setUi.ChkAutoInstall.IsChecked = [bool]$settings.AutoInstallUpdates
    $script:setUi.ChkAutoInstall.Add_Click({ $settings.AutoInstallUpdates = [bool]$script:setUi.ChkAutoInstall.IsChecked; Save-Settings })
    $script:setUi.BtnCheck.Add_Click({ Start-UpdateCheck })
    $script:setUi.BtnDoUpdate.Add_Click({ Start-Update })
    $script:setUi.ChkCodex.IsChecked = [bool]$settings.ShowCodex
    $script:setUi.ChkCodex.Add_Click({ $settings.ShowCodex = [bool]$script:setUi.ChkCodex.IsChecked; $codexState.NextScan = 0; $codexState.Sig = ''; Apply-Settings; Save-Settings; Refresh-CodexUi })
    Add-SettingsTab 'General' '' $script:setUi.PageGeneral
    Add-SettingsTab 'Claude' '#D97757' $script:setUi.PageClaude
    Add-SettingsTab 'Codex' '#10A37F' $script:setUi.PageCodex
    # one page per API-key provider; controls find their provider again through .Tag = provider id
    $esc = { param($v) [Security.SecurityElement]::Escape([string]$v) }
    foreach ($p in $keyProviders.Values) {
        $x = $keyPageXaml.Replace('{TITLE}', (& $esc $p.Title)).Replace('{ACCENT}', $p.Accent).Replace('{HOST}', (& $esc $p.Host))
        $x = $x.Replace('{KEYTEXT}', (& $esc ($p.KeyUrl -replace '^https://', ''))).Replace('{INFO}', (& $esc $p.Info))
        $page = [Windows.Markup.XamlReader]::Parse($x)
        [void]$script:setUi.PageHost.Children.Add($page)
        $p.P = @{}
        foreach ($n in 'ChkShow','KeyLink','KeyBox','BtnConnect','BtnDisconnect','Status') { $p.P[$n] = $page.FindName($n); $p.P[$n].Tag = $p.Id }
        $p.P.ChkShow.IsChecked = [bool]$settings["Show$($p.Id)"]
        # hidden = no requests either; showing it again refreshes right away
        $p.P.ChkShow.Add_Click({ param($s, $e) $q = $keyProviders[$s.Tag]; $settings["Show$($q.Id)"] = [bool]$s.IsChecked; $q.NextAt = 0; Apply-Settings; Save-Settings; Refresh-ProviderUi $q })
        $p.P.KeyLink.Add_Click({ param($s, $e) Start-Process $keyProviders[$s.Tag].KeyUrl })
        $p.P.BtnConnect.Add_Click({ param($s, $e) $q = $keyProviders[$s.Tag]; Connect-Provider $q $q.P.KeyBox.Password })
        $p.P.KeyBox.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $q = $keyProviders[$s.Tag]; Connect-Provider $q $q.P.KeyBox.Password } })
        $p.P.BtnDisconnect.Add_Click({ param($s, $e) Disconnect-Provider $keyProviders[$s.Tag] })
        Add-SettingsTab $p.Title $p.Accent $page
        Refresh-ProviderUi $p
    }
    Select-SettingsTab $(if ($tab) { $tab } else { $script:setTab })
    Refresh-UpdateUi
    Refresh-CodexUi
    $w.Add_Closed({ $script:setWin = $null; $script:setTabs = @(); foreach ($p in $keyProviders.Values) { $p.P = @{} } })
    $w.Show()
}
$ui.MenuSettings.Add_Click({ Show-Settings })
# version shown in: gadget corner, tooltips, right-click menu (tray + Settings title are set further down)
$ui.VerText.Text = "v$AppVersion"
$ui.MenuVer.Header = "System Monitor v$AppVersion"
$ui.BtnSettings.ToolTip = "Settings (v$AppVersion)"
$ui.MiniPanel.ToolTip = "Click to expand (v$AppVersion)"
$ui.BtnUpdate.Text = 'Update'
$ui.BtnUpdate.Add_MouseLeftButtonUp({ Show-Settings 'General' })
# gear button (top-right of the gadget); U+2699 built in code to keep this file ASCII
$ui.BtnSettings.Text = [string][char]0x2699
$ui.BtnSettings.Add_MouseLeftButtonUp({ Show-Settings })
$ui.BtnSettings.Add_MouseEnter({ $ui.BtnSettings.Foreground = [Windows.Media.Brushes]::White })
$ui.BtnSettings.Add_MouseLeave({ $ui.BtnSettings.Foreground = $calDim })

# ---- hide / show the gadget (tray icon brings it back) ----
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$script:hideHintShown = $false

function Toggle-Gadget {
    if ($win.Visibility -eq 'Visible') {
        $win.Visibility = 'Hidden'
        if (-not $script:hideHintShown) {
            $script:hideHintShown = $true
            $tray.ShowBalloonTip(2000, 'System Monitor', 'Click the tray icon to show it again.', [Windows.Forms.ToolTipIcon]::Info)
        }
    } else {
        $win.Visibility = 'Visible'
        Set-Position
    }
}

$ui.BtnHide.Text = [string][char]0x2212
$ui.BtnHide.Add_MouseLeftButtonUp({ Set-Collapsed $true })
$ui.MiniPanel.Add_MouseLeftButtonUp({ Set-Collapsed $false })
$ui.BtnHide.Add_MouseEnter({ $ui.BtnHide.Foreground = [Windows.Media.Brushes]::White })
$ui.BtnHide.Add_MouseLeave({ $ui.BtnHide.Foreground = $calDim })
$ui.MenuHide.Add_Click({ Toggle-Gadget })

# tray icon: three small bars drawn in code (no .ico file needed)
$bmp = New-Object Drawing.Bitmap 16, 16
$gfx = [Drawing.Graphics]::FromImage($bmp)
$gfx.Clear([Drawing.Color]::FromArgb(32, 33, 36))
$barColors = @([Drawing.Color]::FromArgb(79, 195, 247), [Drawing.Color]::FromArgb(129, 199, 132), [Drawing.Color]::FromArgb(255, 183, 77))
$barTops   = @(8, 3, 6)
for ($i = 0; $i -lt 3; $i++) {
    $gfx.FillRectangle((New-Object Drawing.SolidBrush $barColors[$i]), 2 + 5 * $i, $barTops[$i], 3, 14 - $barTops[$i])
}
$gfx.Dispose()
$tray = New-Object Windows.Forms.NotifyIcon
$tray.Icon = [Drawing.Icon]::FromHandle($bmp.GetHicon())
$tray.Text = "System Monitor v$AppVersion"
$trayMenu = New-Object Windows.Forms.ContextMenuStrip
$miVer = $trayMenu.Items.Add("System Monitor v$AppVersion"); $miVer.Enabled = $false
[void]$trayMenu.Items.Add('-')
$miToggle = $trayMenu.Items.Add('Show / Hide')
$miSet    = $trayMenu.Items.Add('Settings...')
$miExit   = $trayMenu.Items.Add('Exit')
$miToggle.Add_Click({ Toggle-Gadget })
$miSet.Add_Click({ Show-Settings })
$miExit.Add_Click({ $win.Close() })
$tray.ContextMenuStrip = $trayMenu
$tray.Add_MouseClick({ param($s, $e) if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) { Toggle-Gadget } })
$tray.Visible = $true
$win.Add_Closed({ $tray.Visible = $false; $tray.Dispose() })

Apply-Settings

$win.Add_SourceInitialized({
    $h = (New-Object Windows.Interop.WindowInteropHelper $win).Handle
    $ex = [Win32]::GetWindowLong($h, $GWL_EXSTYLE)
    [void][Win32]::SetWindowLong($h, $GWL_EXSTYLE, ($ex -bor $WS_EX_TOOLWINDOW -bor $WS_EX_NOACTIVATE))
    Set-Position
})

# ---- Claude usage (written by claude-usage-hook.ps1 via Claude Code's statusLine) ----
$usageFile  = Join-Path $env:LOCALAPPDATA 'system-monitor\claude-usage.json'
$usageState = @{ Stamp = $null; Data = $null }
$brush = New-Object Windows.Media.BrushConverter
$barOk = $brush.ConvertFromString('#26A69A'); $barWarn = $brush.ConvertFromString('#FFB74D'); $barHot = $brush.ConvertFromString('#E57373')

function Get-UsageData {
    if (-not (Test-Path $usageFile)) { $usageState.Data = $null; return }
    $stamp = (Get-Item $usageFile).LastWriteTimeUtc
    if ($stamp -eq $usageState.Stamp) { return }
    $usageState.Stamp = $stamp
    try { $usageState.Data = Get-Content $usageFile -Raw | ConvertFrom-Json } catch { $usageState.Data = $null }
}

function Format-Remaining([double]$sec) {
    $t = [TimeSpan]::FromSeconds($sec)
    if ($t.TotalDays -ge 1) { '{0}d {1}h' -f [int]$t.Days, $t.Hours }
    elseif ($t.TotalHours -ge 1) { '{0}h {1}m' -f [int]$t.Hours, $t.Minutes }
    else { '{0}m' -f [math]::Max(1, [int]$t.Minutes) }
}

# collapsed-bar version of Set-UsageRow: short "label pct" text + colored bar
function Set-MiniUsage($limit, [string]$label, $text, $bar, [double]$ageSec) {
    $reset = if ($limit) { [double]$limit.resets_at } else { 0 }
    if ($reset -gt 1e11) { $reset = $reset / 1000 }
    if (-not $limit -or $reset -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) { $text.Text = "$label --"; $bar.Value = 0; return }
    $pct = [math]::Round([double]$limit.used_percentage, 0)
    if ($ageSec -gt $staleAfterSec) {
        $text.Text = '{0} {1}%*' -f $label, $pct   # * = old data, not live
        $text.Foreground = $calDim
    } else {
        $text.Text = '{0} {1}%' -f $label, $pct
        $text.Foreground = [Windows.Media.Brushes]::White
    }
    $bar.Value = $pct
    $bar.Foreground = if ($pct -ge 95) { $barHot } elseif ($pct -ge 80) { $barWarn } else { $barOk }
}

$staleAfterSec = 900   # usage data older than this is shown greyed out with its age

function Format-Age([double]$sec) {
    if ($sec -ge 86400) { '{0}d' -f [int][math]::Floor($sec / 86400) }
    elseif ($sec -ge 3600) { '{0}h' -f [int][math]::Floor($sec / 3600) }
    else { '{0}m' -f [int][math]::Floor($sec / 60) }
}

function Set-UsageRow($limit, $text, $bar, [double]$ageSec) {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $reset = if ($limit) { [double]$limit.resets_at } else { 0 }
    if ($reset -gt 1e11) { $reset = $reset / 1000 }
    if (-not $limit -or $reset -le $now) {
        # no usable data: with Live off, point at the setting instead of a bare "--"
        if ($settings.LiveClaudeUsage) { $text.Text = '--' } else { $text.Text = 'Live off - see Settings'; $text.Foreground = $calDim }
        $bar.Value = 0; return
    }
    $pct = [math]::Round([double]$limit.used_percentage, 0)
    if ($ageSec -gt $staleAfterSec) {
        $text.Text = '{0}%  {1} ago' -f $pct, (Format-Age $ageSec)
        $text.Foreground = $calDim
    } else {
        $text.Text = '{0}%  resets {1}' -f $pct, (Format-Remaining ($reset - $now))
        $text.Foreground = [Windows.Media.Brushes]::White
    }
    $bar.Value = $pct
    $bar.Foreground = if ($pct -ge 95) { $barHot } elseif ($pct -ge 80) { $barWarn } else { $barOk }
}

# ---- update check (GitHub latest release, once a day, in the background) ----
$installedDir = Join-Path $env:LOCALAPPDATA 'Programs\system-monitor'
$isInstalled  = ($PSScriptRoot -ieq $installedDir)
$appStart     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$updateState  = @{ Task = $null; Error = ''; Checked = $false; RetryAt = 0; Init = $false; Updating = $false }

function Test-UpdateAvailable {
    if (-not $settings.LatestTag) { return $false }
    try { return ([version]([string]$settings.LatestTag).TrimStart('v')) -gt ([version]$AppVersion) } catch { return $false }
}

function Refresh-UpdateUi {
    $newer = Test-UpdateAvailable
    $ui.BtnUpdate.Visibility = if ($newer) { 'Visible' } else { 'Collapsed' }
    if (-not $script:setWin) { return }
    $s = $script:setUi
    $s.BtnCheck.IsEnabled = -not $updateState.Task
    $s.BtnDoUpdate.Visibility = if ($newer -and $isInstalled) { 'Visible' } else { 'Collapsed' }
    $s.UpdStatus.Text =
        if ($updateState.Task) { 'Checking...' }
        elseif ($updateState.Error) { $updateState.Error }
        elseif ($newer -and $isInstalled) { "Update available: $($settings.LatestTag)" }
        elseif ($newer) { "$($settings.LatestTag) is available (this copy runs from the source folder, so update it with git)." }
        elseif ($updateState.Checked) { 'You have the latest version.' }
        else { '' }
}

function Start-UpdateCheck {
    if ($updateState.Task) { return }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', 'system-monitor-gadget')
    $updateState.Error = ''; $updateState.Checked = $false
    $updateState.Task = $wc.DownloadStringTaskAsync("https://api.github.com/repos/$repoSlug/releases/latest")
    Refresh-UpdateUi
}

function Update-Poll {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (-not $updateState.Init) { $updateState.Init = $true; Refresh-UpdateUi }
    $due = $settings.AutoCheckUpdates -and ($now - $appStart -gt 30) -and ($now -gt $updateState.RetryAt) -and (($now - [double]$settings.LastUpdateCheck) -gt 86400)
    if (-not $updateState.Task -and $due) { Start-UpdateCheck }
    $t = $updateState.Task
    if ($t -and $t.IsCompleted) {
        $updateState.Task = $null
        $tag = $null
        if (-not ($t.IsFaulted -or $t.IsCanceled)) { try { $tag = ($t.Result | ConvertFrom-Json).tag_name } catch { } }
        if ($tag -and ([string]$tag) -match '^v\d+\.\d+\.\d+$') {   # strict format: the tag ends up inside a command line
            $settings.LatestTag = [string]$tag; $settings.LastUpdateCheck = $now; $updateState.Error = ''
            Save-Settings
        } else {
            $updateState.Error = 'Could not check for updates (offline, or no release found).'
            $updateState.RetryAt = $now + 3600
        }
        $updateState.Checked = $true
        Refresh-UpdateUi
    }
    # auto-install: at most one attempt per version per 24h, so a failing install can't loop
    if ($settings.AutoInstallUpdates -and $isInstalled -and -not $updateState.Updating -and ($now - $appStart -gt 30) -and (Test-UpdateAvailable)) {
        $again = ($settings.LastAutoAttemptTag -ne $settings.LatestTag) -or (($now - [double]$settings.LastAutoAttemptAt) -gt 86400)
        if ($again) {
            $settings.LastAutoAttemptTag = [string]$settings.LatestTag; $settings.LastAutoAttemptAt = $now
            Save-Settings
            Start-Update
        }
    }
}

# the installer is run from the NEW tag; SM_CLAUDE_USAGE=skip keeps it from re-asking the Claude question
$updateLog = Join-Path $env:LOCALAPPDATA 'system-monitor\update.log'
function Write-UpdateLog([string]$msg) {
    try {
        New-Item -ItemType Directory -Force (Split-Path $updateLog) | Out-Null
        Add-Content -Path $updateLog -Value ('{0}  {1}' -f (Get-Date -Format 's'), $msg)
    } catch { }
}

# The installer runs in a visible console for a few seconds: security software blocks a hidden
# powershell window that runs "irm | iex" (it looks like malware), so hiding it makes the update fail.
function Get-UpdateArgs {
    if (([string]$settings.LatestTag) -notmatch '^v\d+\.\d+\.\d+$') { return $null }
    $url = "https://raw.githubusercontent.com/$repoSlug/$($settings.LatestTag)/install.ps1"
    $cmd = "`$env:SM_CLAUDE_USAGE = 'skip'; irm '$url' | iex"
    @('-NoProfile', '-Command', $cmd)
}

function Start-Update {
    if ($updateState.Updating -or -not ($isInstalled -and (Test-UpdateAvailable))) { return }
    $updateArgs = Get-UpdateArgs
    if (-not $updateArgs) { return }
    $updateState.Updating = $true
    try {
        Start-Process powershell.exe -ArgumentList $updateArgs
        Write-UpdateLog "started installer for $($settings.LatestTag)"
    } catch {
        $updateState.Updating = $false
        $updateState.Error = "Could not start the update: $($_.Exception.Message)"
        Write-UpdateLog $updateState.Error
        Refresh-UpdateUi
        return
    }
    if ($script:setWin) { $script:setUi.UpdStatus.Text = 'Updating... the gadget will restart in a few seconds.'; $script:setUi.BtnDoUpdate.IsEnabled = $false }
}

# ---- live Claude usage (opt-in) ----
# Asks api.anthropic.com/api/oauth/usage (unofficial) with the Claude Code login token, so the numbers match
# Claude even when it is only used through VS Code. The token file is only READ: refreshing the token here
# would rotate Claude Code's own login, so an expired token just means "no live data" until Claude Code renews it.
$liveState = @{ Task = $null; NextAt = 0; Data = $null; Stamp = 0; Error = '' }

function Get-ClaudeToken {
    $p = Join-Path $env:USERPROFILE '.claude\.credentials.json'
    if (-not (Test-Path $p)) { return $null }
    try {
        $o = (Get-Content $p -Raw | ConvertFrom-Json).claudeAiOauth
        if (-not $o -or -not $o.accessToken) { return $null }
        if ($o.expiresAt -and ([double]$o.expiresAt / 1000) -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) { return $null }
        return [string]$o.accessToken
    } catch { return $null }
}

function Convert-ToEpoch($v) {
    try {
        if ($v -is [DateTime]) { return ([DateTimeOffset]$v).ToUnixTimeSeconds() }
        return [DateTimeOffset]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture).ToUnixTimeSeconds()
    } catch { return 0 }
}

function Start-LiveUsage {
    if ($liveState.Task) { return }
    $tok = Get-ClaudeToken
    if (-not $tok) { $liveState.Error = 'no valid Claude login token'; $liveState.NextAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 300; return }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('Authorization', "Bearer $tok")
    $wc.Headers.Add('anthropic-beta', 'oauth-2025-04-20')
    $wc.Headers.Add('User-Agent', 'system-monitor-gadget')
    $liveState.Task = $wc.DownloadStringTaskAsync('https://api.anthropic.com/api/oauth/usage')
}

function Update-LivePoll {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (-not $settings.LiveClaudeUsage) { $liveState.Data = $null; return }
    if (-not $liveState.Task -and $now -ge $liveState.NextAt) { $liveState.NextAt = $now + 120; Start-LiveUsage }
    $t = $liveState.Task
    if ($t -and $t.IsCompleted) {
        $liveState.Task = $null
        if ($t.IsFaulted -or $t.IsCanceled) { $liveState.Error = 'request failed'; $liveState.NextAt = $now + 300; return }
        try {
            $j = $t.Result | ConvertFrom-Json
            $liveState.Data = [pscustomobject]@{
                five_hour = [pscustomobject]@{ used_percentage = [double]$j.five_hour.utilization; resets_at = (Convert-ToEpoch $j.five_hour.resets_at) }
                seven_day = [pscustomobject]@{ used_percentage = [double]$j.seven_day.utilization; resets_at = (Convert-ToEpoch $j.seven_day.resets_at) }
            }
            $liveState.Stamp = $now; $liveState.Error = ''
        } catch { $liveState.Error = 'unexpected reply'; $liveState.NextAt = $now + 300 }
    }
}

# ---- provider rows (Codex + API-key providers) ----
# A view is @{ Rows = @(row, row); Note; Tip; Status }. A row is @{ Label; Pct (0-100, draws a bar);
# ResetAt (epoch); Value (text, shown when there is no Pct or next to it); Mini (collapsed-bar text) }.
function Get-Clamped([double]$v) { [math]::Min(100, [math]::Max(0, $v)) }

function Set-ProviderRow($row, $lbl, $text, $bar, $mText, $mBar, [double]$ageSec, [string]$emptyText) {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($row) { $lbl.Text = $row.Label }
    if (-not $row -or ($row.ResetAt -and $row.ResetAt -le $now)) {
        $text.Text = $emptyText; $text.Foreground = $calDim; $bar.Visibility = 'Collapsed'
        $mText.Text = "$($lbl.Text) --"; $mText.Foreground = $calDim; $mBar.Visibility = 'Collapsed'
        return
    }
    $stale = $ageSec -gt $staleAfterSec
    $hasPct = $null -ne $row.Pct
    $pct = if ($hasPct) { [math]::Round([double]$row.Pct, 0) } else { 0 }
    $main = if ($hasPct) { '{0}%' -f $pct } else { [string]$row.Value }
    $extra = if ($stale) { '{0} ago' -f (Format-Age $ageSec) }
             elseif ($row.ResetAt) { 'resets ' + (Format-Remaining ($row.ResetAt - $now)) }
             elseif ($hasPct -and $row.Value) { [string]$row.Value }
             else { '' }
    $text.Text = if ($extra) { "$main  $extra" } else { $main }
    $mText.Text = if ($row.Mini) { [string]$row.Mini } elseif ($hasPct) { '{0} {1}%' -f $row.Label, $pct } else { "$($row.Label) $($row.Value)" }
    if ($stale) { $mText.Text += '*' }   # * = old data
    $fg = if ($stale) { $calDim } else { [Windows.Media.Brushes]::White }
    $text.Foreground = $fg; $mText.Foreground = $fg
    $vis = if ($hasPct) { 'Visible' } else { 'Collapsed' }
    $bar.Visibility = $vis; $mBar.Visibility = $vis
    if ($hasPct) {
        $c = if ($pct -ge 95) { $barHot } elseif ($pct -ge 80) { $barWarn } else { $barOk }
        $bar.Value = $pct; $mBar.Value = $pct; $bar.Foreground = $c; $mBar.Foreground = $c
    }
}

# no rows yet (connecting / error) = one row with the message
function Show-ProviderRows($sec, $rows, [double]$ageSec, [string]$emptyText) {
    $rows = @($rows | Where-Object { $_ })
    $sec.Row2.Visibility = if ($rows.Count -ge 2) { 'Visible' } else { 'Collapsed' }
    $sec.MiniCell2.Visibility = $sec.Row2.Visibility
    Set-ProviderRow $(if ($rows.Count -ge 1) { $rows[0] }) $sec.Lbl1 $sec.Text1 $sec.Bar1 $sec.MiniText1 $sec.MiniBar1 $ageSec $emptyText
    Set-ProviderRow $(if ($rows.Count -ge 2) { $rows[1] }) $sec.Lbl2 $sec.Text2 $sec.Bar2 $sec.MiniText2 $sec.MiniBar2 $ageSec $emptyText
}

# ---- API-key providers: Ollama Cloud, OpenRouter, DeepSeek (registered in $keyProviders) ----
# Each is asked once a minute with "Authorization: Bearer <key>"; the key is decrypted only for the request.
function Get-ProviderKey($p) {
    $enc = [string]$settings["$($p.Id)Key"]
    if (-not $enc) { return $null }
    try {
        $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR((ConvertTo-SecureString $enc))
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
    } catch { return $null }   # e.g. settings copied from another Windows account
}

function Reset-ProviderState($p) { $p.View = $null; $p.Error = ''; $p.NextAt = 0; $p.Tasks = $null; $p.Urls = $p.AllUrls }

function Connect-Provider($p, [string]$key) {
    $key = $key.Trim()
    if ($key -notmatch '^[\x21-\x7E]{8,}$') {   # printable, no spaces: it goes into an HTTP header
        if ($script:setWin -and $p.P.Status) { $p.P.Status.Text = 'Paste the whole API key first.' }
        return
    }
    $settings["$($p.Id)Key"] = ConvertTo-SecureString $key -AsPlainText -Force | ConvertFrom-SecureString
    $settings["Show$($p.Id)"] = $true   # connecting means "show it"
    Save-Settings
    Reset-ProviderState $p   # also ignores a reply for the old key
    if ($script:setWin -and $p.P.KeyBox) { $p.P.KeyBox.Clear(); $p.P.ChkShow.IsChecked = $true }
    Apply-Settings
    Update-KeyProvider $p
    Refresh-ProviderUi $p
}

function Disconnect-Provider($p) {
    $settings["$($p.Id)Key"] = ''
    Save-Settings
    Reset-ProviderState $p
    Apply-Settings
    Refresh-ProviderUi $p
}

function Refresh-ProviderUi($p) {
    if (-not $script:setWin -or -not $p.P.Status) { return }
    $c = $p.P
    $hasKey = [bool]$settings["$($p.Id)Key"]
    $c.BtnDisconnect.IsEnabled = $hasKey
    $c.BtnConnect.Content = if ($hasKey) { 'Change key' } else { 'Connect' }
    $hint = switch ($p.Error) {
        'Invalid key'      { ' - paste a new key and press Change key.' }
        'Key expired'      { ' - create a new key, paste it and press Change key.' }
        'Key unreadable'   { ' (saved under another Windows account) - paste the key again.' }
        'Offline'          { " - could not reach $($p.Host), retrying in 5 minutes." }
        'Unexpected reply' { " from $($p.Host) - the API may have changed." }
        default            { '' }
    }
    $c.Status.Text =
        if (-not $hasKey) { 'Not connected.' }
        elseif (-not $settings["Show$($p.Id)"]) { 'Connected, hidden in the gadget (not checking usage).' }
        elseif ($p.Error -and $p.View) { "$($p.Error)$hint Showing the last numbers." }
        elseif ($p.Error) { "$($p.Error)$hint" }
        elseif (-not $p.View) { 'Connecting...' }
        else { $p.View.Status }
}

function Get-HttpStatus($task) {
    $we = if ($task.Exception) { $task.Exception.InnerException } else { $null }
    if ($we -is [Net.WebException] -and $we.Response) { return [int]$we.Response.StatusCode }
    0
}

# error body of a failed request (e.g. OpenRouter says "API key expired." with a 401)
function Get-HttpErrorText($task) {
    try { (New-Object IO.StreamReader($task.Exception.InnerException.Response.GetResponseStream())).ReadToEnd() } catch { '' }
}

function Start-KeyRequests($p) {
    $key = Get-ProviderKey $p
    if (-not $key) { $p.Error = 'Key unreadable'; Refresh-ProviderUi $p; return }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $p.TaskUrls = @($p.Urls)
    $p.Tasks = @(foreach ($u in $p.TaskUrls) {
        $wc = New-Object Net.WebClient   # one per request: a WebClient can't run two at once
        $wc.Headers.Add('Authorization', "Bearer $key")
        $wc.Headers.Add('User-Agent', 'system-monitor-gadget')
        $wc.DownloadStringTaskAsync($u)
    })
}

function Update-KeyProvider($p) {
    if (-not ($settings["$($p.Id)Key"] -and $settings["Show$($p.Id)"])) { return }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (-not $p.Tasks -and $now -ge $p.NextAt) { $p.NextAt = $now + 60; Start-KeyRequests $p }
    if (-not $p.Tasks) { return }
    foreach ($t in $p.Tasks) { if (-not $t.IsCompleted) { return } }
    $tasks = $p.Tasks; $p.Tasks = $null
    $main = $tasks[0]
    if ($main.IsFaulted -or $main.IsCanceled) {
        $code = Get-HttpStatus $main; $retry = 0
        if ($code -eq 429) { [void][int]::TryParse([string]$main.Exception.InnerException.Response.Headers['Retry-After'], [ref]$retry) }
        # short: these show in the gadget row; Refresh-ProviderUi adds hints in Settings
        $p.Error = switch ($code) {
            0       { 'Offline' }
            401     { 'Invalid key' }
            402     { 'Out of credits' }
            403     { 'Access denied' }
            429     { 'Too many requests' }
            503     { 'Unavailable' }
            default { "Error $code" }
        }
        if ($code -eq 401 -and (Get-HttpErrorText $main) -match 'expired') { $p.Error = 'Key expired' }
        # a wrong key won't fix itself: drop old numbers and stop asking often
        if ($code -eq 401 -or $code -eq 403) { $p.View = $null; $p.NextAt = $now + 1800 }
        elseif ($code -eq 429 -and $retry -gt 0) { $p.NextAt = $now + [math]::Max(60, $retry) }
        else { $p.NextAt = $now + 300 }
    } else {
        $bodies = New-Object Collections.Generic.List[object]
        $drop = @()
        for ($i = 0; $i -lt $tasks.Count; $i++) {
            $t = $tasks[$i]
            if ($t.IsFaulted -or $t.IsCanceled) {
                $bodies.Add($null)
                # an extra endpoint this key can't use (e.g. OpenRouter /credits needs a management key): stop asking
                $c = Get-HttpStatus $t
                if ($c -eq 401 -or $c -eq 403) { $drop += $p.TaskUrls[$i] }
            } else { $bodies.Add($t.Result) }
        }
        if ($drop) { $p.Urls = @($p.Urls | Where-Object { $drop -notcontains $_ }) }
        try {
            $v = & $p.Parse $bodies.ToArray()
            if (-not $v -or -not @($v.Rows).Count) { throw 'no rows' }
            $p.View = $v; $p.Stamp = $now; $p.Error = ''
        } catch { $p.Error = 'Unexpected reply'; $p.NextAt = $now + 300 }
    }
    Refresh-ProviderUi $p
}

function Update-KeyProviderRows($p) {
    if (-not ($settings["$($p.Id)Key"] -and $settings["Show$($p.Id)"])) { return }
    $v = $p.View
    $age = if ($v) { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $p.Stamp } else { 0 }
    $empty = if ($p.Error) { $p.Error } else { 'Connecting...' }
    Show-ProviderRows $p.Sec $(if ($v) { $v.Rows }) $age $empty
    $p.Sec.Note.Text = if ($v) { [string]$v.Note } else { '' }
    $tip = if ($v -and $v.Tip) { $v.Tip } else { "$($p.Title)." }
    $tip += if ($p.Error) { " $($p.Error) - see Settings." } else { ' Refreshed every minute.' }
    $p.Sec.Text1.ToolTip = $tip; $p.Sec.Text2.ToolTip = $tip
}

# Ollama Cloud: documented GET https://ollama.com/api/balance (10 req/min). Older plans report session + weekly
# limits (remaining_percent 0-100); newer plans a monthly USD allowance.
function ConvertFrom-OllamaBalance([string]$json) {
    $j = $json | ConvertFrom-Json
    $inc = $j.included
    $purchased = if ($j.purchased -and $null -ne $j.purchased.balance_usd) { [double]$j.purchased.balance_usd } else { 0 }
    $note = if ($purchased -gt 0) { '+${0:N2} credits' -f $purchased } else { '' }
    if ($inc.session -or $inc.weekly) {
        $rows = @()
        if ($inc.session) { $rows += @{ Label = '5hr'; Pct = (Get-Clamped (100 - [double]$inc.session.remaining_percent)); ResetAt = (Convert-ToEpoch $inc.session.resets_at) } }
        if ($inc.weekly)  { $rows += @{ Label = 'Week'; Pct = (Get-Clamped (100 - [double]$inc.weekly.remaining_percent)); ResetAt = (Convert-ToEpoch $inc.weekly.resets_at) } }
        $used = ($rows | ForEach-Object { '{0} {1:N0}% used' -f $_.Label, $_.Pct }) -join ', '
        return @{ Rows = $rows; Note = $note; Tip = 'Ollama Cloud session (5hr) and weekly limits.'; Status = "Connected. $used." }
    }
    if ($null -ne $inc.allowance_usd) {
        $allow = [double]$inc.allowance_usd; $used = [math]::Max(0, $allow - [double]$inc.balance_usd)
        $pct = if ($allow -gt 0) { Get-Clamped ($used / $allow * 100) } else { 0 }
        $txt = '${0:N2} of ${1:N2}' -f $used, $allow
        return @{ Rows = @(@{ Label = 'Month'; Pct = $pct; ResetAt = (Convert-ToEpoch $inc.period.until) }); Note = $note
                  Tip = "Ollama Cloud: $txt included credits used this month."; Status = "Connected. $txt included credits used this month." }
    }
    throw 'unknown shape'
}

# next UTC reset of an OpenRouter key limit ("daily" | "weekly" (Monday) | "monthly"); 0 = never resets
function Get-NextUtcReset([string]$kind) {
    $d = [DateTime]::SpecifyKind([DateTime]::UtcNow.Date, 'Utc')
    $next = switch ($kind) {
        'daily'   { $d.AddDays(1) }
        'weekly'  { $n = (8 - [int]$d.DayOfWeek) % 7; if ($n -eq 0) { $n = 7 }; $d.AddDays($n) }
        'monthly' { $d.AddDays(1 - $d.Day).AddMonths(1) }
        default   { $null }
    }
    if ($next) { ([DateTimeOffset]$next).ToUnixTimeSeconds() } else { 0 }
}

# OpenRouter: documented GET /api/v1/key (this key's spend + limit) and /api/v1/credits (account balance).
# Like DeepSeek, the main row is the balance left; when /credits is refused (it is documented for management
# keys) the key's spend today / this month is shown instead. A key limit, if set, gets its own bar row.
function ConvertFrom-OpenRouterKey([string]$keyJson, [string]$creditsJson) {
    $d = ($keyJson | ConvertFrom-Json).data
    if (-not $d) { throw 'no data' }
    $rows = @()
    $left = $null
    if ($creditsJson) {
        $c = ($creditsJson | ConvertFrom-Json).data
        if ($c) {
            $left = '${0:N2}' -f ([double]$c.total_credits - [double]$c.total_usage)
            $rows += @{ Label = 'Left'; Value = $left; Mini = "$left left" }
        }
    }
    if ($null -ne $d.limit -and [double]$d.limit -gt 0) {
        $lim = [double]$d.limit
        $rem = if ($null -ne $d.limit_remaining) { [double]$d.limit_remaining } else { $lim - [double]$d.usage }
        $used = [math]::Max(0, $lim - $rem)
        $label = switch ([string]$d.limit_reset) { 'daily' { 'Day' } 'weekly' { 'Week' } 'monthly' { 'Month' } default { 'Limit' } }
        $rows += @{ Label = $label; Pct = (Get-Clamped ($used / $lim * 100)); ResetAt = (Get-NextUtcReset ([string]$d.limit_reset)); Value = ('${0:N2} of ${1:N2}' -f $used, $lim) }
    }
    if (-not $left) {
        $rows += @{ Label = 'Today'; Value = ('${0:N2} used' -f [double]$d.usage_daily); Mini = ('Today ${0:N2}' -f [double]$d.usage_daily) }
        if ($rows.Count -lt 2) { $rows += @{ Label = 'Month'; Value = ('${0:N2} used' -f [double]$d.usage_monthly); Mini = ('Month ${0:N2}' -f [double]$d.usage_monthly) } }
    }
    $rows = @($rows | Select-Object -First 2)
    $note = if ($d.is_free_tier) { 'free tier' } else { '' }
    $spend = '${0:N2} today, ${1:N2} this week, ${2:N2} this month, ${3:N2} in total' -f [double]$d.usage_daily, [double]$d.usage_weekly, [double]$d.usage_monthly, [double]$d.usage
    $bal = if ($left) { "Balance left: $left. " } else { '' }
    @{ Rows = $rows; Note = $note; Tip = "OpenRouter. $($bal)This key spent $spend."; Status = "Connected. $($bal)This key spent $spend." }
}

# DeepSeek: documented GET https://api.deepseek.com/user/balance (pay-as-you-go balance, CNY or USD)
function ConvertFrom-DeepSeekBalance([string]$json) {
    $j = $json | ConvertFrom-Json
    if ($null -eq $j.balance_infos) { throw 'no balance_infos' }
    $rows = @()
    foreach ($b in @($j.balance_infos)) {
        $sym = switch ([string]$b.currency) { 'CNY' { [string][char]0x00A5 } 'USD' { '$' } default { "$($b.currency) " } }
        $v = '{0}{1:N2}' -f $sym, [double]$b.total_balance
        $rows += @{ Label = 'Left'; Value = $v; Mini = "$v left" }
    }
    if (-not $rows) { $rows = @(@{ Label = 'Left'; Value = '0.00'; Mini = '0.00 left' }) }
    $detail = (@($j.balance_infos) | ForEach-Object { '{0} {1} (granted {2}, topped up {3})' -f $_.currency, $_.total_balance, $_.granted_balance, $_.topped_up_balance }) -join '; '
    if (-not $detail) { $detail = 'none' }
    $note = if ($j.is_available -eq $false) { 'balance too low' } else { '' }
    @{ Rows = $rows; Note = $note; Tip = "DeepSeek balance: $detail."; Status = "Connected. Balance: $detail." }
}

# ---- Codex (read from the Codex CLI's own session logs on this PC; nothing is sent anywhere) ----
# Codex writes ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl; its "token_count" events carry rate_limits with
# primary / secondary windows: used_percent, window_minutes (300 = 5h, 10080 = week), resets_at (epoch).
$codexHome  = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$codexState = @{ NextScan = 0; Sig = ''; View = $null; Stamp = 0; Found = $false }

function Find-CodexSession {
    $dir = Join-Path $codexHome 'sessions'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    # walk the newest YYYY / MM / DD folder instead of scanning every session ever written
    for ($i = 0; $i -lt 3; $i++) {
        $next = Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if (-not $next) { return $null }
        $dir = $next.FullName
    }
    Get-ChildItem -LiteralPath $dir -Filter 'rollout-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

# last rate_limits snapshot in the file; only the tail is read (sessions can be large) and Codex may be writing it
function Read-CodexLimits($file) {
    $fs = [IO.File]::Open($file.FullName, 'Open', 'Read', 'ReadWrite')
    try {
        $take = [int][math]::Min($fs.Length, 512KB)
        [void]$fs.Seek(-$take, 'End')
        $buf = New-Object byte[] $take
        $n = $fs.Read($buf, 0, $take)
    } finally { $fs.Dispose() }
    $lines = [Text.Encoding]::UTF8.GetString($buf, 0, $n) -split "`n"
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -notlike '*"rate_limits"*') { continue }
        try { $j = $lines[$i] | ConvertFrom-Json } catch { continue }   # the first line may be cut off
        if ($j.payload.rate_limits) { return @{ Limits = $j.payload.rate_limits; At = (Convert-ToEpoch $j.timestamp) } }
    }
    $null
}

function ConvertFrom-CodexLimits($rl, [double]$at) {
    $rows = @()
    foreach ($w in @($rl.primary, $rl.secondary)) {
        if (-not $w) { continue }
        $min = [double]$w.window_minutes
        $label = if ($min -gt 0 -and $min -le 360) { '5hr' } elseif ($min -ge 10000) { 'Week' } elseif ($min -gt 0) { '{0}h' -f [math]::Round($min / 60) } else { 'Limit' }
        $reset = if ($w.resets_at -is [string]) { Convert-ToEpoch $w.resets_at } elseif ($w.resets_at) { [double]$w.resets_at }
                 elseif ($w.resets_in_seconds) { $at + [double]$w.resets_in_seconds } else { 0 }
        $rows += @{ Label = $label; Pct = (Get-Clamped ([double]$w.used_percent)); ResetAt = $reset; Min = $min }
    }
    @{ Rows = @($rows | Sort-Object { $_.Min }); Plan = [string]$rl.plan_type }
}

function Update-Codex {
    if (-not $settings.ShowCodex) { return }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($now -lt $codexState.NextScan) { return }
    $codexState.NextScan = $now + 15
    $found = Test-Path -LiteralPath (Join-Path $codexHome 'sessions')
    if ($found -ne $codexState.Found) { $codexState.Found = $found; Apply-Settings }
    $f = Find-CodexSession
    if (-not $f) { return }
    $sig = '{0}|{1}|{2}' -f $f.FullName, $f.Length, $f.LastWriteTimeUtc.Ticks
    if ($sig -eq $codexState.Sig) { return }
    $codexState.Sig = $sig
    try { $r = Read-CodexLimits $f } catch { $r = $null }
    if ($r) {   # a brand-new session has no snapshot yet: keep the previous one
        $codexState.Stamp = if ($r.At -gt 0) { $r.At } else { ([DateTimeOffset]$f.LastWriteTimeUtc).ToUnixTimeSeconds() }
        $codexState.View = ConvertFrom-CodexLimits $r.Limits $codexState.Stamp
    }
    Refresh-CodexUi
}

function Update-CodexRows {
    if (-not ($settings.ShowCodex -and $codexState.Found)) { return }
    $v = $codexState.View
    $age = if ($v) { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $codexState.Stamp } else { 0 }
    $empty = if ($v) { 'Use Codex to refresh' } else { 'No data - use Codex' }
    Show-ProviderRows $codexSec $(if ($v) { $v.Rows }) $age $empty
    $codexSec.Note.Text = if ($v -and $v.Plan) { "$($v.Plan) plan" } else { '' }
    $tip = 'Codex limits, read from the Codex session files on this PC. They update while you use Codex.'
    $codexSec.Text1.ToolTip = $tip; $codexSec.Text2.ToolTip = $tip
}

function Refresh-CodexUi {
    if (-not $script:setWin) { return }
    $v = $codexState.View
    $script:setUi.CodexStatus.Text =
        if (-not (Test-Path -LiteralPath (Join-Path $codexHome 'sessions'))) { "No Codex sessions found in $codexHome\sessions. Install the Codex CLI and use it once." }
        elseif (-not $settings.ShowCodex) { 'Hidden in the gadget.' }
        elseif (-not $v) { 'Found Codex, but no usage data yet - send Codex a message.' }
        else { 'Last update from Codex: {0} ago ({1} plan).' -f (Format-Age ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $codexState.Stamp)), $v.Plan }
}

$update = {
    Update-Poll
    # before the hidden check so the Settings status still updates while the gadget is hidden
    foreach ($p in $keyProviders.Values) { Update-KeyProvider $p }
    # hidden: skip work, and don't call SetWindowPos below (its SHOWWINDOW flag would re-show the window)
    if ($win.Visibility -ne 'Visible') { return }
    Update-LivePoll
    Update-Codex
    Update-Calendar
    Get-UsageData
    $rl = if ($usageState.Data) { $usageState.Data.rate_limits } else { $null }
    $fh = if ($rl) { $rl.five_hour } else { $null }
    $sd = if ($rl) { $rl.seven_day } else { $null }
    $age = if ($usageState.Data -and $usageState.Data.updatedAt) { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [double]$usageState.Data.updatedAt } else { 0 }
    $isLive = $false
    if ($settings.LiveClaudeUsage -and $liveState.Data) {   # fresh live numbers win over the CLI file
        $liveAge = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $liveState.Stamp
        if ($liveAge -lt 600) { $fh = $liveState.Data.five_hour; $sd = $liveState.Data.seven_day; $age = $liveAge; $isLive = $true }
    }
    $s = $claudeSec
    Set-UsageRow $fh $s.Text1 $s.Bar1 $age
    Set-UsageRow $sd $s.Text2 $s.Bar2 $age
    # where the numbers come from (blank while the first live request is still running)
    $s.Note.Text = if ($isLive) { 'live' } elseif (-not $settings.LiveClaudeUsage) { 'CLI' } elseif ($liveState.Error) { 'CLI (live failed)' } else { '' }
    $usageTip = if (-not $settings.LiveClaudeUsage) { 'Live Claude usage is off: these numbers only update while you use the Claude CLI. Turn it on in Settings (gear).' }
                elseif ($liveState.Error) { "Live Claude usage: $($liveState.Error) - showing the last CLI numbers." }
                else { 'Live Claude usage (refreshed every 2 minutes).' }
    $s.Text1.ToolTip = $usageTip; $s.Text2.ToolTip = $usageTip; $s.Note.ToolTip = $usageTip
    Set-MiniUsage $fh '5hr' $s.MiniText1 $s.MiniBar1 $age
    Set-MiniUsage $sd 'Week' $s.MiniText2 $s.MiniBar2 $age
    Update-CodexRows
    foreach ($p in $keyProviders.Values) { Update-KeyProviderRows $p }
    $m = Get-Metrics
    $ui.MiniCpuText.Text = 'CPU {0}%' -f $m.Cpu
    $ui.MiniCpuBar.Value = $m.Cpu
    $ui.MiniRamText.Text = 'RAM {0}%' -f $m.RamPct
    $ui.MiniRamBar.Value = $m.RamPct
    $ui.CpuText.Text  = '{0}%' -f $m.Cpu
    $ui.CpuBar.Value  = $m.Cpu
    $ui.RamText.Text  = '{0:N1} / {1:N1} GB ({2}%)' -f $m.RamUsedGB, $m.RamTotGB, $m.RamPct
    $ui.RamBar.Value  = $m.RamPct
    $ui.DiskText.Text = '{0}: {1}% ({2:N0} GB free)' -f $sysDrive, $m.DiskPct, $m.DiskFreeGB
    $ui.DiskBar.Value = $m.DiskPct
    $ui.NetText.Text  = [string]::Format([char]0x2193 + ' {0}  ' + [char]0x2191 + ' {1}', (Format-Speed $m.Down), (Format-Speed $m.Up))
    # keep position (resolution / taskbar changes) and re-assert topmost
    Set-Position
    $h = (New-Object Windows.Interop.WindowInteropHelper $win).Handle
    [void][Win32]::SetWindowPos($h, $HWND_TOPMOST, 0, 0, 0, 0, $SWP_FLAGS)
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick($update)
# First refresh after the first frame, not in Loaded: start-monitor.vbs starts PowerShell hidden, which hides
# the first window, and only $update's SetWindowPos (SHOWWINDOW) shows it - so it must not wait on slow work.
$win.Add_Loaded({ $timer.Start() })
$win.Add_ContentRendered({ & $update })

# Application.Run (not ShowDialog): hiding a ShowDialog window would end the program
$app = New-Object Windows.Application
$app.ShutdownMode = 'OnMainWindowClose'
[void]$app.Run($win)
