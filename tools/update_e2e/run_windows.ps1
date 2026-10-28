# Windows end-to-end self-update (run on the Windows test PC from the project root, after export_windows.sh on the mini and
# copying its win/ folder here as .\e2e\win):  powershell -ExecutionPolicy Bypass -File tools\update_e2e\run_windows.ps1
$ErrorActionPreference = 'Continue'
$Work = Join-Path (Get-Location) 'e2e\win'
$Install = Join-Path $Work 'install'
Remove-Item -Recurse -Force $Install -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Install | Out-Null
Expand-Archive -Path (Join-Path $Work 'a\KyttusLab-Windows-Debug.zip') -DestinationPath $Install -Force
$env:LASTROUTE_HTTP_PORT = '18105'; $env:LASTROUTE_RELAY_PORT = '18106'
$env:LASTROUTE_UPDATE_DIR = Join-Path $Work 'serve'; $env:LASTROUTE_UPDATE_MANIFEST = Join-Path $Work 'serve\updates.debug.json'
$env:LASTROUTE_ACCOUNT_STORE = Join-Path $Work 'accounts.json'
$Backend = Start-Process -FilePath node -ArgumentList 'backend\server.mjs' -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Work 'backend.log') -RedirectStandardError (Join-Path $Work 'backend.err')
Start-Sleep 3
(Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:18105/api/updates/debug/windows').Content.Substring(0, 200)
$OldPck = (Get-FileHash (Join-Path $Install 'KyttusLab.exe')).Hash
$Game = Start-Process -FilePath (Join-Path $Install 'KyttusLab.exe') -ArgumentList '--headless','--','--backend=http://127.0.0.1:18105','--update-smoke' -PassThru -RedirectStandardOutput (Join-Path $Work 'a-run.log') -RedirectStandardError (Join-Path $Work 'a-run.err')
$Game | Wait-Process -Timeout 240 -ErrorAction SilentlyContinue
Select-String -Path (Join-Path $Work 'a-run.log') -Pattern 'UPDATE_SMOKE' | ForEach-Object { $_.Line }
Start-Sleep 10
$NewPck = (Get-FileHash (Join-Path $Install 'KyttusLab.exe')).Hash
Expand-Archive -Path (Join-Path $Work 'b\KyttusLab-Windows-Debug.zip') -DestinationPath (Join-Path $Work 'checkb') -Force
$BPck = (Get-FileHash (Join-Path $Work 'checkb\KyttusLab.exe')).Hash
if ($NewPck -eq $BPck -and $NewPck -ne $OldPck) { 'E2E PASS installed exe (pck embedded) is build B' } else { "E2E FAIL pck $NewPck (B $BPck, A $OldPck)" }
if (Test-Path (Join-Path $Install '.lastroute-backup-previous\KyttusLab.exe')) { 'E2E backup kept: ' + ((Get-ChildItem (Join-Path $Install '.lastroute-backup-previous')).Name -join ', ') } else { 'E2E FAIL no backup' }
$Relaunched = Get-Process -Name KyttusLab -ErrorAction SilentlyContinue
'E2E relaunched processes: ' + (($Relaunched | ForEach-Object { $_.Id }) -join ', ')
$Relaunched | ForEach-Object { Stop-Process -Id $_.Id -Force }
Stop-Process -Id $Backend.Id -Force
'E2E done'
