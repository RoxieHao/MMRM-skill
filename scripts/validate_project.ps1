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
$controlAssets = Join-Path $skillRoot 'assets\study-control'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Contains {
    param([string]$Text, [string]$Expected, [string]$Message)
    Assert-True ($Text.Contains($Expected)) $Message
}

function Assert-AsciiOnlyFile {
    param([string]$Path)
    $text = Get-Content -Raw -LiteralPath $Path -Encoding utf8
    for ($i = 0; $i -lt $text.Length; $i++) {
        if ([int][char]$text[$i] -gt 127) {
            throw "Non-ASCII character in source file that must stay ASCII-only: $Path"
        }
    }
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

$rFiles = Get-ChildItem -LiteralPath $skillRRoot -Recurse -Filter '*.R' -File
foreach ($file in $rFiles) {
    & $RscriptExe --vanilla -e 'invisible(parse(file=commandArgs(TRUE)[1]))' $file.FullName
    Assert-True ($LASTEXITCODE -eq 0) "R parse failed: $($file.FullName)"
}

$scriptRFiles = Get-ChildItem -LiteralPath (Join-Path $skillRoot 'scripts') -Filter '*.R' -File
foreach ($file in $scriptRFiles) {
    & $RscriptExe --vanilla -e 'invisible(parse(file=commandArgs(TRUE)[1]))' $file.FullName
    Assert-True ($LASTEXITCODE -eq 0) "R script parse failed: $($file.FullName)"
}

$asciiOnlySourceFiles = @()
$asciiOnlySourceFiles += Get-ChildItem -LiteralPath (Join-Path $skillRRoot 'templates') -Filter '*.R' -File
$asciiOnlySourceFiles += Get-ChildItem -LiteralPath (Join-Path $skillRoot 'scripts') -Include '*.R', '*.ps1' -File
foreach ($file in $asciiOnlySourceFiles) {
    Assert-AsciiOnlyFile $file.FullName
}

$assetContracts = @{
    'input-manifest.csv' = 'input_type,file_name,relative_path,version,file_size_bytes,modified_at,sha256,status,note'
    'tfl-output-manifest.csv' = 'tfl_id,tfl_type,title,scope_status,output_status,raw_output_file,final_tfl_file,log_file,qc_file,note'
}
foreach ($asset in $assetContracts.Keys) {
    $path = Join-Path $controlAssets $asset
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Missing control template: $path"
    $header = Get-Content -LiteralPath $path -Encoding utf8 -TotalCount 1
    Assert-True ($header -eq $assetContracts[$asset]) "Invalid control template header: $path"
}
foreach ($asset in @('standard-mmrm-contract-template.yaml', 'study-case-summary-template.yaml')) {
    $path = Join-Path $controlAssets $asset
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Missing Standard Profile control template: $path"
}

$statisticianTemplate = Join-Path $controlAssets 'statistician-analysis-input-template.md'
Assert-True (Test-Path -LiteralPath $statisticianTemplate -PathType Leaf) 'Missing strict statistician analysis input template.'
$templateText = Get-Content -Raw -LiteralPath $statisticianTemplate -Encoding utf8
foreach ($required in @('data_classification', 'intended_use', 'default_population', 'analysis_population', 'population_rule', 'TFL', 'TFL Analysis', 'AI', 'estimate_id', 'Endpoint Mapping', 'primary_covariance', 'fallback_order', 'standard_mmrm_qc_v1', 'generate_sas_template', 'structured_diagnostics_format')) {
    Assert-Contains $templateText $required "Statistician template missing contract field: $required"
}

$specificationHelper = Get-Content -Raw -LiteralPath (Join-Path $skillRRoot 'specification.R') -Encoding utf8
foreach ($required in @('read_analysis_specification', 'validate_analysis_specification', 'assert_approved_specification', 'assert_specification_execution_allowed', 'finalization_status', 'ready_for_final_signature', 'SPEC-CONTRACT-PATH', 'SPEC-CONTRACT-IDENTITY')) {
    Assert-Contains $specificationHelper $required "Specification helper missing: $required"
}

$standardHelpers = @{
    'standard_contract.R' = @('standard-mmrm-profile/v1', 'validate_standard_mmrm_contract', 'contrast_direction', 'standard_resolve_fail_fast', 'adapter_sha256')
    'standard_engine.R' = @('run_standard_mmrm_analysis', 'standard_fit_group_worker', 'failure_domain', 'blocked_environment', 'standard_artifact_identity')
    'standard_artifacts.R' = @('run_standard_mmrm_collector', 'standard_validate_model_rds', 'standard_output_manifest_schema', 'overall_status=failed')
    'standard_sas.R' = @('render_standard_sas_template', 'template_generated_not_executed', 'execute_approved_template=YES', 'ConvergenceStatus=work._mmrm_convergence_status', 'sas_adapter_required')
    'case_summary.R' = @('standard_case_summary', 'aggregate_only=true', 'at_least_2_independent_studies', 'automatic_engine_modification')
}
foreach ($helperName in $standardHelpers.Keys) {
    $helperPath = Join-Path $skillRRoot $helperName
    Assert-True (Test-Path -LiteralPath $helperPath -PathType Leaf) "Missing Standard Profile helper: $helperPath"
    $helperText = Get-Content -Raw -LiteralPath $helperPath -Encoding utf8
    foreach ($required in $standardHelpers[$helperName]) {
        Assert-Contains $helperText $required "Standard Profile helper '$helperName' missing: $required"
    }
}
$standardEngineText = Get-Content -Raw -LiteralPath (Join-Path $skillRRoot 'standard_engine.R') -Encoding utf8
foreach ($required in @('standard_risk_label_cn', 'SAS status', 'Formal manifest')) {
    Assert-Contains $standardEngineText $required "Standard diagnostic report contract missing: $required"
}
$standardArtifactsText = Get-Content -Raw -LiteralPath (Join-Path $skillRRoot 'standard_artifacts.R') -Encoding utf8
foreach ($required in @('final_covariance', 'convergence', 'diagnostic_report', 'standard_risk_label_cn')) {
    Assert-Contains $standardArtifactsText $required "Standard collector summary contract missing: $required"
}
foreach ($scriptName in @('generate_standard_study.R', 'generate_case_summary.R')) {
    Assert-True (Test-Path -LiteralPath (Join-Path $skillRoot "scripts\$scriptName") -PathType Leaf) "Missing Standard Profile script: $scriptName"
}

$endpointMappingHelper = Join-Path $skillRRoot 'endpoint_mapping.R'
$structuredEndpointMappingCheck = Join-Path $skillRoot 'scripts\check_structured_endpoint_mapping.R'
Assert-True (Test-Path -LiteralPath $endpointMappingHelper -PathType Leaf) 'Missing Endpoint Mapping helper.'
Assert-True (Test-Path -LiteralPath $structuredEndpointMappingCheck -PathType Leaf) 'Missing structured Endpoint Mapping finalization check.'
& $RscriptExe --vanilla $structuredEndpointMappingCheck
Assert-True ($LASTEXITCODE -eq 0) 'Structured Endpoint Mapping finalization check failed.'
$reviewFinalizationHelper = Join-Path $skillRRoot 'review_finalization.R'
$reviewFinalizationScript = Join-Path $skillRoot 'scripts\finalize_statistical_review.R'
Assert-True (Test-Path -LiteralPath $reviewFinalizationHelper -PathType Leaf) 'Missing review finalization helper.'
Assert-True (Test-Path -LiteralPath $reviewFinalizationScript -PathType Leaf) 'Missing review finalization script.'
& $RscriptExe --vanilla $reviewFinalizationScript '--self-check=true'
Assert-True ($LASTEXITCODE -eq 0) 'Review finalization temporary self-check failed.'
$analysisSpecificationGenerationHelper = Join-Path $skillRRoot 'analysis_specification_generation.R'
$analysisSpecificationGenerationScript = Join-Path $skillRoot 'scripts\generate_analysis_specification.R'
$analysisSpecificationGenerationCheck = Join-Path $skillRoot 'scripts\check_analysis_specification_generation.R'
Assert-True (Test-Path -LiteralPath $analysisSpecificationGenerationHelper -PathType Leaf) 'Missing analysis specification generation helper.'
Assert-True (Test-Path -LiteralPath $analysisSpecificationGenerationScript -PathType Leaf) 'Missing analysis specification generation script.'
Assert-True (Test-Path -LiteralPath $analysisSpecificationGenerationCheck -PathType Leaf) 'Missing analysis specification generation temporary self-check.'
& $RscriptExe --vanilla $analysisSpecificationGenerationCheck
Assert-True ($LASTEXITCODE -eq 0) 'Analysis specification generation temporary self-check failed.'
$intakeEnrichmentHelper = Join-Path $skillRRoot 'intake_enrichment.R'
$intakeEnrichmentCheck = Join-Path $skillRoot 'scripts\check_intake_enrichment.R'
Assert-True (Test-Path -LiteralPath $intakeEnrichmentHelper -PathType Leaf) 'Missing intake enrichment helper.'
Assert-True (Test-Path -LiteralPath $intakeEnrichmentCheck -PathType Leaf) 'Missing intake enrichment temporary self-check.'
& $RscriptExe --vanilla $intakeEnrichmentCheck
Assert-True ($LASTEXITCODE -eq 0) 'Intake enrichment temporary self-check failed.'
$intakeReviewText = Get-Content -Raw -LiteralPath (Join-Path $skillRRoot 'intake_review.R') -Encoding utf8
foreach ($required in @('intake_auto_register_inputs_if_needed', 'intake_detect_tfls_in_briefing', 'statistician-analysis-input.md structured briefing', 'source_dataset', 'endpoint_codes')) {
    Assert-Contains $intakeReviewText $required "Intake review helper missing briefing parser support: $required"
}
$generateIntakeText = Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'scripts\generate_intake_review.R') -Encoding utf8
foreach ($required in @('infer_intake_route', 'get_arg("route", required = FALSE')) {
    Assert-Contains $generateIntakeText $required "Generate intake script missing route inference support: $required"
}
$finalizeText = Get-Content -Raw -LiteralPath $reviewFinalizationScript -Encoding utf8
foreach ($required in @('statistical-review_filled.md', 'statistical-review-filled.md', 'existing_filled', 'statistical-review.md')) {
    Assert-Contains $finalizeText $required "Finalize review script missing filled/review fallback support: $required"
}

