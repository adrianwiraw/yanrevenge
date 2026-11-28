# ============================================================
#  pembersih + audit y4nn / "SysMon"  v3 (ASCII murni)
#  Jalankan: powershell -NoProfile -ExecutionPolicy Bypass -File .\clean.ps1
#  Setujui UAC. Aman diulang. Exit 0 = bersih, 1 = ada sisa.
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    $exe = (Get-Process -Id $PID).Path
    if ($PSCommandPath) {
        $arg = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath))
    } else {
        $b64 = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($MyInvocation.MyCommand.Definition))
        $arg = @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$b64)
    }
    Start-Process -FilePath $exe -Verb RunAs -ArgumentList $arg
    exit
}

$ns      = 'root/subscription'
$ns2     = 'root/default'
$hkSys   = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\SysMon'
$hkSysU  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SysMon'
$hkSysW  = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\SysMon'
$runK    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runKL   = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
$runKW   = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
$runOnce = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
             'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce')
$policy  = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run',
             'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run')
$winlogon= 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$desk    = 'HKCU:\Control Panel\Desktop'
$appDir  = Join-Path $env:ProgramData 'Microsoft\Windows\SysMon'
$backup  = Join-Path $env:TEMP ('y4nn-backup-' + (Get-Date -Format yyyyMMdd-HHmmss))

New-Item -ItemType Directory $backup -Force | Out-Null
Start-Transcript -Path (Join-Path $backup 'log.txt') -Force | Out-Null

Write-Host ''
Write-Host '  pembersih + audit y4nn / SysMon' -ForegroundColor Cyan
Write-Host '  -------------------------------' -ForegroundColor DarkGray

# ---------- 1. kumpulkan target WMI ----------
$regF = (Get-ItemProperty $hkSys -Name FilterName  ).FilterName
$regC = (Get-ItemProperty $hkSys -Name ConsumerName).ConsumerName

$filters   = @(Get-CimInstance -Namespace $ns -ClassName __EventFilter)
$consumers = @(Get-CimInstance -Namespace $ns -ClassName CommandLineEventConsumer)
$bindings  = @(Get-CimInstance -Namespace $ns -ClassName __FilterToConsumerBinding)

$hitF = @($filters | Where-Object {
    $_.Name -eq $regF -or
    $_.Name -eq 'SysMon' -or
    ($_.Query -like '*Win32_PerfFormattedData_PerfOS_System*' -and
     $_.Query -like '*SystemUpTime*') -or
    ($_.Name -match '^S[a-z]{8}$' -and $_.Query -like '*SystemUpTime*')
})

$hitC = @($consumers | Where-Object {
    $_.Name -eq $regC -or
    $_.Name -eq 'SysMon-c' -or
    $_.CommandLineTemplate -like '*y4nn*' -or
    ($_.Name -match '-c$' -and $hitF.Name -contains ($_.Name -replace '-c$',''))
})

$hitB = @($bindings | Where-Object {
    $bb = $_
    ($hitF | Where-Object { $bb.Filter   -like ('*' + $_.Name + '*') }) -or
    ($hitC | Where-Object { $bb.Consumer -like ('*' + $_.Name + '*') })
})

$dirs = New-Object 'System.Collections.Generic.HashSet[string]'
[void]$dirs.Add($appDir)
foreach ($c in $hitC) {
    if ($c.CommandLineTemplate -match '"([^"]+\.exe)"') {
        [void]$dirs.Add((Split-Path $Matches[1] -Parent))
    }
}
$uiRaw = (Get-ItemProperty $winlogon -Name Userinit).Userinit
foreach ($m in [regex]::Matches([string]$uiRaw, '[A-Za-z]:\\[^,"]+\\y4nn\.exe')) {
    [void]$dirs.Add((Split-Path $m.Value -Parent))
}

