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

$assetContracts = @{
    'input-manifest.csv' = 'input_type,file_name,relative_path,version,file_size_bytes,modified_at,sha256,status,note'
    'tfl-output-manifest.csv' = 'study_id,analysis_id,tfl_id,tfl_type,title,scope_status,programming_language,binding_mode,program_file,program_sha256,execution_status,run_status,computational_risk,raw_output_file,final_tfl_file,diagnostic_file,run_record_file,plan_sha256,approval_payload_sha256,contract_sha256,expected_input_sha256,actual_input_sha256,collector_mode,collected_at_utc,note'
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
foreach ($required in @('read_statistical_review', 'statistical_review_trace_ids', 'statistical_review_candidate_table_columns', 'approval_payload', 'review_execution_content_sha256', 'statistical_review_set_metadata')) {
    Assert-Contains $specificationHelper $required "Statistical review helper missing: $required"
}

$standardHelpers = @{
    'standard_contract.R' = @('standard-mmrm-profile/v1', 'validate_standard_mmrm_contract', 'contrast_direction', 'standard_resolve_fail_fast', 'adapter_sha256')
    'standard_engine.R' = @('run_standard_mmrm_analysis', 'standard_fit_group_worker', 'failure_domain', 'blocked_environment', 'standard_artifact_identity')
    'standard_artifacts.R' = @('standard_validate_collector_manifest', 'standard_validate_model_rds', 'standard_output_manifest_schema', 'standard_collector_execution_status_values')
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
foreach ($required in @('final_covariance', 'failure_domain', 'diagnostic_report', 'computational_risk')) {
    Assert-Contains $standardArtifactsText $required "Standard collector summary contract missing: $required"
}
foreach ($scriptName in @('generate_standard_study.R', 'generate_case_summary.R')) {
    Assert-True (Test-Path -LiteralPath (Join-Path $skillRoot "scripts\$scriptName") -PathType Leaf) "Missing Standard Profile script: $scriptName"
}

$reviewFinalizationHelper = Join-Path $skillRRoot 'review_finalization.R'
$reviewFinalizationScript = Join-Path $skillRoot 'scripts\finalize_statistical_review.R'
Assert-True (Test-Path -LiteralPath $reviewFinalizationHelper -PathType Leaf) 'Missing review finalization helper.'
Assert-True (Test-Path -LiteralPath $reviewFinalizationScript -PathType Leaf) 'Missing review finalization script.'
& $RscriptExe --vanilla $reviewFinalizationScript '--self-check=true'
Assert-True ($LASTEXITCODE -eq 0) 'Review finalization temporary self-check failed.'
$intakeReviewText = Get-Content -Raw -LiteralPath (Join-Path $skillRRoot 'intake_review.R') -Encoding utf8
foreach ($required in @('intake_auto_register_inputs_if_needed', 'intake_detect_tfls_in_briefing')) {
    Assert-Contains $intakeReviewText $required "Intake review helper missing TFL discovery support: $required"
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
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $RscriptExe --vanilla $generateIntakeScript "--study-dir=$briefingProbe" '--replace-pending=true' 2>&1
    $ErrorActionPreference = $prevEap
    Assert-True ($LASTEXITCODE -eq 0) 'Briefing intake probe generator failed.'
    $probeReview = Join-Path $briefingProbe 'statistician-review\statistical-review.md'
    Assert-True (Test-Path -LiteralPath $probeReview -PathType Leaf) 'Briefing intake probe did not create statistical-review.md.'
    $probeReviewText = Get-Content -Raw -LiteralPath $probeReview -Encoding utf8
    foreach ($required in @('T14.2.1', 'AI Candidate Generation')) {
        Assert-Contains $probeReviewText $required "Briefing intake probe missing: $required"
    }
} finally {
    if (Test-Path -LiteralPath $briefingProbe) { Remove-Item -LiteralPath $briefingProbe -Recurse -Force }
}

$skillText = Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Encoding utf8
foreach ($required in @(
    'analysis-plan.yaml',
    'standard-mmrm-contract.yaml',
    'AI Candidate Generation',
    'finalize_statistical_review.R',
    'approve_and_generate_analysis.R',
    'run_all_mmrm.R',
    'output/tfl-output-manifest.csv'
)) {
    Assert-Contains $skillText $required "Skill contract missing: $required"
}

$studyPathsText = Get-Content -Raw -LiteralPath (Join-Path $skillRRoot 'study_paths.R') -Encoding utf8
foreach ($required in @('analysis_plan_file', 'r_analysis_dir', 'sas_analysis_dir', 'analysis_output_dir', 'analysis_output_paths', 'run_record', 'diagnostic_report', 'diagnostic_csv', 'output_manifest')) {
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

$figureHelper = Get-Content -Raw -LiteralPath (Join-Path $skillRRoot 'shell_figure.R') -Encoding utf8
Assert-Contains $figureHelper 'ggsave(png_path' 'Figure helper does not save PNG output.'
Assert-True (-not $figureHelper.Contains('pdf_path')) 'Figure helper still generates PDF output.'

$workflowText = Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'references\workflow.md') -Encoding utf8
foreach ($required in @('analysis-plan.candidate.yaml', 'ready_for_compilation', 'run-and-collect', 'collect-only', 'tfl-output-manifest.csv', 'sas-9.4m5-self-contained/v1')) {
    Assert-Contains $workflowText $required "Workflow contract missing: $required"
}
$rulesText = Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'references\rules.md') -Encoding utf8
foreach ($required in @('analysis-plan.yaml', 'binding_mode', 'CODE_GENERATION_ONLY', 'PROGRAM-INLINE-ADAPTER-UNSUPPORTED', 'tfl-output-manifest.csv', 'sas-9.4m5-self-contained/v1')) {
    Assert-Contains $rulesText $required "Rules contract missing: $required"
}
$outputDocsText = Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'references\output-docs.md') -Encoding utf8
foreach ($required in @('statistical-review.md', 'analysis-plan.yaml', 'standard-mmrm-contract.yaml', 'tfl-output-manifest.csv', 'run_record_file', 'run_all_mmrm.R', 'contract_sha256')) {
    Assert-Contains $outputDocsText $required "Output docs contract missing: $required"
}

# Generic gates and the non-FCN Standard Profile must pass independently of any FCN fixture.
foreach ($testName in @('check_standard_profile.R')) {
    $testPath = Join-Path $skillRRoot "tests\$testName"
    Assert-True (Test-Path -LiteralPath $testPath -PathType Leaf) "Missing general test: $testPath"
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $RscriptExe --vanilla $testPath 2>&1
    $ErrorActionPreference = $prevEap
    Assert-True ($LASTEXITCODE -eq 0) "General test failed: $testName"
}

Write-Host "Project validation passed: review->candidate->approved analysis-plan pipeline, typed Standard MMRM contract, full ADaM profile + variable-level specification projection, self-contained R/SAS program generation with strong artifact identity, two-file atomic review/plan publication, and Chinese human-readable output."