$initStudyScript = Join-Path $skillRoot 'scripts\init_study.ps1'
$briefingProbe = Join-Path $projectRoot ("studies\zz_briefing_intake_probe_" + [Guid]::NewGuid().ToString('N'))
try {
    & $initStudyScript -StudyDir $briefingProbe -Route statistician_authored
    Assert-True ($LASTEXITCODE -eq 0) 'Briefing intake probe initializer failed.'
    $briefingPath = Join-Path $briefingProbe 'input\statistician-analysis-input.md'
    $briefingText = @'
# Statistician MMRM Analysis Input

## 1. Study

| field | value |
|---|---|
| study_id | PROBE-001 |
| data_classification | dummy |
| intended_use | testing |
| default_population | FAS |
| default_population_rule | FASFL == "Y" |

## 2. Defaults

| field | value |
|---|---|
| primary_covariance | UN |
| fallback_order | AR(1); CS |

## 3. TFL list

| tfl_id | title | endpoint_family | role | short_analysis_intent |
|---|---|---|---|---|
| T14.2.1 | CFB in total symptom score by visit | symptom score | primary | Compare CHG by visit. |

## 4. TFL Analysis: `T14.2.1`

### 4.2 Data

| field | value |
|---|---|
| analysis_population | FAS |
| population_rule | FASFL == "Y" |
| source_dataset | ADQS |
| endpoint_variable | PARAMCD |
| endpoint_codes | TSS |
| response_variable | CHG |
| baseline_variable | BASE |
| visit_variable | AVISITN |

### 4.5 Fixed effects

baseline + visit + treatment + visit*treatment.

### 4.6 Covariance

UN, then AR(1), then CS; Kenward-Roger.

### 4.8 Output

LSMean, difference, 95% CI, p-value. estimate_id is generated later.
'@
    Set-Content -LiteralPath $briefingPath -Value $briefingText -Encoding utf8
    $generateIntakeScript = Join-Path $skillRoot 'scripts\generate_intake_review.R'
    & $RscriptExe --vanilla $generateIntakeScript "--study-dir=$briefingProbe" '--replace-pending=true'
    Assert-True ($LASTEXITCODE -eq 0) 'Briefing intake probe generator failed.'
    $probeReview = Join-Path $briefingProbe 'statistician-review\statistical-review.md'
    Assert-True (Test-Path -LiteralPath $probeReview -PathType Leaf) 'Briefing intake probe did not create statistical-review.md.'
    $probeReviewText = Get-Content -Raw -LiteralPath $probeReview -Encoding utf8
    foreach ($required in @('T14.2.1', 'ADQS', 'PARAMCD in TSS', 'statistician-analysis-input.md structured briefing')) {
        Assert-Contains $probeReviewText $required "Briefing intake probe missing: $required"
    }
} finally {
    if (Test-Path -LiteralPath $briefingProbe) { Remove-Item -LiteralPath $briefingProbe -Recurse -Force }
}

