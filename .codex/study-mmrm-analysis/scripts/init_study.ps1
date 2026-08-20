param(
    [Parameter(Mandatory)]
    [string]$StudyDir,

    [ValidateSet('statistician_authored', 'ai_source_extraction')]
    [string]$Route = 'statistician_authored'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$studyRoot = [IO.Path]::GetFullPath($StudyDir)
$skillRoot = Split-Path -Parent $PSScriptRoot
$templateRoot = Join-Path $skillRoot 'assets\study-control'

# Verify all runtime R packages before doing anything else. Set MMRM_SKILL_NO_INSTALL=1 to prohibit installation.
$rscript = Get-Command Rscript.exe -ErrorAction SilentlyContinue
if (-not $rscript) { $rscript = Get-Command Rscript -ErrorAction SilentlyContinue }
if ($rscript) {
    $depScript = Join-Path $skillRoot 'scripts\check_dependencies.R'
    Write-Host 'Checking R package dependencies...'
    Push-Location $skillRoot
    try { & $rscript.Source $depScript } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw 'Dependency check failed. Install the required R packages and re-run init_study.ps1.' }
} else {
    Write-Warning 'Rscript not found on PATH; skipped automatic dependency check. Run scripts/check_dependencies.R with your R installation before generating anything.'
}

# Create the controlled intake, trace and code skeleton. The statistician supplies
# source materials under input/ before AI creates the sole pending review; output is
# still created lazily by the first real run.
$directories = @(
    'input',
    'backup-trace',
    'statistician-review',
    'analysis\r',
    'analysis\sas'
)
foreach ($relative in $directories) {
    New-Item -ItemType Directory -Path (Join-Path $studyRoot $relative) -Force | Out-Null
}

$studyControlDestination = Join-Path $studyRoot 'backup-trace\study-control.yaml'
if (-not (Test-Path -LiteralPath $studyControlDestination)) {
    Set-Content -LiteralPath $studyControlDestination -Value @("study_control_schema_version: '1.0'", "generation_route: $Route") -Encoding utf8
}

$manifestDestination = Join-Path $studyRoot 'backup-trace\input-manifest.csv'
if (-not (Test-Path -LiteralPath $manifestDestination)) {
    Copy-Item -LiteralPath (Join-Path $templateRoot 'input-manifest.csv') -Destination $manifestDestination
}

$briefingDestination = Join-Path $studyRoot 'input\statistician-analysis-input.md'
if (-not (Test-Path -LiteralPath $briefingDestination)) {
    Copy-Item -LiteralPath (Join-Path $templateRoot 'statistician-analysis-input-template.md') -Destination $briefingDestination
}

Write-Host "Initialized intake-first MMRM study for route: $Route"
Write-Host 'Place current-study source materials or complete input\statistician-analysis-input.md, then generate the pending review and analysis-plan template.'

Write-Host "Initialized minimal controlled MMRM study: $studyRoot"
Write-Host 'Output directories and tfl-output-manifest.csv will be created only by a validated execution/collector.'