# ---------- 2. hapus WMI ----------
for ($pass = 1; $pass -le 2; $pass++) {
    $nowB = @(Get-CimInstance -Namespace $ns -ClassName __FilterToConsumerBinding |
              Where-Object {
                 $bb = $_
                 ($hitF | Where-Object { $bb.Filter   -like ('*' + $_.Name + '*') }) -or
                 ($hitC | Where-Object { $bb.Consumer -like ('*' + $_.Name + '*') }) })
    foreach ($b in $nowB) { Remove-CimInstance -InputObject $b }
    foreach ($c in $hitC) { Remove-CimInstance -InputObject $c }
    foreach ($f in $hitF) { Remove-CimInstance -InputObject $f }
}
Write-Host ("  WMI        : {0} filter, {1} consumer, {2} binding dihapus" -f `
    $hitF.Count, $hitC.Count, $hitB.Count) -ForegroundColor Gray

# ---------- 3. hentikan proses ----------
$killed = 0
foreach ($p in @(Get-Process y4nn -ErrorAction SilentlyContinue)) {
    Stop-Process -Id $p.Id -Force; $killed++
}
Start-Sleep -Milliseconds 900
Write-Host ("  proses     : {0} dihentikan" -f $killed) -ForegroundColor Gray

# ---------- 4. berkas ----------
foreach ($d in $dirs) {
    if (-not (Test-Path -LiteralPath $d)) { continue }
    try { (Get-Item -LiteralPath $d -Force).Attributes = 'Directory' } catch {}
    Get-ChildItem -LiteralPath $d -Force | ForEach-Object {
        try { $_.Attributes = 'Normal' } catch {}
    }
    $m = Join-Path $d 'message.txt'
    if (Test-Path -LiteralPath $m) { Copy-Item -LiteralPath $m $backup -Force }

    if ($d -like '*\SysMon') {
        for ($i = 0; $i -lt 5; $i++) {
            Get-ChildItem -LiteralPath $d -Force | Remove-Item -Recurse -Force
            if (-not (Get-ChildItem -LiteralPath $d -Force)) { break }
            Start-Sleep -Milliseconds 500
        }
        Remove-Item -LiteralPath $d -Recurse -Force
    } else {
        Get-ChildItem -LiteralPath $d -Force -Filter 'y4nn*' | Remove-Item -Force
    }
    Write-Host ("  folder     : {0}" -f $d) -ForegroundColor Gray
}

foreach ($dd in @([Environment]::GetFolderPath('Desktop'), (Join-Path $env:PUBLIC 'Desktop'))) {
    $m = Join-Path $dd 'message.txt'
    if (Test-Path -LiteralPath $m) {
        Copy-Item -LiteralPath $m $backup -Force
        Remove-Item -LiteralPath $m -Force
        Write-Host ("  pesan      : {0}" -f $m) -ForegroundColor Gray
    }
}

# ---------- 5. registry ----------
foreach ($k in @($hkSys, $hkSysU, $hkSysW)) { Remove-Item $k -Recurse -Force }
foreach ($k in @($runK, $runKL, $runKW) + $runOnce + $policy) {
    foreach ($n in @('Y4nnWallpaper', 'SysMon', 'y4nn')) {
        Remove-ItemProperty $k -Name $n -Force
    }
}

# ---------- 6. Userinit ----------
if ($uiRaw) {
    $parts = @([string]$uiRaw -split ',' | ForEach-Object { $_.Trim() } |
               Where-Object { $_ -and $_ -notmatch 'y4nn' })
    if (-not ($parts | Where-Object { $_ -match '(?i)userinit\.exe' })) {
        $parts = @('C:\Windows\system32\userinit.exe') + $parts
    }
    $fixed = ($parts -join ',')
    if ($fixed -ne $uiRaw) {
        Set-ItemProperty $winlogon -Name Userinit -Value $fixed -Type String
        Write-Host ("  Userinit   : {0}" -f $fixed) -ForegroundColor Gray
    }
}

# ---------- 7. wallpaper ----------
$wp = (Get-ItemProperty $desk -Name Wallpaper).Wallpaper
if (-not $wp -or $wp -match '(?i)SysMon\\wallpaper\.png') {
    $def = Join-Path $env:WINDIR 'Web\Wallpaper\Windows\img0.jpg'
    Set-ItemProperty $desk -Name Wallpaper      -Value $def -Type String
    Set-ItemProperty $desk -Name WallpaperStyle -Value '10' -Type String
    Set-ItemProperty $desk -Name TileWallpaper  -Value '0'  -Type String
    if (-not ('U.W' -as [type])) {
        Add-Type -Namespace U -Name W -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true, CharSet=System.Runtime.InteropServices.CharSet.Auto)]
public static extern int SystemParametersInfo(int a, int b, string c, int d);
'@
    }
    [void][U.W]::SystemParametersInfo(20, 0, $def, 0x01 -bor 0x02)
    Write-Host ("  wallpaper  : dipulihkan ke {0}" -f $def) -ForegroundColor Gray
}

# ============================================================
#  8. AUDIT LENGKAP
# ============================================================
Write-Host ''
Write-Host '  audit jejak' -ForegroundColor Cyan
Write-Host '  ------------' -ForegroundColor DarkGray

$issues = New-Object 'System.Collections.Generic.List[string]'
function Chk($label, [bool]$ok, $detail) {
    if ($ok) { Write-Host ("    [bersih] {0}" -f $label) -ForegroundColor Green }
    else {
        Write-Host ("    [SISA]   {0}{1}" -f $label, $(if ($detail) { ' -> ' + $detail } else { '' })) -ForegroundColor Red
        $issues.Add($label)
    }
}

# 8.1 WMI
$lf = @(Get-CimInstance -Namespace $ns -ClassName __EventFilter | Where-Object {
    $_.Name -eq 'SysMon' -or $_.Name -match '^S[a-z]{8}$' -or
    ($_.Query -like '*Win32_PerfFormattedData_PerfOS_System*' -and $_.Query -like '*SystemUpTime*') })
Chk 'WMI filter' ($lf.Count -eq 0) (($lf.Name) -join ', ')

$lf2 = @(Get-CimInstance -Namespace $ns2 -ClassName __EventFilter | Where-Object {
    $_.Query -like '*y4nn*' -or $_.Name -eq 'SysMon' })
Chk 'WMI filter (root\default)' ($lf2.Count -eq 0) (($lf2.Name) -join ', ')

$lc = @(Get-CimInstance -Namespace $ns -ClassName __EventConsumer | Where-Object {
    $_.Name -eq 'SysMon-c' -or $_.Name -match '^S[a-z]{8}-c$' -or
    $_.CommandLineTemplate -like '*y4nn*' -or $_.ExecutablePath -like '*y4nn*' -or
    $_.ScriptText -like '*y4nn*' })
Chk 'WMI consumer' ($lc.Count -eq 0) (($lc.Name) -join ', ')

$lb = @(Get-CimInstance -Namespace $ns -ClassName __FilterToConsumerBinding | Where-Object {
    $_.Filter -like '*y4nn*' -or $_.Consumer -like '*y4nn*' -or
    $_.Filter -match '^__EventFilter\.Name="S[a-z]{8}"' -or
    $_.Consumer -match '^CommandLineEventConsumer\.Name="S[a-z]{8}-c"' })
Chk 'WMI binding' ($lb.Count -eq 0) ("{0} binding" -f $lb.Count)

# 8.2 Userinit & Shell
$uiNow = [string](Get-ItemProperty $winlogon -Name Userinit).Userinit
Chk 'Userinit' ($uiNow -notmatch '(?i)y4nn') $uiNow
Chk 'Userinit diawali userinit.exe' ($uiNow -match '^(?i)C:\\Windows\\system32\\userinit\.exe') $uiNow
$sh = [string](Get-ItemProperty $winlogon -Name Shell).Shell
Chk 'Winlogon Shell' ($sh -notmatch '(?i)y4nn') $sh

# 8.3 autostart
$hitAuto = @()
foreach ($k in @($runK, $runKL, $runKW) + $runOnce + $policy) {
    if (-not (Test-Path $k)) { continue }
    $p = Get-ItemProperty $k
    foreach ($n in $p.PSObject.Properties.Name) {
        if ($p.$n -match '(?i)y4nn') { $hitAuto += ('{0}\{1}' -f $k, $n) }
    }
}
Chk 'Run / RunOnce / Policies' ($hitAuto.Count -eq 0) ($hitAuto -join '; ')

$su = @(Get-CimInstance Win32_StartupCommand | Where-Object { $_.Command -match '(?i)y4nn' })
Chk 'startup (WMI view)' ($su.Count -eq 0) (($su.Name) -join ', ')

foreach ($sd in @([Environment]::GetFolderPath('Startup'),
                  (Join-Path $env:PUBLIC 'Microsoft\Windows\Start Menu\Programs\StartUp'))) {
    $h = @(Get-ChildItem -LiteralPath $sd -Force | Where-Object { $_.Name -match '(?i)y4nn' })
    Chk ("folder startup: {0}" -f (Split-Path $sd -Leaf)) ($h.Count -eq 0) (($h.Name) -join ', ')
}

# 8.4 scheduled task & service
$st = @(Get-ScheduledTask | Where-Object {
    $_.Actions.Execute -match '(?i)y4nn' -or $_.TaskName -match '(?i)y4nn|sysmon' })
Chk 'scheduled task' ($st.Count -eq 0) (($st.TaskName) -join ', ')

$sv = @(Get-CimInstance Win32_Service | Where-Object { $_.PathName -match '(?i)y4nn' })
Chk 'service' ($sv.Count -eq 0) (($sv.Name) -join ', ')

# 8.5 registry kunci
$hitKey = @(@($hkSys, $hkSysU, $hkSysW) | Where-Object { Test-Path $_ })
Chk 'kunci registry SysMon' ($hitKey.Count -eq 0) ($hitKey -join '; ')

# 8.6 berkas
$leftD = @($dirs | Where-Object { Test-Path -LiteralPath $_ })
Chk 'folder induk' ($leftD.Count -eq 0) ($leftD -join '; ')

$hiddenLeft = @()
foreach ($d in $leftD) {
    if ((Get-Item -LiteralPath $d -Force).Attributes -band [IO.FileAttributes]::Hidden) {
        $hiddenLeft += $d
    }
}
Chk 'atribut hidden sisa' ($hiddenLeft.Count -eq 0) ($hiddenLeft -join '; ')

$msgLeft = @(@([Environment]::GetFolderPath('Desktop'),
               (Join-Path $env:PUBLIC 'Desktop')) |
             ForEach-Object { Join-Path $_ 'message.txt' } |
             Where-Object { Test-Path -LiteralPath $_ })
Chk 'message.txt di desktop' ($msgLeft.Count -eq 0) ($msgLeft -join '; ')

$leftP = @(Get-Process y4nn -ErrorAction SilentlyContinue)
Chk 'proses berjalan' ($leftP.Count -eq 0) (($leftP.Id) -join ', ')

# 8.7 salinan liar -> cadangan
$strays = @()
$roots  = @($env:TEMP, $env:LOCALAPPDATA, (Join-Path $env:USERPROFILE 'Downloads'),
            (Join-Path $env:USERPROFILE 'Desktop'), $env:PUBLIC, $env:ProgramData)
foreach ($r in $roots) {
    if (-not (Test-Path -LiteralPath $r)) { continue }
    $strays += @(Get-ChildItem -LiteralPath $r -Filter 'y4nn*' -Force -Recurse -Depth 3 |
                 Where-Object { $_.FullName -notlike "$appDir*" })
}
$strays = @($strays | Sort-Object FullName -Unique)
$moved = 0
foreach ($s in $strays) {
    $dst = Join-Path $backup ('stray_' + [IO.Path]::GetFileName($s.FullName))
    Move-Item -LiteralPath $s.FullName $dst -Force -ErrorAction SilentlyContinue
    if ($?) { $moved++ }
}
Write-Host ("    [info]   salinan liar dipindah ke cadangan: {0}" -f $moved) -ForegroundColor DarkGray
foreach ($s in $strays) { Write-Host ("             {0}" -f $s.FullName) -ForegroundColor DarkGray }

# 8.8 wallpaper menunjuk berkas yang ada
$wpNow = [string](Get-ItemProperty $desk -Name Wallpaper).Wallpaper
Chk 'wallpaper valid' ((-not $wpNow) -or (Test-Path -LiteralPath $wpNow)) $wpNow

# 8.9 ACL folder
foreach ($d in $leftD) {
    $a = (Get-Acl -LiteralPath $d).Access |
         Where-Object { $_.IdentityReference -match '(?i)S-1-5-18|SYSTEM' -and
                         $_.FileSystemRights -match 'FullControl' }
    Chk ("ACL {0}" -f $d) ([bool]$a) 'SYSTEM full control hilang'
}

# ============================================================
#  9. putusan
# ============================================================
Write-Host ''
if ($issues.Count -eq 0) {
    Write-Host '  BERSIH - 15 permukaan diperiksa, tidak ada sisa.' -ForegroundColor Green
    Write-Host '  Restart sekali untuk membuang y4nn.old.exe yang tertunda.' -ForegroundColor DarkGray
    $code = 0
} else {
    Write-Host ("  ADA {0} SISA - jalankan ulang skrip, lalu restart." -f $issues.Count) -ForegroundColor Yellow
    foreach ($i in $issues) { Write-Host ("    - {0}" -f $i) -ForegroundColor Yellow }
    $code = 1
}
Write-Host ("  cadangan  : {0}" -f $backup) -ForegroundColor DarkGray
Stop-Transcript | Out-Null
if (-not $PSCommandPath) { Read-Host '  tekan Enter' }
exit $code