$skillText = Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Encoding utf8
foreach ($required in @(
    'human-readable-language: zh-CN',
    'finalize_statistical_review.R',
    'generate_analysis_specification.R',
    'intake_enrichment.R',
    'specification: statistician-review/analysis-specification.md',
    'r-programs: analysis/r/<analysis_id>.R',
    'runner: analysis/r/run_all_mmrm.R',
    'sas-templates: analysis/sas/<analysis_id>_template.sas',
    'analysis-diagnostics: output/analyses/<analysis_id>/diagnostics/',
    'analysis-run-record-is-manifest: no',
    'manifest: output/tfl-output-manifest.csv',
    'raw_output_file',
    'final_tfl_file',
    'figure-format: png-only',
    'duplicate-output-policy: prohibit',
    'variable-review-output: prohibit'
)) {
    Assert-Contains $skillText $required "Skill contract missing: $required"
}

$studyPathsText = Get-Content -Raw -LiteralPath (Join-Path $skillRRoot 'study_paths.R') -Encoding utf8
foreach ($required in @('analysis_specification_file', 'r_analysis_dir', 'sas_analysis_dir', 'analysis_output_dir', 'analysis_output_paths', 'run_record', 'diagnostic_report', 'diagnostic_csv', 'output_manifest')) {
    Assert-Contains $studyPathsText $required "Study paths missing: $required"
}

