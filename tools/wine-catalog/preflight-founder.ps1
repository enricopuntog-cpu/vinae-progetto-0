# Promozione canonica - preflight del founder (F-06), runbook sez. 4.3 e sez. 5.1.
# Sola lettura. Nessuna password passa da questo script: psql la chiede al proprio prompt.
#
#   Solo controlli degli strumenti (nessuna connessione):
#     powershell -ExecutionPolicy Bypass -File tools\wine-catalog\preflight-founder.ps1 -CaCert C:\vinea\prod-ca-2021.crt -SoloControlli
#   Prova del percorso amministrativo (circa 4 minuti, sola lettura):
#     powershell -ExecutionPolicy Bypass -File tools\wine-catalog\preflight-founder.ps1 -CaCert C:\vinea\prod-ca-2021.crt
#
# Esito: righe OK/MANCA, poi (senza -SoloControlli) il verdetto della prova e il file di log da riportare.
param(
  [Parameter(Mandatory = $true)][string]$CaCert,
  [switch]$SoloControlli,
  [string]$ProjectRef = 'pijnmcllmfgjmgsvtcej',
  [string]$PoolerHost = 'aws-0-eu-west-1.pooler.supabase.com'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$mancanti = 0

function Write-Esito([bool]$ok, [string]$voce, [string]$dettaglio) {
  if ($ok) { Write-Host ("OK     {0} {1}" -f $voce, $dettaglio) } else { Write-Host ("MANCA  {0} {1}" -f $voce, $dettaglio); $script:mancanti++ }
}

# 1. psql (client 16 o successivo; il server e PostgreSQL 17)
$psql = $null
$cmd = Get-Command psql -ErrorAction SilentlyContinue
if ($cmd) { $psql = $cmd.Source }
if (-not $psql) {
  $trovato = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
  if ($trovato) { $psql = $trovato.FullName }
}
if ($psql) {
  $versione = (& $psql --version) -join ' '
  $major = 0
  if ($versione -match '(\d+)\.\d+') { $major = [int]$Matches[1] }
  Write-Esito ($major -ge 16) 'psql' ("$psql ($versione)")
} else {
  Write-Esito $false 'psql' '(installare i PostgreSQL Command Line Tools, runbook sez. 4.3)'
}

# 2. certificato CA del progetto (pannello Supabase -> Database -> SSL)
$caOk = $false
if (Test-Path -LiteralPath $CaCert -PathType Leaf) {
  $caOk = ((Get-Content -LiteralPath $CaCert -Raw) -match '-----BEGIN CERTIFICATE-----')
}
Write-Esito $caOk 'certificato CA' $CaCert

# 3. strumenti della verifica dell'archivio (F-08 b): bash, age, python 3, client S3
$bash = Get-Command bash -ErrorAction SilentlyContinue
Write-Esito ($null -ne $bash) 'bash (Git Bash)' ''
$age = Get-Command age -ErrorAction SilentlyContinue
if (-not $age) { $age = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\FiloSottile.age*\age\age.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 }
Write-Esito ($null -ne $age) 'age' ''
$python = $env:PYTHON_BIN
$pythonOk = $false
if (-not $python) {
  foreach ($nome in @('python3', 'python')) {
    $c = Get-Command $nome -ErrorAction SilentlyContinue
    if ($c -and $c.Source -notmatch 'WindowsApps') { $python = $c.Source; break }
  }
}
if ($python) {
  try { $pythonOk = ((& $python --version 2>&1) -join ' ') -match 'Python 3\.' } catch { $pythonOk = $false }
}
Write-Esito $pythonOk 'python 3 (o PYTHON_BIN)' "$python"
$aws = Get-Command aws -ErrorAction SilentlyContinue
Write-Esito ($null -ne $aws) 'aws (download S3 da B2)' ''

# 4. file del repository
foreach ($f in @('tools\wine-catalog\promozione\verifica_percorso.sql', '.github\scripts\offsite-restore-verify.sh')) {
  Write-Esito (Test-Path -LiteralPath (Join-Path $repo $f)) $f ''
}

if ($SoloControlli) {
  Write-Host ("Controlli conclusi: {0} voci mancanti." -f $mancanti)
  if ($mancanti -gt 0) { exit 1 } else { exit 0 }
}
if (-not $psql -or -not $caOk) {
  Write-Host 'STOP: servono psql e il certificato CA per la prova del percorso.'
  exit 1
}

# 5. prova del percorso: STESSO comando dei lotti (Session Pooler 5432, verify-full, keepalive, -X, ON_ERROR_STOP, -f)
$ca = (Resolve-Path -LiteralPath $CaCert).Path -replace '\\', '/'
$conn = "host=$PoolerHost port=5432 dbname=postgres user=postgres.$ProjectRef sslmode=verify-full sslrootcert=$ca keepalives=1 keepalives_idle=30 keepalives_interval=10 keepalives_count=6 application_name=vinea-verifica-percorso"
$file = Join-Path $repo 'tools\wine-catalog\promozione\verifica_percorso.sql'
$log = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ("vinea-verifica-percorso-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$env:PGCLIENTENCODING = 'UTF8'
# stderr di psql nel log senza interrompere lo script (PowerShell 5.1 lo tratterebbe come errore)
$ErrorActionPreference = 'Continue'
Write-Host 'psql chiede ora la password del proprietario del database (non viene salvata ne mostrata).'
$inizio = Get-Date
& $psql $conn -X -v ON_ERROR_STOP=1 -f $file 2>&1 | Tee-Object -FilePath $log
$codice = $LASTEXITCODE
$secondi = [int]((Get-Date) - $inizio).TotalSeconds
$testo = Get-Content -LiteralPath $log -Raw

$pids = @([regex]::Matches($testo, '"pid":\s*(\d+)') | ForEach-Object { $_.Groups[1].Value })
$ssl = $testo -match '(?i)\bssl\b'
$utente = $testo -match '"utente":\s*"postgres"'
$stessoPid = ($pids.Count -eq 2 -and $pids[0] -eq $pids[1])
$commit = $testo -match '(?m)^COMMIT\s*$'
Write-Host ''
Write-Esito ($codice -eq 0) 'uscita di psql' "($codice)"
Write-Esito $ssl 'SSL dichiarato da \conninfo' ''
Write-Esito $utente 'utente proprietario (postgres)' ''
Write-Esito $stessoPid 'stesso pid inizio e fine' ("(" + ($pids -join ', ') + ")")
Write-Esito ($secondi -ge 235) 'durata' ("$secondi s")
Write-Esito $commit 'ultima istruzione COMMIT' ''
if ($codice -eq 0 -and $ssl -and $utente -and $stessoPid -and $secondi -ge 235 -and $commit) {
  Write-Host "F-06 SUPERATA. Riportare questo file (nessun segreto dentro): $log"
  exit 0
}
Write-Host "F-06 NON SUPERATA. Riportare il file: $log"
exit 1
