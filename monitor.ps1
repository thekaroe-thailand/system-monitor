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
$AppVersion = '1.2.6'
$repoSlug   = 'thekaroe-thailand/system-monitor'
$settings = @{ Transparency = 25; ShowCalendar = $true; ShowClaude = $true; Collapsed = $false
               AutoCheckUpdates = $true; LastUpdateCheck = 0; LatestTag = ''
               AutoInstallUpdates = $true; LastAutoAttemptTag = ''; LastAutoAttemptAt = 0
               LiveClaudeUsage = $false }
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
    <Grid Name="MainGrid" Height="176">
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/><RowDefinition Height="*"/><RowDefinition Height="*"/><RowDefinition Height="*"/>
        <RowDefinition Height="*"/><RowDefinition Height="*"/>
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
      <TextBlock Grid.Row="4" Foreground="#9AA0A6" FontSize="12" Text="5hr" VerticalAlignment="Center"/>
      <StackPanel Grid.Row="4" Grid.Column="1" VerticalAlignment="Center">
        <TextBlock Name="SessText" Foreground="White" FontSize="12" HorizontalAlignment="Right"/>
        <ProgressBar Name="SessBar" Height="4" Maximum="100" Foreground="#26A69A" Background="#33FFFFFF" BorderThickness="0"/>
      </StackPanel>
      <TextBlock Grid.Row="5" Foreground="#9AA0A6" FontSize="12" Text="Week" VerticalAlignment="Center"/>
      <StackPanel Grid.Row="5" Grid.Column="1" VerticalAlignment="Center">
        <TextBlock Name="WeekText" Foreground="White" FontSize="12" HorizontalAlignment="Right"/>
        <ProgressBar Name="WeekBar" Height="4" Maximum="100" Foreground="#26A69A" Background="#33FFFFFF" BorderThickness="0"/>
      </StackPanel>
    </Grid>
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
      <Grid VerticalAlignment="Center" Margin="0,2,16,2">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,8,0">
          <TextBlock Name="MiniCpuText" Foreground="White" FontSize="11"/>
          <ProgressBar Name="MiniCpuBar" Height="4" Maximum="100" Foreground="#4FC3F7" Background="#33FFFFFF" BorderThickness="0" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel Grid.Row="0" Grid.Column="1">
          <TextBlock Name="MiniRamText" Foreground="White" FontSize="11"/>
          <ProgressBar Name="MiniRamBar" Height="4" Maximum="100" Foreground="#81C784" Background="#33FFFFFF" BorderThickness="0" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel Name="MiniSessCell" Grid.Row="1" Grid.Column="0" Margin="0,6,8,0">
          <TextBlock Name="MiniSessText" Foreground="White" FontSize="11"/>
          <ProgressBar Name="MiniSessBar" Height="4" Maximum="100" Foreground="#26A69A" Background="#33FFFFFF" BorderThickness="0" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel Name="MiniWeekCell" Grid.Row="1" Grid.Column="1" Margin="0,6,0,0">
          <TextBlock Name="MiniWeekText" Foreground="White" FontSize="11"/>
          <ProgressBar Name="MiniWeekBar" Height="4" Maximum="100" Foreground="#26A69A" Background="#33FFFFFF" BorderThickness="0" Margin="0,2,0,0"/>
        </StackPanel>
      </Grid>
      <TextBlock Name="MiniPlus" Foreground="#9AA0A6" FontFamily="Segoe UI Symbol" FontSize="13" Text="+"
                 HorizontalAlignment="Right" VerticalAlignment="Center" Padding="4,0"/>
    </Grid>
    </Grid>
  </Border>
</Window>
"@

$win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'CpuText','CpuBar','RamText','RamBar','DiskText','DiskBar','NetText','SessText','SessBar','WeekText','WeekBar','CalPanel','CalPrev','CalTitle','CalNext','CalGrid','Root','MainGrid','VerText','MenuVer','BtnUpdate','BtnSettings','BtnHide','FullPanel','MiniPanel','MiniCpuText','MiniCpuBar','MiniRamText','MiniRamBar','MiniSessCell','MiniSessText','MiniSessBar','MiniWeekCell','MiniWeekText','MiniWeekBar','MenuSettings','MenuHide','MenuExit') { $ui[$n] = $win.FindName($n) }
$ui.MenuExit.Add_Click({ $win.Close() })

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
    # rows 4-5 of the main grid are the Claude usage rows; collapse them and shrink the grid to match
    $showClaude = [bool]$settings.ShowClaude
    $vis = if ($showClaude) { 'Visible' } else { 'Collapsed' }
    foreach ($c in $ui.MainGrid.Children) { if ([Windows.Controls.Grid]::GetRow($c) -ge 4) { $c.Visibility = $vis } }
    foreach ($i in 4, 5) {
        $ui.MainGrid.RowDefinitions[$i].Height = if ($showClaude) { [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star) } else { [Windows.GridLength]::new(0) }
    }
    $ui.MainGrid.Height = 176 / 6 * $(if ($showClaude) { 6 } else { 4 })
    # collapsed = small one-line bar (CPU / RAM) instead of the full gadget
    $ui.FullPanel.Visibility = if ($settings.Collapsed) { 'Collapsed' } else { 'Visible' }
    $ui.MiniPanel.Visibility = if ($settings.Collapsed) { 'Visible' } else { 'Collapsed' }
    $ui.MiniSessCell.Visibility = $vis
    $ui.MiniWeekCell.Visibility = $vis
}