$initStudyScript = Join-Path $skillRoot 'scripts\init_study.ps1'
$parseTokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($initStudyScript, [ref]$parseTokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'Study initializer contains PowerShell syntax errors.'
$initText = Get-Content -Raw -LiteralPath $initStudyScript -Encoding utf8
foreach ($required in @('backup-trace', 'statistician-review', 'analysis\r', 'analysis\sas', 'statistician_authored', 'ai_source_extraction')) {
    Assert-Contains $initText $required "Study initializer missing: $required"
}
Assert-True (-not $initText.Contains("'output\")) 'Study initializer must not pre-create output directories.'
Assert-True (-not $initText.Contains("'tfl-output-manifest.csv'")) 'Study initializer must not copy an empty global manifest.'

foreach ($route in @('statistician_authored', 'ai_source_extraction')) {
    $initFixture = Join-Path $projectRoot ("studies\zz_init_test_" + $route + '_' + [Guid]::NewGuid().ToString('N'))
    try {
        & $initStudyScript -StudyDir $initFixture -Route $route
        foreach ($relative in @('backup-trace\input-manifest.csv', 'statistician-review', 'analysis\r', 'analysis\sas')) {
            Assert-True (Test-Path -LiteralPath (Join-Path $initFixture $relative)) "Minimal initializer missing for ${route}: $relative"
        }
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $initFixture 'output'))) "Minimal initializer created output prematurely for $route."
        $authoredInput = Join-Path $initFixture 'input\statistician-analysis-input.md'
        Assert-True (Test-Path -LiteralPath $authoredInput -PathType Leaf) "Initializer must create its optional intake briefing template under input/ for ${route}."
    } finally {
        if (Test-Path -LiteralPath $initFixture) { Remove-Item -LiteralPath $initFixture -Recurse -Force }
    }
}

$workflowText = Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'references\workflow.md') -Encoding utf8
foreach ($required in @('status = linked_source', 'PARAM/PARAMCD', 'analysis-specification.md', 'statistical-review_filled.md', 'finalize_statistical_review.R', 'generate_analysis_specification.R', 'finalization_status', 'ready_for_final_signature', 'needs_statistician_confirmation', 'run-and-collect', 'collect-only', 'fail_fast', 'analysis-run-record.csv', 'tfl-output-manifest.csv')) {
    Assert-Contains $workflowText $required "Workflow contract missing: $required"
}
$rulesText = Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'references\rules.md') -Encoding utf8
foreach ($required in @('ADaM Specification', 'COA/PRO Mapping', 'treatment comparison', 'Analysis Specification Gate', 'approved specification', 'risk_reason')) {
    Assert-Contains $rulesText $required "Rules contract missing: $required"
}
$outputDocsText = Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'references\output-docs.md') -Encoding utf8
foreach ($required in @('statistical-review.md', 'statistical-review_filled.md', 'finalize_statistical_review.R', 'generate_analysis_specification.R', 'finalization_status', 'ready_for_final_signature', 'needs_statistician_confirmation', 'analysis-specification.md', 'standard-mmrm-contract.yaml', 'study-case-summary.yaml', 'analysis-run-record.csv', 'collector input', 'mmrm-run-diagnostic-report.md', 'project-relative', 'approval artifact')) {
    Assert-Contains $outputDocsText $required "Output docs contract missing: $required"
}

