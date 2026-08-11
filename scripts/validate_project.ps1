param(
    [string]$PythonExe = 'C:\Users\haoruoxi\AppData\Local\Python\pythoncore-3.14-64\python.exe',
    [string]$RscriptExe = 'D:\R-4.6.0\bin\x64\Rscript.exe',
    [string]$SkillValidator = 'C:\Users\haoruoxi\.codex\skills\.system\skill-creator\scripts\quick_validate.py'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$skillRoot = Join-Path $projectRoot '.codex\study-mmrm-analysis'
$skillRRoot = Join-Path $skillRoot 'R'
$testsRoot = Join-Path $skillRoot 'tests'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Assert-True (Test-Path -LiteralPath $PythonExe -PathType Leaf) "Python not found: $PythonExe"
Assert-True (Test-Path -LiteralPath $RscriptExe -PathType Leaf) "Rscript not found: $RscriptExe"
Assert-True (Test-Path -LiteralPath $SkillValidator -PathType Leaf) "Skill validator not found: $SkillValidator"

$previousPythonUtf8 = $env:PYTHONUTF8
try {
    $env:PYTHONUTF8 = '1'
    & $PythonExe $SkillValidator $skillRoot
    Assert-True ($LASTEXITCODE -eq 0) 'Skill validation failed.'
} finally {
    $env:PYTHONUTF8 = $previousPythonUtf8
}

$rFiles = @()
if (Test-Path -LiteralPath $skillRRoot -PathType Container) {
    $rFiles += Get-ChildItem -LiteralPath $skillRRoot -Recurse -Filter '*.R' -File
}
$rFiles += Get-ChildItem -LiteralPath $testsRoot -Recurse -Filter '*.R' -File
foreach ($file in $rFiles) {
    & $RscriptExe -e 'invisible(parse(file=commandArgs(TRUE)[1]))' $file.FullName
    Assert-True ($LASTEXITCODE -eq 0) "R parse failed: $($file.FullName)"
}

$fixtureContracts = @{
    'fcn_159_002' = @('inputs.md', 'expected-route.md', 'analysis-content.md', 'scan-summary.md', 'adam-parameter-mapping.md', 'code-plan-after-scan.md', 'run-notes.md', 'results.md')
    'triferic_phase3' = @('inputs.md', 'expected-route.md', 'analysis-content.md', 'scan-summary.md', 'adam-parameter-mapping.md', 'code-plan-after-scan.md', 'run-notes.md', 'results.md')
    'cross_study' = @('inputs.md', 'expected-route.md', 'analysis-content.md', 'scan-summary.md', 'run-notes.md', 'results.md')
}

foreach ($fixture in $fixtureContracts.Keys) {
    foreach ($relativePath in $fixtureContracts[$fixture]) {
        $path = Join-Path (Join-Path $testsRoot $fixture) $relativePath
        Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Missing fixture file: $path"
    }
}

$fcnTableDir = Join-Path $testsRoot 'fcn_159_002\model-run\output\tables'
$tableFiles = Get-ChildItem -LiteralPath $fcnTableDir -Filter 'table_*_mmrm.csv' -File
foreach ($file in $tableFiles) {
    $rows = Import-Csv -LiteralPath $file.FullName -Encoding utf8
    $incompleteFits = @($rows | Where-Object {
        $_.model_status -eq 'fit' -and
        $_.row_type -ne 'Observed AVAL' -and
        ([string]::IsNullOrWhiteSpace($_.mmrm_adjusted_mean_95ci) -or
         [string]::IsNullOrWhiteSpace($_.mmrm_p_value_formatted))
    })
    Assert-True ($incompleteFits.Count -eq 0) "Complete-fit contract failed in $($file.FullName): $($incompleteFits.Count) incomplete rows"
}

$manifestPath = Join-Path $fcnTableDir 'table_output_manifest.csv'
$manifest = Import-Csv -LiteralPath $manifestPath -Encoding utf8
$absolutePaths = @($manifest | Where-Object { $_.output_file -match '^[A-Za-z]:[\\/]' })
Assert-True ($absolutePaths.Count -eq 0) 'FCN manifest contains absolute output paths.'

Write-Host "Project validation passed: skill, $($rFiles.Count) R scripts, fixture contracts, model-output completeness, and manifest portability."
