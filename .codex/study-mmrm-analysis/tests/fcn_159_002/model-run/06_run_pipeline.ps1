param(
    [string]$RscriptExe = 'D:\R-4.6.0\bin\x64\Rscript.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RscriptExe -PathType Leaf)) {
    throw "Rscript executable not found: $RscriptExe"
}

$outputDir = Join-Path $PSScriptRoot 'output'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile = Join-Path $outputDir "fcn_159_002_pipeline_$timestamp.log"
$scripts = @(
    '02_run_mmrm_by_tfl.R',
    '03_create_shell_table_csvs.R',
    '04_create_tfl_workbook.R'
)

"Pipeline started: $(Get-Date -Format o)" | Set-Content -LiteralPath $logFile -Encoding utf8
"Rscript: $RscriptExe" | Add-Content -LiteralPath $logFile -Encoding utf8

foreach ($script in $scripts) {
    $scriptPath = Join-Path $PSScriptRoot $script
    "`n[$(Get-Date -Format o)] START $script" | Add-Content -LiteralPath $logFile -Encoding utf8
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $RscriptExe $scriptPath 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $_.Exception.Message
        } else {
            $_.ToString()
        }
    }
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    $output | ForEach-Object {
        Write-Host $_
        $_ | Add-Content -LiteralPath $logFile -Encoding utf8
    }
    "[$(Get-Date -Format o)] END $script exit=$exitCode" | Add-Content -LiteralPath $logFile -Encoding utf8
    if ($exitCode -ne 0) {
        throw "Pipeline stopped because $script exited with code $exitCode. See $logFile"
    }
}

"Pipeline completed: $(Get-Date -Format o)" | Add-Content -LiteralPath $logFile -Encoding utf8
Write-Host "Pipeline completed. Log: $logFile"