function Set-Collapsed([bool]$collapsed) {
    $settings.Collapsed = $collapsed
    Apply-Settings; Save-Settings
    $win.UpdateLayout()
    Set-Position
}

# ---- settings window (opened from the right-click menu) ----
[xml]$setXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="System Monitor Settings" Width="290" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True" Background="#202124">
  <StackPanel Margin="16">
    <TextBlock Name="TransLabel" Foreground="White" FontSize="13"/>
    <Slider Name="TransSlider" Minimum="0" Maximum="90" TickFrequency="5" IsSnapToTickEnabled="True" Margin="0,6,0,2"/>
    <TextBlock Text="0% = solid, higher = more see-through" Foreground="#9AA0A6" FontSize="11" Margin="0,0,0,14"/>
    <CheckBox Name="ChkCal" Content="Show calendar" Foreground="White" Margin="0,0,0,8"/>
    <CheckBox Name="ChkClaude" Content="Show Claude usage (5hr / Week)" Foreground="White"/>
    <CheckBox Name="ChkLive" Content="Live Claude usage (uses your Claude login)" Foreground="White" Margin="0,8,0,0"/>
    <TextBlock Text="Off by default. Reads the login token in ~\.claude\.credentials.json (read-only) and asks api.anthropic.com every 2 minutes, so the numbers match Claude even when you only use VS Code. Unofficial endpoint: it may stop working."
               Foreground="#6B7075" FontSize="10" TextWrapping="Wrap" Margin="22,2,0,0"/>
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
</Window>
"@
$script:setWin = $null
$script:setUi = @{}

function Show-Settings {
    if ($script:setWin) { [void]$script:setWin.Activate(); return }
    $w = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $setXaml))
    $script:setWin = $w
    foreach ($n in 'TransLabel','TransSlider','ChkCal','ChkClaude','ChkLive','VerLabel','ChkUpdate','ChkAutoInstall','BtnCheck','BtnDoUpdate','UpdStatus') { $script:setUi[$n] = $w.FindName($n) }
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
    Refresh-UpdateUi
    $w.Add_Closed({ $script:setWin = $null })
    $w.Show()
}
$ui.MenuSettings.Add_Click({ Show-Settings })
# version shown in: gadget corner, tooltips, right-click menu (tray + Settings title are set further down)
$ui.VerText.Text = "v$AppVersion"
$ui.MenuVer.Header = "System Monitor v$AppVersion"
$ui.BtnSettings.ToolTip = "Settings (v$AppVersion)"
$ui.MiniPanel.ToolTip = "Click to expand (v$AppVersion)"
$ui.BtnUpdate.Text = 'Update'
$ui.BtnUpdate.Add_MouseLeftButtonUp({ Show-Settings })
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

$update = {
    Update-Poll
    # hidden: skip work, and don't call SetWindowPos below (its SHOWWINDOW flag would re-show the window)
    if ($win.Visibility -ne 'Visible') { return }
    Update-LivePoll
    Update-Calendar
    Get-UsageData
    $rl = if ($usageState.Data) { $usageState.Data.rate_limits } else { $null }
    $fh = if ($rl) { $rl.five_hour } else { $null }
    $sd = if ($rl) { $rl.seven_day } else { $null }
    $age = if ($usageState.Data -and $usageState.Data.updatedAt) { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [double]$usageState.Data.updatedAt } else { 0 }
    if ($settings.LiveClaudeUsage -and $liveState.Data) {   # fresh live numbers win over the CLI file
        $liveAge = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $liveState.Stamp
        if ($liveAge -lt 600) { $fh = $liveState.Data.five_hour; $sd = $liveState.Data.seven_day; $age = $liveAge }
    }
    Set-UsageRow $fh $ui.SessText $ui.SessBar $age
    Set-UsageRow $sd $ui.WeekText $ui.WeekBar $age
    $usageTip = if (-not $settings.LiveClaudeUsage) { 'Live Claude usage is off: these numbers only update while you use the Claude CLI. Turn it on in Settings (gear).' }
                elseif ($liveState.Error) { "Live Claude usage: $($liveState.Error) - showing the last CLI numbers." }
                else { 'Live Claude usage (refreshed every 2 minutes).' }
    $ui.SessText.ToolTip = $usageTip; $ui.WeekText.ToolTip = $usageTip
    Set-MiniUsage $fh '5hr' $ui.MiniSessText $ui.MiniSessBar $age
    Set-MiniUsage $sd 'Week' $ui.MiniWeekText $ui.MiniWeekBar $age
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
$win.Add_Loaded({ & $update; $timer.Start() })

# Application.Run (not ShowDialog): hiding a ShowDialog window would end the program
$app = New-Object Windows.Application
$app.ShutdownMode = 'OnMainWindowClose'
[void]$app.Run($win)