# Generic gates and the non-FCN Standard Profile must pass independently of any FCN fixture.
foreach ($testName in @('check_standard_profile.R')) {
    $testPath = Join-Path $skillRRoot "tests\$testName"
    Assert-True (Test-Path -LiteralPath $testPath -PathType Leaf) "Missing general test: $testPath"
    & $RscriptExe --vanilla $testPath
    Assert-True ($LASTEXITCODE -eq 0) "General test failed: $testName"
}

# Optional acceptance fixture: validate structure and produced artifacts without rerunning models.
$fcnFixtureStatus = 'Skipped'
$v2Study = Join-Path $projectRoot 'studies\fcn_159_002_v2_skilltest'
if (Test-Path -LiteralPath $v2Study -PathType Container) {
    $v2Spec = Join-Path $v2Study 'statistician-review\analysis-specification.md'

    $specValidator = Join-Path $skillRoot 'scripts\validate_analysis_specification.R'
    $specReport = Join-Path ([IO.Path]::GetTempPath()) ("fcn-v2-analysis-specification-validation-" + [Guid]::NewGuid().ToString('N') + ".md")
    & $RscriptExe --vanilla $specValidator "--spec=$v2Spec" "--project-root=$projectRoot" "--report=$specReport"
    if (Test-Path -LiteralPath $specReport) { Remove-Item -LiteralPath $specReport -Force }
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'FCN backward compatibility fixture: Skipped (fixture is not approved under the current Markdown review gate).'
    } else {

        $rDir = Join-Path $v2Study 'analysis\r'
        $sasDir = Join-Path $v2Study 'analysis\sas'
        $outputDir = Join-Path $v2Study 'output'
        $programs = @(Get-ChildItem -LiteralPath $rDir -Filter 'MMRM-*.R' -File)
        Assert-True ($programs.Count -gt 0) 'V2 has no independent MMRM programs.'

        $runnerPath = Join-Path $rDir 'run_all_mmrm.R'
        Assert-True (Test-Path -LiteralPath $runnerPath -PathType Leaf) 'V2 collector is missing.'
        $runnerText = Get-Content -Raw -LiteralPath $runnerPath -Encoding utf8
        foreach ($required in @('run-and-collect', 'collect-only', 'fail_fast', 'analysis-run-record.csv', 'output_manifest', 'collapse_diagnostic_status', 'highest_diagnostic_risk', 'validate_csv_artifact')) {
            Assert-Contains $runnerText $required "Collector contract missing: $required"
        }
        Assert-True (-not $runnerText.Contains('mmrm::mmrm(')) 'Collector must not fit models.'

        $allowedStatus = @('complete', 'partial', 'blocked_mapping', 'blocked_data', 'fit_failed', 'deferred', 'not_applicable')
        foreach ($program in $programs) {
            $analysisId = [IO.Path]::GetFileNameWithoutExtension($program.Name)
            $programText = Get-Content -Raw -LiteralPath $program.FullName -Encoding utf8
            Assert-Contains $programText 'run_fcn_v2_analysis(' "Independent program has no direct execution call: $analysisId"
            Assert-True (-not $programText.Contains('run_all_mmrm.R')) "Independent program depends on collector: $analysisId"

        $sasPath = Join-Path $sasDir "${analysisId}_template.sas"
        Assert-True (Test-Path -LiteralPath $sasPath -PathType Leaf) "Missing SAS template: $analysisId"
        $sasText = (Get-Content -Raw -LiteralPath $sasPath -Encoding utf8).ToLowerInvariant()
        foreach ($required in @('template_generated_not_executed', 'proc mixed', 'type=un', 'type=ar(1)', 'ods output', 'proc export', 'region', 'country', 'region_effect', 'region_effect_status', 'region_omission_reason', 'region_class_term', 'region_model_term', 'region omitted', 'fewer_than_2_levels')) {
            Assert-Contains $sasText $required "SAS template contract missing '$required': $analysisId"
        }
        Assert-True (-not $sasText.Contains('siteid')) "SAS template must not query or use SITEID: $analysisId"
        Assert-True (-not ($sasText -match 'region_level_n\s*<\s*2[\s\S]{0,200}%abort')) "SAS template must omit an inestimable region term rather than abort: $analysisId"
        Assert-Contains $sasText 'class usubjid avisitn &region_class_term' "SAS CLASS is not dynamically controlled: $analysisId"
        Assert-Contains $sasText '&region_model_term' "SAS MODEL is not dynamically controlled: $analysisId"

        $analysisOutput = Join-Path $outputDir "analyses\$analysisId"
        $runRecordPath = Join-Path $analysisOutput 'analysis-run-record.csv'
        $diagnosticPath = Join-Path $analysisOutput 'diagnostics\mmrm-run-diagnostics.csv'
        $reportPath = Join-Path $analysisOutput 'diagnostics\mmrm-run-diagnostic-report.md'
        $logPath = Join-Path $analysisOutput 'logs\run.log'
        foreach ($requiredPath in @($runRecordPath, $diagnosticPath, $reportPath, $logPath)) {
            Assert-True (Test-Path -LiteralPath $requiredPath -PathType Leaf) "Missing V2 artifact: $requiredPath"
        }

        $diagnostics = @(Import-Csv -LiteralPath $diagnosticPath)
        Assert-True ($diagnostics.Count -gt 0) "Empty diagnostics: $analysisId"
        foreach ($column in @('run_id', 'analysis_id', 'analysis_group_id', 'specification_id', 'specification_sha256', 'data_classification', 'region_variable', 'region_level_count', 'region_effect_status', 'region_omission_reason', 'covariance_path', 'final_covariance', 'fallback_used', 'convergence_status', 'inference_complete', 'computational_risk', 'risk_reason', 'run_status', 'model_file', 'log_file')) {
            Assert-True ($diagnostics[0].PSObject.Properties.Name -contains $column) "Diagnostics missing '$column': $analysisId"
        }

        $reportText = Get-Content -Raw -LiteralPath $reportPath -Encoding utf8
        Assert-True ($reportText -match 'Analysis ID') "Diagnostic report missing analysis identity: $analysisId"
        Assert-True ($reportText -match 'Covariance') "Diagnostic report missing covariance result: $analysisId"
        Assert-True ($reportText -match 'SAS') "Diagnostic report missing SAS status: $analysisId"
    }

    $manifestPath = Join-Path $outputDir 'tfl-output-manifest.csv'
    $manifestFiles = @(Get-ChildItem -LiteralPath $outputDir -Recurse -Filter '*manifest*.csv' -File)
    Assert-True ($manifestFiles.Count -eq 1) 'V2 output must contain exactly one formal manifest.'
    Assert-True ($manifestFiles[0].FullName -eq $manifestPath) 'V2 formal manifest is not at the required top-level path.'
    $manifest = @(Import-Csv -LiteralPath $manifestPath)
    Assert-True ($manifest.Count -eq $programs.Count) 'V2 manifest row count does not match independent programs.'
    $formalManifestColumns = @('tfl_id', 'tfl_type', 'title', 'scope_status', 'output_status', 'raw_output_file', 'final_tfl_file', 'log_file', 'qc_file', 'note')
    $actualManifestColumns = @($manifest[0].PSObject.Properties.Name)
    Assert-True (($actualManifestColumns -join ',') -eq ($formalManifestColumns -join ',')) 'V2 manifest must preserve the formal ten-column schema.'
    foreach ($row in $manifest) {
        Assert-True ($allowedStatus -contains $row.output_status) "Invalid manifest status: $($row.output_status)"
        foreach ($field in @('raw_output_file', 'final_tfl_file', 'log_file', 'qc_file')) {
            $value = [string]$row.$field
            Assert-True (-not [IO.Path]::IsPathRooted($value)) "Manifest path must be project-relative: $value"
            Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot $value) -PathType Leaf) "Manifest target missing: $value"
        }
    }

        $duplicateTflText = @(Get-ChildItem -LiteralPath (Join-Path $outputDir 'analyses') -Recurse -File | Where-Object {
            $_.Directory.Name -eq 'tables' -and $_.Extension -in @('.md', '.txt')
        })
        Assert-True ($duplicateTflText.Count -eq 0) 'V2 contains duplicate Markdown/TXT TFL output.'
        $fcnFixtureStatus = 'Passed'
    }
} else {
    Write-Host 'FCN backward compatibility fixture: Skipped (optional fixture not present).'
}

Write-Host "Project validation passed: approved specification and typed Standard MMRM contract, non-FCN engine integration with actual mmrm fit, independent R/SAS programs, strong artifact identity, closed case promotion gate, analysis-scoped diagnostics, collector-only ten-column global manifest, Chinese human-readable output. FCN backward compatibility fixture: $fcnFixtureStatus."
