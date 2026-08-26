/* =============================================================================
   第 1 部分：程序说明与用户配置
   ========================================================================== */
/* 本程序由已批准的 analysis plan 与机械编译的 runtime contract 确定性生成，逐 TFL 自包含。 */
/* 阅读本文件即可理解该 TFL 的数据处理、MMRM 拟合、统计推断与输出，无需阅读任何项目共享代码。 */
/* 本程序不使用任何外部宏库、站点宏、操作系统命令或转换脚本。 */
/* 研究：SYNTHETIC；分析：MMRM-08；TFL：T14-08 */
/* 标题：Synthetic self-contained analysis "quoted" 'apostrophe' \backslash ;#% 中文 */
/* profile 版本：standard-mmrm-profile/v1 */

/* 批准身份（用于审计追溯；本程序独立运行时不读取 review/plan/contract 文件）： */
/* PROGRAM-MARKER:IDENTITY:STUDY:SYNTHETIC */
/* PROGRAM-MARKER:IDENTITY:ANALYSIS:MMRM-08 */
/* PROGRAM-MARKER:IDENTITY:TFL:T14-08 */
/* PROGRAM-MARKER:IDENTITY:PROFILE:standard-mmrm-profile/v1 */
/* PROGRAM-MARKER:IDENTITY:PLAN_SHA256:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB */
/* PROGRAM-MARKER:IDENTITY:APPROVAL_SHA256:DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD */
/* PROGRAM-MARKER:IDENTITY:CONTRACT_SHA256:FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF */

/* 数据绑定模式：linked（已登记实体 ADaM 文件与 SHA-256） */
/* PROGRAM-MARKER:BINDING:linked */
/* 批准的数据文件名：scores.csv；格式：csv */

/* 批准的 SAS execution profile：sas-9.4m5-self-contained/v1 */
/*   最低 SAS 版本：SAS 9.4M5；会话编码：UTF-8 */
/*   需要的能力：FCMP=true；位运算=true；自包含 SHA-256=true */
/*   CSV writer 要求：UTF-8 BOM data-step writer */
/*   生成流水线不执行 SAS：本文件是代码交付物，请在上述目标环境中由统计师运行； */
/*   目标环境缺少 FCMP/位运算/SHA-256 能力时生成即阻断，不降低 SHA-256 安全要求。 */

/* 本 TFL 的输出文件名逐字来自 contract，程序运行时不自行推断或拼接： */
/* PROGRAM-MARKER:OUTPUT:r_raw_file:T14-08_r_raw.csv */
/* PROGRAM-MARKER:OUTPUT:r_final_file:T14-08_r_final.csv */
/* PROGRAM-MARKER:OUTPUT:r_diagnostic_file:T14-08_r_diagnostic.csv */
/* PROGRAM-MARKER:OUTPUT:r_run_record_file:T14-08_r_run_record.csv */
/* PROGRAM-MARKER:OUTPUT:sas_raw_file:T14-08_sas_raw.csv */
/* PROGRAM-MARKER:OUTPUT:sas_final_file:T14-08_sas_final.csv */
/* PROGRAM-MARKER:OUTPUT:sas_diagnostic_file:T14-08_sas_diagnostic.csv */
/* PROGRAM-MARKER:OUTPUT:sas_run_record_file:T14-08_sas_run_record.csv */

options validvarname=v7 nofmterr;

/* =========================== 用户配置区（开始） =========================== */
/* 以下三个宏变量是本程序中唯一允许人工修改的内容。 */
/* EXECUTE_APPROVED_PROGRAM：核对批准身份与输入数据后显式改为 YES 才允许执行； */
/* INPUT_DIR：存放批准数据文件的本机只读输入目录； */
/* OUTPUT_DIR：存放本 TFL 结果、诊断与运行记录的本机输出目录。 */
/* 路径请使用正斜杠，且不要加引号或结尾分隔符。 */
%let EXECUTE_APPROVED_PROGRAM=NO;
%let INPUT_DIR=;
%let OUTPUT_DIR=;
/* =========================== 用户配置区（结束） =========================== */

/* 除上面的用户配置区之外，请不要修改本程序的任何内容。 */
/* 任何统计语义变更（数据集、变量映射、派生、筛选、分组、模型、估计量、输出） */
/* 都必须回到 analysis plan 修改并重新批准，然后重新生成本程序。 */

/* 以下常量由生成器写入，属于批准语义，不是用户配置项。 */
/* CODE_GENERATION_ONLY 是生成常量：planned 程序永久为 YES，改动它不能获得执行许可。 */
%let CODE_GENERATION_ONLY=NO;
%let DATA_AVAILABLE=YES;
%let STUDY_ID=SYNTHETIC;
%let ANALYSIS_ID=MMRM-08;
%let TFL_ID=T14-08;
%let PROFILE_VERSION=standard-mmrm-profile/v1;
%let PLAN_SHA256=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB;
%let APPROVAL_PAYLOAD_SHA256=DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD;
%let CONTRACT_SHA256=FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
%let DATASET_BINDING_MODE=linked;
%let DATASET_FILE=scores.csv;
%let DATASET_FORMAT=csv;
%let EXPECTED_INPUT_SHA256=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
%let SAS_RAW_FILE=T14-08_sas_raw.csv;
%let SAS_FINAL_FILE=T14-08_sas_final.csv;
%let SAS_DIAGNOSTIC_FILE=T14-08_sas_diagnostic.csv;
%let SAS_RUN_RECORD_FILE=T14-08_sas_run_record.csv;
%let SAS_EXECUTION_PROFILE=sas-9.4m5-self-contained/v1;
%let SESSION_ENCODING_REQUIRED=UTF-8;

/* 批准的分组与协方差顺序（供第 4-5 部分的确定性循环使用）。 */
%let GROUP_IDS=TOTAL SUBSCALE;
%let GROUP_COUNT=2;
%let COVARIANCE_KEYS=TOEP CS AR1;
%let COVARIANCE_TYPES=TOEP CS AR(1);
%let COVARIANCE_COUNT=3;
%let APPROVED_TREATMENT_LEVEL_COUNT=2;
%let DERIVATION_COUNT=1;
%let PRIMARY_ESTIMAND=treatment_visit_lsmean;

/* 运行期状态变量的初值。运行记录的时间戳只在运行时产生，不进入确定性正文。 */
%let PROGRAM_ACTIVE=0;
%let RUN_STATUS=not_started;
%let ACTUAL_INPUT_SHA256=;
%let INPUT_PATH=;
%let INPUT_ROWS=0;
%let POPULATION_FILTERED_ROWS=0;
%let ANALYSIS_ROWS=0;
%let MISSING_REQUIRED_ROWS=0;
%let SUBJECT_COUNT=0;
%let VISIT_LEVEL_COUNT=0;
%let TREATMENT_LEVEL_COUNT=0;
%let QC_GROUP_OVERLAP=0;
%let QC_ENDPOINT_UNAPPROVED=0;
%let QC_DUPLICATE_KEY=0;
%let QC_BASELINE_INCONSISTENT=0;
%let QC_TREATMENT_LEVEL=0;
%let QC_VISIT_LABEL=0;
%let QC_ERROR_TOTAL=0;
%let MMRM_FIT_SUCCESS=0;
%let INFERENCE_COMPLETE=0;
%let COVARIANCE_PATH=;
%let SELECTED_COVARIANCE=;
%let RAW_OUTPUT_WRITTEN=0;
%let FINAL_OUTPUT_WRITTEN=0;
/* E8601DZ 格式把会话时间写成带 Z 后缀的 UTC 时间戳，与 R 程序的运行记录保持同一语义。 */
%let RUN_STARTED_UTC=%sysfunc(putn(%sysfunc(datetime()),E8601DZ20.));

/* =============================================================================
   第 2 部分：运行环境与安全检查
   ========================================================================== */
/* 本部分按固定顺序执行运行环境与安全检查： */
/*   1 code-generation-only gate；2 执行许可与会话能力；3 输入/输出配置；4 文件存在；5 linked SHA-256。 */
/* planned 的 code-generation-only 是合法状态：打印中文说明后走正常结束路径，不使用中止语句。 */
/* linked 的执行许可、配置、文件或 SHA-256 安全失败才中止执行。 */

/* linked 程序必须在读取数据之前完成文件存在与 SHA-256 两道安全 gate。 */
/* PROGRAM-MARKER:GATE:LINKED_FILE */
/* PROGRAM-MARKER:GATE:LINKED_SHA256 */

/* 自包含 SHA-256：用 PROC FCMP 位运算函数加 DATA step 二进制分块读取实现。 */
/* 不依赖操作系统命令、外部脚本语言、第三方可执行文件或站点宏；不把整个数据文件读成字符变量。 */
%macro verify_file_sha256(path=, expected=);
  %global ACTUAL_INPUT_SHA256;
  proc fcmp outlib=work.scfuncs.sha256;
    function sha256_rotr(x, n);
      return(bor(brshift(band(x, 0FFFFFFFFx), n), band(blshift(band(x, 0FFFFFFFFx), 32 - n), 0FFFFFFFFx)));
    endsub;
    function sha256_shr(x, n);
      return(brshift(band(x, 0FFFFFFFFx), n));
    endsub;
    function sha256_ch(x, y, z);
      return(bxor(band(x, y), band(band(bnot(x), 0FFFFFFFFx), z)));
    endsub;
    function sha256_maj(x, y, z);
      return(bxor(bxor(band(x, y), band(x, z)), band(y, z)));
    endsub;
    function sha256_bsig0(x);
      return(bxor(bxor(sha256_rotr(x, 2), sha256_rotr(x, 13)), sha256_rotr(x, 22)));
    endsub;
    function sha256_bsig1(x);
      return(bxor(bxor(sha256_rotr(x, 6), sha256_rotr(x, 11)), sha256_rotr(x, 25)));
    endsub;
    function sha256_ssig0(x);
      return(bxor(bxor(sha256_rotr(x, 7), sha256_rotr(x, 18)), sha256_shr(x, 3)));
    endsub;
    function sha256_ssig1(x);
      return(bxor(bxor(sha256_rotr(x, 17), sha256_rotr(x, 19)), sha256_shr(x, 10)));
    endsub;
  quit;
  options cmplib=work.scfuncs;
  filename _shafile "&path" recfm=n encoding='any' lrecl=64;
  data _null_;
    length _chunk $64 _actual $64 _expected $64 _hex $8;
    array _h{8} _temporary_ (06A09E667x, 0BB67AE85x, 03C6EF372x, 0A54FF53Ax,
                             0510E527Fx, 09B05688Cx, 01F83D9ABx, 05BE0CD19x);
    array _k{64} _temporary_ (
                          0428A2F98x, 071374491x, 0B5C0FBCFx, 0E9B5DBA5x, 03956C25Bx, 059F111F1x, 0923F82A4x, 0AB1C5ED5x,
                          0D807AA98x, 012835B01x, 0243185BEx, 0550C7DC3x, 072BE5D74x, 080DEB1FEx, 09BDC06A7x, 0C19BF174x,
                          0E49B69C1x, 0EFBE4786x, 00FC19DC6x, 0240CA1CCx, 02DE92C6Fx, 04A7484AAx, 05CB0A9DCx, 076F988DAx,
                          0983E5152x, 0A831C66Dx, 0B00327C8x, 0BF597FC7x, 0C6E00BF3x, 0D5A79147x, 006CA6351x, 014292967x,
                          027B70A85x, 02E1B2138x, 04D2C6DFCx, 053380D13x, 0650A7354x, 0766A0ABBx, 081C2C92Ex, 092722C85x,
                          0A2BFE8A1x, 0A81A664Bx, 0C24B8B70x, 0C76C51A3x, 0D192E819x, 0D6990624x, 0F40E3585x, 0106AA070x,
                          019A4C116x, 01E376C08x, 02748774Cx, 034B0BCB5x, 0391C0CB3x, 04ED8AA4Ax, 05B9CCA4Fx, 0682E6FF3x,
                          0748F82EEx, 078A5636Fx, 084C87814x, 08CC70208x, 090BEFFFAx, 0A4506CEBx, 0BEF9A3F7x, 0C67178F2x
                             );
    array _w{0:63} _temporary_;
    array _mb{0:63} _temporary_;
    _fid = fopen('_shafile');
    if _fid = 0 then do;
      put 'ERROR: 无法打开待校验的输入文件，SHA-256 校验无法完成。';
      call symputx('ACTUAL_INPUT_SHA256', 'OPEN_FAILED', 'G');
      stop;
    end;
    _size = input(finfo(_fid, 'File Size (bytes)'), best32.);
    _rc = fclose(_fid);
    if missing(_size) then do;
      put 'ERROR: 无法读取待校验文件的字节数，SHA-256 校验无法完成。';
      call symputx('ACTUAL_INPUT_SHA256', 'SIZE_UNKNOWN', 'G');
      stop;
    end;
    _full = floor(_size / 64);
    _rem = _size - 64 * _full;
    _bits_hi = floor(_size * 8 / 4294967296);
    _bits_lo = mod(_size * 8, 4294967296);
    infile _shafile recfm=n lrecl=64 encoding='any';
/*   按 64 字节分块读取，逐块压缩；文件内容不会被整体读入内存。 */
    do _blk = 1 to _full;
      input _chunk $char64.;
      do _i = 1 to 64;
        _mb{_i - 1} = rank(substr(_chunk, _i, 1));
      end;
      link compress_block;
    end;
    if _rem gt 0 then input _chunk $varying64. _rem;
    do _i = 0 to 63;
      _mb{_i} = 0;
    end;
    do _i = 1 to _rem;
      _mb{_i - 1} = rank(substr(_chunk, _i, 1));
    end;
    _mb{_rem} = 128;
    if _rem + 1 le 56 then do;
      link append_length;
      link compress_block;
    end;
    else do;
      link compress_block;
      do _i = 0 to 63;
        _mb{_i} = 0;
      end;
      link append_length;
      link compress_block;
    end;
    _actual = '';
    do _i = 1 to 8;
      _hex = put(_h{_i}, hex8.);
      _actual = cats(_actual, _hex);
    end;
    _actual = upcase(_actual);
    _expected = upcase("&expected");
    call symputx('ACTUAL_INPUT_SHA256', _actual, 'G');
    if _actual ne _expected then put 'ERROR: 输入文件 SHA-256 与批准值不一致。expected=' _expected ' actual=' _actual;
    stop;
   append_length:
    _mb{56} = band(brshift(_bits_hi, 24), 255);
    _mb{57} = band(brshift(_bits_hi, 16), 255);
    _mb{58} = band(brshift(_bits_hi, 8), 255);
    _mb{59} = band(_bits_hi, 255);
    _mb{60} = band(brshift(_bits_lo, 24), 255);
    _mb{61} = band(brshift(_bits_lo, 16), 255);
    _mb{62} = band(brshift(_bits_lo, 8), 255);
    _mb{63} = band(_bits_lo, 255);
    return;
   compress_block:
    do _i = 0 to 15;
      _w{_i} = _mb{4 * _i} * 16777216 + _mb{4 * _i + 1} * 65536 + _mb{4 * _i + 2} * 256 + _mb{4 * _i + 3};
    end;
    do _i = 16 to 63;
      _w{_i} = mod(sha256_ssig1(_w{_i - 2}) + _w{_i - 7} + sha256_ssig0(_w{_i - 15}) + _w{_i - 16}, 4294967296);
    end;
    _wa = _h{1}; _wb = _h{2}; _wc = _h{3}; _wd = _h{4};
    _we = _h{5}; _wf = _h{6}; _wg = _h{7}; _wh = _h{8};
    do _i = 0 to 63;
      _t1 = mod(_wh + sha256_bsig1(_we) + sha256_ch(_we, _wf, _wg) + _k{_i + 1} + _w{_i}, 4294967296);
      _t2 = mod(sha256_bsig0(_wa) + sha256_maj(_wa, _wb, _wc), 4294967296);
      _wh = _wg; _wg = _wf; _wf = _we;
      _we = mod(_wd + _t1, 4294967296);
      _wd = _wc; _wc = _wb; _wb = _wa;
      _wa = mod(_t1 + _t2, 4294967296);
    end;
    _h{1} = mod(_h{1} + _wa, 4294967296);
    _h{2} = mod(_h{2} + _wb, 4294967296);
    _h{3} = mod(_h{3} + _wc, 4294967296);
    _h{4} = mod(_h{4} + _wd, 4294967296);
    _h{5} = mod(_h{5} + _we, 4294967296);
    _h{6} = mod(_h{6} + _wf, 4294967296);
    _h{7} = mod(_h{7} + _wg, 4294967296);
    _h{8} = mod(_h{8} + _wh, 4294967296);
    return;
  run;
  filename _shafile clear;
  %if %upcase(&ACTUAL_INPUT_SHA256) ne %upcase(&expected) %then %do;
    %put ERROR: 输入数据文件 SHA-256 与批准值不一致，按设计在读取数据之前阻断。;
    %put ERROR- expected=%upcase(&expected);
    %put ERROR- actual=%upcase(&ACTUAL_INPUT_SHA256);
    %abort cancel;
  %end;
  %put NOTE: 输入文件 SHA-256 校验通过：&ACTUAL_INPUT_SHA256;
%mend;

%macro check_environment;
  %global PROGRAM_ACTIVE RUN_STATUS INPUT_PATH;
/*   检查 1：CODE_GENERATION_ONLY 是生成常量，位于全部数据与模型代码之前。 */
  %if %upcase(&CODE_GENERATION_ONLY) = YES %then %do;
    %put NOTE: 当前程序按无 ADaM 数据的 code-generation 模式生成。;
    %put NOTE- 批准语义已完整内联，但本程序不允许读取数据、拟合模型或生成任何结果文件。;
    %put NOTE- 请在 ADaM 数据到达并核对文件名、变量映射与批准版本后，重新编译 analysis plan、;
    %put NOTE- 重新 finalization 与批准，并重新生成 linked 版本的正式程序。;
    %put NOTE- 分析：&ANALYSIS_ID；TFL：&TFL_ID；数据绑定模式：&DATASET_BINDING_MODE;
    %let RUN_STATUS=code_generation_only;
    %let PROGRAM_ACTIVE=0;
    %return;
  %end;
  %if %upcase(&DATA_AVAILABLE) ne YES %then %do;
    %put NOTE: DATA_AVAILABLE 不为 YES：本次运行不读取数据、不拟合模型，正常结束。;
    %let RUN_STATUS=code_generation_only;
    %let PROGRAM_ACTIVE=0;
    %return;
  %end;
/*   检查 2：执行许可与会话能力。 */
  %if %upcase(&EXECUTE_APPROVED_PROGRAM) ne YES %then %do;
    %put ERROR: 必须先核对批准身份与输入数据，再把 EXECUTE_APPROVED_PROGRAM 显式改为 YES。;
    %abort cancel;
  %end;
  %put NOTE: EXECUTE_APPROVED_PROGRAM=YES；已批准的自包含 SAS 程序进入执行路径。;
  %if %upcase(%sysfunc(getoption(encoding))) ne %upcase(&SESSION_ENCODING_REQUIRED) %then %do;
    %put ERROR: 本程序要求会话编码为 &SESSION_ENCODING_REQUIRED，当前为 %sysfunc(getoption(encoding))。;
    %put ERROR- 编码不符时无法保证 UTF-8 BOM CSV 导出与二进制 SHA-256 读取的字节语义。;
    %abort cancel;
  %end;
/*   检查 3：输入/输出目录配置。这两个通道只能传递路径，不能传递任何统计语义。 */
  %if %length(%superq(INPUT_DIR)) = 0 %then %do;
    %put ERROR: 未配置输入目录：请在第 1 部分用户配置区设置 INPUT_DIR。;
    %abort cancel;
  %end;
  %if %length(%superq(OUTPUT_DIR)) = 0 %then %do;
    %put ERROR: 未配置输出目录：请在第 1 部分用户配置区设置 OUTPUT_DIR。;
    %abort cancel;
  %end;
  %let INPUT_PATH=&INPUT_DIR/&DATASET_FILE;
/*   检查 4：输入目录、批准数据文件与输出目录是否存在。程序绝不写入输入目录。 */
  %if %sysfunc(fileexist(&INPUT_DIR)) = 0 %then %do;
    %put ERROR: 输入目录不存在：&INPUT_DIR;
    %abort cancel;
  %end;
  %if %sysfunc(fileexist(&INPUT_PATH)) = 0 %then %do;
    %put ERROR: 批准的输入数据文件不存在：&INPUT_PATH;
    %abort cancel;
  %end;
  %if %sysfunc(fileexist(&OUTPUT_DIR)) = 0 %then %do;
    %put ERROR: 输出目录不存在：&OUTPUT_DIR。请先创建该目录，本程序不会创建输出目录。;
    %abort cancel;
  %end;
/*   检查 5：在读取任何数据之前计算输入文件 SHA-256，并与批准值以大写比较。 */
  %verify_file_sha256(path=&INPUT_PATH, expected=&EXPECTED_INPUT_SHA256)
  %let PROGRAM_ACTIVE=1;
  %let RUN_STATUS=environment_checked;
%mend;
%check_environment;

/* 本分析是确定性 MMRM，不需要随机性，因此不设置也不虚构随机种子。 */

/* =============================================================================
   第 3 部分：读取 ADaM 数据
   ========================================================================== */
/* 本部分只按批准的 dataset.format 生成唯一一种读取分支，读取后立即检查全部批准引用的源变量。 */
/* 输入 libname 固定使用 access=readonly；本程序在任何步骤都不写入输入目录。 */

%macro read_adam_data;
  %global INPUT_ROWS MISSING_SOURCE_VARS;
  %if &PROGRAM_ACTIVE ne 1 %then %return;
  libname _adamin "&INPUT_DIR" access=readonly;
  %if %sysfunc(libref(_adamin)) ne 0 %then %do;
    %put ERROR: 无法以只读方式分配输入 libname：&INPUT_DIR;
    %abort cancel;
  %end;
/*   批准格式为 csv：用 PROC IMPORT 读取，guessingrows=max 保证列类型稳定，不允许自动改列名。 */
  proc import out=_source replace
    datafile="&INPUT_PATH"
    dbms=csv;
    guessingrows=max;
    getnames=yes;
  run;
  %if &syserr gt 4 %then %do;
    %put ERROR: 读取批准的 ADaM 数据失败，syserr=&syserr。;
    %abort cancel;
  %end;
  libname _adamin clear;

/*   批准的 mappings、derivations、filters、groups 与 endpoint definitions 引用的全部源变量； */
/*   缺列时一次列出全部缺失变量后停止，避免统计师逐个试错。 */
  %let MISSING_SOURCE_VARS=;
  data _null_;
    length _missing $4000;
    array _required{9} $32 _temporary_ ('PERSON_ID', 'DELTA_SCORE', 'START_SCORE', 'TIME_INDEX', 'TIME_LABEL', 'RANDOM_ARM', 'REPORTER', 'ANALYSIS_FLAG', 'PARAMCD');
    _dsid = open('work._source');
    if _dsid = 0 then do;
      call symputx('MISSING_SOURCE_VARS', '__OPEN_FAILED__', 'G');
      stop;
    end;
    _rows = attrn(_dsid, 'nobs');
    do _i = 1 to dim(_required);
      if not missing(_required{_i}) and varnum(_dsid, _required{_i}) = 0 then _missing = catx(', ', _missing, _required{_i});
    end;
    _rc = close(_dsid);
    call symputx('MISSING_SOURCE_VARS', _missing, 'G');
    call symputx('INPUT_ROWS', _rows, 'G');
    stop;
  run;
  %if %length(&MISSING_SOURCE_VARS) %then %do;
    %put ERROR: ADaM 数据缺少以下批准引用的源变量：&MISSING_SOURCE_VARS;
    %abort cancel;
  %end;
  %if &INPUT_ROWS = 0 %then %do;
    %put ERROR: 读取到的 ADaM 数据没有任何记录：&INPUT_PATH;
    %abort cancel;
  %end;
  %put NOTE: 已读取输入数据，行数=&INPUT_ROWS;
%mend;
%read_adam_data;

/* =============================================================================
   第 4 部分：数据处理与质量控制
   ========================================================================== */
/* 本部分严格按批准设计的 1-11 顺序执行数据处理与质量控制，语义与同一 TFL 的 R 程序一致。 */
/* 每个 QC 检查写入一个计数宏变量；任一错误计数大于 0 时在 PROC MIXED 之前统一中止执行。 */

/* 步骤 1：批准的 derivations（DATA step if/else recode）。 */
/* PROGRAM-MARKER:DERIVATION:REPORTER_RECODE */
/* PROGRAM-WHY:DERIVATION:REPORTER_RECODE: 按批准的 recode 规则把源变量 REPORTER 归并为分析变量 REPORTER_GROUP，规范化类型为 character，未匹配策略=error，缺失策略=preserve。 */

/* 步骤 2：批准的 population filters。 */
/* PROGRAM-MARKER:FILTER:1 */
/* PROGRAM-WHY:FILTER:1: 按批准的分析人群定义，仅保留变量 ANALYSIS_FLAG 满足 eq 条件的记录。 */

/* 步骤 3-4：批准的 analysis group 与 endpoint definition 分配，并检查互斥分组是否重叠。 */
/* PROGRAM-MARKER:GROUP:TOTAL */
/* PROGRAM-WHY:GROUP:TOTAL: 按批准的分组定义选出属于该分析组的记录（分组标签见第 4 部分 data step 常量），分组之间必须互斥。 */
/* PROGRAM-MARKER:ENDPOINT:TOTAL */
/* PROGRAM-WHY:ENDPOINT:TOTAL: 按批准的 endpoint definition 校验 endpoint 变量 PARAMCD 与各维度取值，行分配规则为 one_row_per_subject_endpoint_visit。 */
/* PROGRAM-MARKER:GROUP:SUBSCALE */
/* PROGRAM-WHY:GROUP:SUBSCALE: 按批准的分组定义选出属于该分析组的记录（分组标签见第 4 部分 data step 常量），分组之间必须互斥。 */
/* PROGRAM-MARKER:ENDPOINT:SUBSCALE */
/* PROGRAM-WHY:ENDPOINT:SUBSCALE: 按批准的 endpoint definition 校验 endpoint 变量 PARAMCD 与各维度取值，行分配规则为 one_row_per_subject_endpoint_visit。 */

/* 步骤 5：批准的标准变量映射。 */
/* PROGRAM-MARKER:MAPPING:subject:PERSON_ID */
/* PROGRAM-WHY:MAPPING:subject: 批准的受试者标识映射，用于受试者内相关结构与唯一性检查。 */
/* PROGRAM-MARKER:MAPPING:response:DELTA_SCORE */
/* PROGRAM-WHY:MAPPING:response: 批准的响应变量映射，是 MMRM 的因变量。 */
/* PROGRAM-MARKER:MAPPING:baseline:START_SCORE */
/* PROGRAM-WHY:MAPPING:baseline: 批准的基线协变量映射，用于基线校正。 */
/* PROGRAM-MARKER:MAPPING:visit:TIME_INDEX */
/* PROGRAM-WHY:MAPPING:visit: 批准的访视变量映射，作为分类时间因子。 */
/* PROGRAM-MARKER:MAPPING:visit_label:TIME_LABEL */
/* PROGRAM-WHY:MAPPING:visit_label: 批准的访视标签映射，仅用于 TFL 展示，不改变统计模型。 */
/* PROGRAM-MARKER:MAPPING:treatment:RANDOM_ARM */
/* PROGRAM-WHY:MAPPING:treatment: 批准的治疗变量映射，用于治疗效应与组间对比。 */
/* PROGRAM-MARKER:TREATMENT_REFERENCE:Placebo"quoted"'apostrophe'\backslash;#%中文 */
/* PROGRAM-WHY:TREATMENT_REFERENCE:Placebo"quoted"'apostrophe'\backslash;#%中文: 批准的参照组写入 CLASS 语句的 ref=，对比方向为 comparator_minus_reference。 */

%macro prepare_analysis_data;
  %global POPULATION_FILTERED_ROWS ANALYSIS_ROWS MISSING_REQUIRED_ROWS SUBJECT_COUNT VISIT_LEVEL_COUNT
          TREATMENT_LEVEL_COUNT QC_GROUP_OVERLAP QC_ENDPOINT_UNAPPROVED QC_DUPLICATE_KEY
          QC_BASELINE_INCONSISTENT QC_TREATMENT_LEVEL QC_VISIT_LABEL QC_ERROR_TOTAL RUN_STATUS;
  %if &PROGRAM_ACTIVE ne 1 %then %return;
/*   步骤 1-2：先执行批准的 recode，再应用批准的 population filters。 */
  data _derived;
    set _source;
  /* recode REPORTER_RECODE; normalized_type=character; blank_is_missing=true */
  length REPORTER_GROUP $32767;
  if not missing(REPORTER) and REPORTER in ('Mother', 'Father', 'Guardian') then REPORTER_GROUP='Caregiver';
  else if not missing(REPORTER) and REPORTER in ('Self') then REPORTER_GROUP='Subject';
  else if not missing(REPORTER) then do; put 'ERROR: PLAN-DERIVATION unmatched value'; abort cancel; end;
  if missing(REPORTER) then REPORTER_GROUP=REPORTER;
    if not ((ANALYSIS_FLAG eq 'Y "quoted" ''apostrophe'' \backslash ;#% 中文')) then delete;
  run;
  proc sql noprint;
    select count(*) into :POPULATION_FILTERED_ROWS trimmed from _derived;
  quit;
  %if &POPULATION_FILTERED_ROWS = 0 %then %do;
    %put ERROR: 应用批准的 population filters 之后没有剩余记录。;
    %abort cancel;
  %end;

/*   步骤 3-5：分配 analysis group、校验 endpoint 维度、构造标准变量，并逐行标记 QC 条件。 */
  data _allocated;
    set _derived;
    length _analysis_group $200 _analysis_group_label $400 _subject $200 _treatment $200 _visit_value $200 _visit_label $400;
    _source_row_id = _n_;
    _analysis_group = '';
    _analysis_group_label = '';
    _group_hit_count = 0;
    _endpoint_unapproved = 0;
    _treatment_unapproved = 0;
    _required_missing = 0;
    if (PARAMCD in ('SCORE_A', 'SCORE_B')) and (REPORTER_GROUP in ('Caregiver', 'Subject')) then do;
      _group_hit_count = _group_hit_count + 1;
      if missing(_analysis_group) then do;
        _analysis_group = 'TOTAL';
        _analysis_group_label = 'Total score "quoted" ''apostrophe'' \backslash ;#% 中文';
      end;
    end;
    if (PARAMCD eq 'SCORE_C') then do;
      _group_hit_count = _group_hit_count + 1;
      if missing(_analysis_group) then do;
        _analysis_group = 'SUBSCALE';
        _analysis_group_label = 'Subscale score "quoted" ''apostrophe'' \backslash ;#% 中文';
      end;
    end;
    if _group_hit_count = 0 then delete;
    if _analysis_group = 'TOTAL' then do;
      if not (PARAMCD in ('SCORE_A', 'SCORE_B')) then do;
        _endpoint_unapproved = 1;
        put 'ERROR: 未批准的 endpoint 维度取值 version ' PARAMCD=;
      end;
      if not (REPORTER_GROUP in ('Caregiver', 'Subject')) then do;
        _endpoint_unapproved = 1;
        put 'ERROR: 未批准的 endpoint 维度取值 reporter ' REPORTER_GROUP=;
      end;
    end;
    if _analysis_group = 'SUBSCALE' then do;
      if not (PARAMCD in ('SCORE_C')) then do;
        _endpoint_unapproved = 1;
        put 'ERROR: 未批准的 endpoint 维度取值 version ' PARAMCD=;
      end;
    end;
    _subject = strip(vvalue(PERSON_ID));
/*     _response 与 _baseline 是数值变量；若批准的源变量是字符型，SAS 会做标准的字符到数值自动转换， */
/*     转换失败的行成为缺失并在步骤 6 作为必需变量缺失删除，与 R 程序的 as.numeric 语义一致。 */
    _response = DELTA_SCORE;
    _baseline = START_SCORE;
    _visit_value = strip(vvalue(TIME_INDEX));
    _visit_label = strip(vvalue(TIME_LABEL));
    _treatment = strip(vvalue(RANDOM_ARM));
    if not (_treatment in ('Placebo"quoted"''apostrophe''\backslash;#%中文', 'Active"quoted"''apostrophe''\backslash;#%中文')) then do;
      _treatment_unapproved = 1;
      put 'ERROR: 观测到未批准的 treatment level ' _treatment=;
    end;
    if missing(_treatment) then _required_missing = 1;
    if missing(_subject) or missing(_response) or missing(_baseline) or missing(_visit_value) then _required_missing = 1;
  run;

/*   步骤 6：删除批准规则定义的必需变量缺失行，并记录删除数量。 */
  data _standard_mmrm;
    set _allocated;
    if _required_missing = 0;
  run;
  proc sql noprint;
    select count(*) into :MISSING_REQUIRED_ROWS trimmed from _allocated where _required_missing = 1;
    select count(*) into :QC_GROUP_OVERLAP trimmed from _allocated where _group_hit_count gt 1;
    select count(*) into :QC_ENDPOINT_UNAPPROVED trimmed from _allocated where _endpoint_unapproved = 1;
    select count(*) into :QC_TREATMENT_LEVEL trimmed from _allocated where _treatment_unapproved = 1;
    select count(*) into :ANALYSIS_ROWS trimmed from _standard_mmrm;
  quit;
  %if &ANALYSIS_ROWS = 0 %then %do;
    %put ERROR: 删除必需变量缺失行之后没有剩余分析记录。;
    %abort cancel;
  %end;
  %put NOTE: 删除必需变量缺失行数=&MISSING_REQUIRED_ROWS;

/*   步骤 10：固定 visit 的分类顺序。_visit 是确定性访视序号（数值可解析时按数值升序，否则按文本升序）， */
/*   _visit_value 保留原始取值，_visit_label 只用于 TFL 展示。CLASS 使用 _visit，保证模型与 TFL 顺序确定。 */
  proc sql noprint;
    create table _visit_distinct as
      select distinct _visit_value, _visit_label from _standard_mmrm;
  quit;
  data _visit_keyed;
    set _visit_distinct;
    _visit_numeric = input(_visit_value, ?? best32.);
  run;
  proc sort data=_visit_keyed out=_visit_ordered;
    by _visit_numeric _visit_value;
  run;
  data _visit_map;
    set _visit_ordered;
    _visit = _n_;
  run;
  proc sql noprint;
    select count(*) into :QC_VISIT_LABEL trimmed from
      (select _visit_value from _visit_map group by _visit_value having count(*) gt 1);
  quit;
  proc sort data=_standard_mmrm;
    by _visit_value;
  run;
  proc sort data=_visit_map out=_visit_map_key;
    by _visit_value;
  run;
  data _standard_mmrm;
    merge _standard_mmrm(in=_a) _visit_map_key(keep=_visit_value _visit in=_b);
    by _visit_value;
    if _a and _b;
  run;
  proc sort data=_standard_mmrm;
    by _analysis_group _subject _visit;
  run;

/*   步骤 7-9：subject/分组/visit 唯一、分组内 baseline 一致、treatment level 与批准 levels 一致。 */
  proc sql noprint;
    select count(*) into :QC_DUPLICATE_KEY trimmed from
      (select _analysis_group, _subject, _visit from _standard_mmrm
         group by _analysis_group, _subject, _visit having count(*) gt 1);
    select count(*) into :QC_BASELINE_INCONSISTENT trimmed from
      (select _analysis_group, _subject from _standard_mmrm
         group by _analysis_group, _subject having count(distinct _baseline) gt 1);
    select count(distinct _subject) into :SUBJECT_COUNT trimmed from _standard_mmrm;
    select count(distinct _visit) into :VISIT_LEVEL_COUNT trimmed from _standard_mmrm;
    select count(distinct _treatment) into :TREATMENT_LEVEL_COUNT trimmed from _standard_mmrm;
  quit;
  %if &TREATMENT_LEVEL_COUNT ne &APPROVED_TREATMENT_LEVEL_COUNT %then %do;
    %put ERROR: 批准的全部 treatment level 必须都出现在分析数据中，批准=&APPROVED_TREATMENT_LEVEL_COUNT，观测=&TREATMENT_LEVEL_COUNT。;
    %let QC_TREATMENT_LEVEL=%eval(&QC_TREATMENT_LEVEL + 1);
  %end;

/*   统一 hard QC gate：任一错误计数大于 0 时在 PROC MIXED 之前中止，不允许只打印查询结果后继续。 */
  %let QC_ERROR_TOTAL=%eval(&QC_GROUP_OVERLAP + &QC_ENDPOINT_UNAPPROVED + &QC_DUPLICATE_KEY
                            + &QC_BASELINE_INCONSISTENT + &QC_TREATMENT_LEVEL + &QC_VISIT_LABEL);
  %put NOTE: QC 计数：分组重叠=&QC_GROUP_OVERLAP；endpoint 未批准取值=&QC_ENDPOINT_UNAPPROVED;
  %put NOTE- 重复 subject/分组/visit=&QC_DUPLICATE_KEY；baseline 不一致=&QC_BASELINE_INCONSISTENT;
  %put NOTE- treatment level 问题=&QC_TREATMENT_LEVEL；visit label 冲突=&QC_VISIT_LABEL;
  %if &QC_ERROR_TOTAL gt 0 %then %do;
    %put ERROR: 数据质量控制未通过，错误计数合计=&QC_ERROR_TOTAL，按设计在 PROC MIXED 之前中止。;
    %let RUN_STATUS=qc_failed;
    %abort cancel;
  %end;
  %let RUN_STATUS=data_prepared;
/*   步骤 11：数据处理计数已写入宏变量，供第 8 部分诊断与运行记录使用。 */
  %put NOTE: 数据处理计数：输入=&INPUT_ROWS；筛选后=&POPULATION_FILTERED_ROWS；分析=&ANALYSIS_ROWS；缺失删除=&MISSING_REQUIRED_ROWS;
%mend;
%prepare_analysis_data;

/* 至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。 */

/* =============================================================================
   第 5 部分：MMRM 模型拟合
   ========================================================================== */
/* 本部分实现批准的 MMRM 拟合与可执行 covariance fallback；宏在第 6 部分调用。 */
/* fallback 不是注释，而是真实控制流：按批准顺序尝试，满足全部选定条件才停止。 */

/* 批准的固定效应（顺序逐字来自 analysis plan）： */
/* PROGRAM-MARKER:FIXED_EFFECT:baseline */
/* PROGRAM-WHY:FIXED_EFFECT:baseline: 批准的固定效应：以 _baseline 作为连续协变量校正基线水平。 */
/* PROGRAM-MARKER:FIXED_EFFECT:visit */
/* PROGRAM-WHY:FIXED_EFFECT:visit: 批准的固定效应：以 CLASS _visit 估计各访视的均值结构。 */
/* PROGRAM-MARKER:FIXED_EFFECT:baseline_by_visit */
/* PROGRAM-WHY:FIXED_EFFECT:baseline_by_visit: 批准的固定效应：允许 _baseline 的作用随访视变化。 */
/* PROGRAM-MARKER:FIXED_EFFECT:treatment */
/* PROGRAM-WHY:FIXED_EFFECT:treatment: 批准的固定效应：估计治疗组主效应。 */
/* PROGRAM-MARKER:FIXED_EFFECT:treatment_by_visit */
/* PROGRAM-WHY:FIXED_EFFECT:treatment_by_visit: 批准的固定效应：估计治疗与访视交互，支持逐访视组间比较。 */

/* 批准的估计方法为 REML；本 profile 不允许改为 ML。 */
/* PROGRAM-MARKER:REML:TRUE */
/* PROGRAM-WHY:REML:TRUE: 批准的方差成分估计方法为 REML，可减少小样本方差低估。 */

/* 批准的协方差结构顺序（第一个为 primary，其后按顺序 fallback）： */
/* PROGRAM-MARKER:COVARIANCE:TOEP */
/* PROGRAM-WHY:COVARIANCE:TOEP: 批准的主协方差结构 Toeplitz (TOEP)，优先用于受试者内重复测量。 */
/* PROGRAM-MARKER:COVARIANCE:CS */
/* PROGRAM-WHY:COVARIANCE:CS: 批准的第 1 顺位 fallback 协方差结构 复合对称 (CS)，仅在前序结构未收敛时按批准顺序尝试。 */
/* PROGRAM-MARKER:COVARIANCE:AR1 */
/* PROGRAM-WHY:COVARIANCE:AR1: 批准的第 2 顺位 fallback 协方差结构 一阶自回归 (AR1)，仅在前序结构未收敛时按批准顺序尝试。 */

/* 批准的自由度方法： */
/* PROGRAM-MARKER:DF_METHOD:Satterthwaite */
/* PROGRAM-WHY:DF_METHOD:Satterthwaite: 批准的小样本自由度方法为 Satterthwaite，对应 PROC MIXED 的 ddfm=satterth。 */

/* PROGRAM-MARKER:SAS:FALLBACK_CONTROL */
/* PROGRAM-MARKER:SAS:ODS_CAPTURE */
/* PROGRAM-MARKER:SAS:CONVERGENCE_GATE */

%macro run_mmrm_with_fallback;
  %global MMRM_FIT_SUCCESS COVARIANCE_PATH SELECTED_COVARIANCE RUN_STATUS
          ATT_STATUS ATT_REASON ATT_ACTION ATT_SYSERR ATT_REASON_TEXT
          ATT_LSM_N ATT_LSM_KEYS ATT_LSM_INCOMPLETE
          ATT_TRT_LSM_N ATT_TRT_LSM_KEYS ATT_TRT_LSM_INCOMPLETE
          ATT_DIFF_N ATT_DIFF_KEYS ATT_DIFF_INCOMPLETE ATT_DIFF_COLUMNS;
  %if &PROGRAM_ACTIVE ne 1 %then %return;
  %local g c gid cov covtype selected group_ok gvisits gtreat gsubj selected_groups;
/*   封闭 allow/block 规则表：所有判定只使用结构化 ODS 字段与 key 计数， */
/*   不对日志自由文本做模糊猜测；表中没有的情况一律按 block 处理。 */
  data _warning_rules;
    length rule_code $40 rule_action $5 rule_note $200;
    rule_code='converged_no_blocking_condition'; rule_action='allow'; rule_note='收敛成功且没有任何阻断条件，允许选定本次 covariance。'; output;
    rule_code='syserr_error'; rule_action='block'; rule_note='PROC MIXED 返回错误级 syserr，按封闭规则表阻断。'; output;
    rule_code='missing_ods_dataset'; rule_action='block'; rule_note='启用 estimand 需要的 ODS 结果集缺失，按封闭规则表阻断。'; output;
    rule_code='convergence_status_nonzero'; rule_action='block'; rule_note='ConvergenceStatus 的 Status 不为 0，视为未收敛并阻断。'; output;
    rule_code='diffs_key_columns_missing'; rule_action='block'; rule_note='Diffs 结果集缺少成对比较的 key 列，按封闭规则表阻断。'; output;
    rule_code='duplicate_or_missing_key'; rule_action='block'; rule_note='预期的 group/visit/contrast key 不完整或不唯一，按封闭规则表阻断。'; output;
    rule_code='incomplete_inference_fields'; rule_action='block'; rule_note='estimate/SE/df/CI/p-value 中存在缺失，按封闭规则表阻断。'; output;
  run;
  %let MMRM_FIT_SUCCESS=0;
  %let SELECTED_COVARIANCE=;
  %let COVARIANCE_PATH=;
  %let selected_groups=0;
  proc datasets library=work nolist nowarn;
    delete _selected_lsmeans _selected_diffs _selected_solutionf _selected_convergence _fit_attempts;
  quit;
  data _fit_attempts;
    length analysis_group_id $200 covariance $20 outcome $20 reason_code $40 reason_text $400;
    stop;
  run;
  %do g=1 %to &GROUP_COUNT;
    %let gid=%scan(&GROUP_IDS, &g, %str( ));
    %let selected=;
    %let group_ok=1;
    %let gvisits=0;
    %let gtreat=0;
    %let gsubj=0;
    proc sql noprint;
      select count(distinct _visit) into :gvisits trimmed from _standard_mmrm where _analysis_group = "&gid";
      select count(distinct _treatment) into :gtreat trimmed from _standard_mmrm where _analysis_group = "&gid";
      select count(distinct _subject) into :gsubj trimmed from _standard_mmrm where _analysis_group = "&gid";
    quit;
    %if &gvisits lt 2 or &gsubj lt 2 %then %do;
      %put ERROR: 分组 &gid 的 subject 或 visit 水平不足，无法拟合 MMRM。;
      %let group_ok=0;
    %end;
    %do c=1 %to &COVARIANCE_COUNT;
/*       一旦选定就不再尝试后续 covariance；这等价于成功后 break。 */
      %if %length(&selected) = 0 and &group_ok = 1 %then %do;
        %let cov=%scan(&COVARIANCE_KEYS, &c, %str( ));
        %let covtype=%scan(&COVARIANCE_TYPES, &c, %str( ));
/*         每次尝试前清理本次 ODS work datasets，避免沿用上一次 attempt 的结果。 */
        proc datasets library=work nolist nowarn;
          delete _ods_convergence _ods_lsmeans _ods_diffs _ods_solutionf;
        quit;
        %let ATT_STATUS=9;
        %let ATT_REASON_TEXT=;
        %let ATT_LSM_N=0;
        %let ATT_LSM_KEYS=0;
        %let ATT_LSM_INCOMPLETE=1;
        ods exclude all;
        ods output ConvergenceStatus=work._ods_convergence
                   LSMeans=work._ods_lsmeans
                   Diffs=work._ods_diffs
                   SolutionF=work._ods_solutionf;
        proc mixed data=_standard_mmrm(where=(_analysis_group = "&gid")) method=reml order=data;
          class _subject _visit _treatment(ref='Placebo"quoted"''apostrophe''\backslash;#%中文');
          model _response = _baseline _visit _baseline*_visit _treatment _treatment*_visit / ddfm=satterth solution cl alpha=0.05;
          repeated _visit / subject=_subject type=&covtype;
          %mmrm_estimand_statements
        run;
        ods output close;
        ods exclude none;
        %let ATT_SYSERR=&syserr;
        %if %sysfunc(exist(work._ods_convergence)) %then %do;
          data _null_;
            set work._ods_convergence(obs=1);
            call symputx('ATT_STATUS', Status, 'G');
            call symputx('ATT_REASON_TEXT', Reason, 'G');
            stop;
          run;
        %end;
        %if %sysfunc(exist(work._ods_lsmeans)) %then %do;
          proc sql noprint;
            select count(*) into :ATT_LSM_N trimmed from work._ods_lsmeans where Effect = '_visit';
            select count(distinct put(_visit, best12.)) into :ATT_LSM_KEYS trimmed from work._ods_lsmeans where Effect = '_visit';
            select sum(missing(Estimate) or missing(StdErr) or missing(DF) or missing(Lower) or missing(Upper) or missing(Probt))
              into :ATT_LSM_INCOMPLETE trimmed from work._ods_lsmeans where Effect = '_visit';
          quit;
        %end;
        %let ATT_TRT_LSM_N=0;
        %let ATT_TRT_LSM_KEYS=0;
        %let ATT_TRT_LSM_INCOMPLETE=1;
        %if %sysfunc(exist(work._ods_lsmeans)) %then %do;
          proc sql noprint;
            select count(*) into :ATT_TRT_LSM_N trimmed from work._ods_lsmeans where Effect = '_treatment*_visit';
            select count(distinct catx('|', _treatment, put(_visit, best12.))) into :ATT_TRT_LSM_KEYS trimmed
              from work._ods_lsmeans where Effect = '_treatment*_visit';
            select sum(missing(Estimate) or missing(StdErr) or missing(DF) or missing(Lower) or missing(Upper) or missing(Probt))
              into :ATT_TRT_LSM_INCOMPLETE trimmed from work._ods_lsmeans where Effect = '_treatment*_visit';
          quit;
        %end;
        %let ATT_DIFF_N=0;
        %let ATT_DIFF_KEYS=0;
        %let ATT_DIFF_INCOMPLETE=1;
        %let ATT_DIFF_COLUMNS=0;
        %if %sysfunc(exist(work._ods_diffs)) %then %do;
          data _null_;
            _dsid = open('work._ods_diffs');
            _ok = 0;
            if _dsid ne 0 then do;
              if varnum(_dsid, '__treatment') gt 0 and varnum(_dsid, '__visit') gt 0 then _ok = 1;
              _rc = close(_dsid);
            end;
            call symputx('ATT_DIFF_COLUMNS', _ok, 'G');
            stop;
          run;
        %end;
        %if &ATT_DIFF_COLUMNS = 1 %then %do;
          proc sql noprint;
            select count(*) into :ATT_DIFF_N trimmed from work._ods_diffs
              where Effect = '_treatment*_visit' and _visit = __visit
                and _treatment = 'Active"quoted"''apostrophe''\backslash;#%中文' and __treatment = 'Placebo"quoted"''apostrophe''\backslash;#%中文';
            select count(distinct put(_visit, best12.)) into :ATT_DIFF_KEYS trimmed from work._ods_diffs
              where Effect = '_treatment*_visit' and _visit = __visit
                and _treatment = 'Active"quoted"''apostrophe''\backslash;#%中文' and __treatment = 'Placebo"quoted"''apostrophe''\backslash;#%中文';
            select sum(missing(Estimate) or missing(StdErr) or missing(DF) or missing(Lower) or missing(Upper) or missing(Probt))
              into :ATT_DIFF_INCOMPLETE trimmed from work._ods_diffs
              where Effect = '_treatment*_visit' and _visit = __visit
                and _treatment = 'Active"quoted"''apostrophe''\backslash;#%中文' and __treatment = 'Placebo"quoted"''apostrophe''\backslash;#%中文';
          quit;
        %end;
/*         依次判定阻断条件，得到唯一稳定的 reason code。 */
        %let ATT_REASON=converged_no_blocking_condition;
        %if &ATT_SYSERR gt 4 %then %let ATT_REASON=syserr_error;
        %else %if %sysfunc(exist(work._ods_convergence)) = 0 %then %let ATT_REASON=missing_ods_dataset;
        %else %if %sysfunc(exist(work._ods_lsmeans)) = 0 %then %let ATT_REASON=missing_ods_dataset;
        %else %if %sysfunc(exist(work._ods_solutionf)) = 0 %then %let ATT_REASON=missing_ods_dataset;
        %else %if %sysfunc(exist(work._ods_diffs)) = 0 %then %let ATT_REASON=missing_ods_dataset;
        %else %if &ATT_DIFF_COLUMNS ne 1 %then %let ATT_REASON=diffs_key_columns_missing;
        %else %if &ATT_STATUS ne 0 %then %let ATT_REASON=convergence_status_nonzero;
        %else %if &ATT_LSM_N ne &gvisits or &ATT_LSM_KEYS ne &gvisits %then %let ATT_REASON=duplicate_or_missing_key;
        %else %if &ATT_TRT_LSM_N ne %eval(&gvisits * &gtreat) or &ATT_TRT_LSM_KEYS ne %eval(&gvisits * &gtreat) %then %let ATT_REASON=duplicate_or_missing_key;
        %else %if &ATT_DIFF_N ne &gvisits or &ATT_DIFF_KEYS ne &gvisits %then %let ATT_REASON=duplicate_or_missing_key;
        %else %if &ATT_LSM_INCOMPLETE ne 0 %then %let ATT_REASON=incomplete_inference_fields;
        %else %if &ATT_TRT_LSM_INCOMPLETE ne 0 %then %let ATT_REASON=incomplete_inference_fields;
        %else %if &ATT_DIFF_INCOMPLETE ne 0 %then %let ATT_REASON=incomplete_inference_fields;
        %let ATT_ACTION=block;
        proc sql noprint;
          select rule_action into :ATT_ACTION trimmed from _warning_rules where rule_code = "&ATT_REASON";
        quit;
        data _attempt_row;
          length analysis_group_id $200 covariance $20 outcome $20 reason_code $40 reason_text $400;
          analysis_group_id = "&gid";
          covariance = "&cov";
          reason_code = "&ATT_REASON";
          if "&ATT_ACTION" = 'allow' then outcome = 'selected';
          else outcome = 'failed';
          reason_text = symget('ATT_REASON_TEXT');
        run;
        proc append base=_fit_attempts data=_attempt_row force;
        run;
        %let COVARIANCE_PATH=&COVARIANCE_PATH &gid/&cov=&ATT_REASON;
        %put NOTE: 分组 &gid 尝试协方差 &cov：&ATT_ACTION（&ATT_REASON）;
        %if &ATT_ACTION = allow %then %do;
          data _attempt_lsmeans;
            set work._ods_lsmeans;
            length _analysis_group $200 _covariance $20;
            _analysis_group = "&gid";
            _covariance = "&cov";
          run;
          proc append base=_selected_lsmeans data=_attempt_lsmeans force;
          run;
          data _attempt_solutionf;
            set work._ods_solutionf;
            length _analysis_group $200 _covariance $20;
            _analysis_group = "&gid";
            _covariance = "&cov";
          run;
          proc append base=_selected_solutionf data=_attempt_solutionf force;
          run;
          data _attempt_diffs;
            set work._ods_diffs;
            length _analysis_group $200 _covariance $20;
            _analysis_group = "&gid";
            _covariance = "&cov";
          run;
          proc append base=_selected_diffs data=_attempt_diffs force;
          run;
          data _attempt_convergence;
            set work._ods_convergence;
            length _analysis_group $200 _covariance $20;
            _analysis_group = "&gid";
            _covariance = "&cov";
          run;
          proc append base=_selected_convergence data=_attempt_convergence force;
          run;
          %let selected=&cov;
        %end;
      %end;
    %end;
    %if %length(&selected) %then %do;
      %let selected_groups=%eval(&selected_groups + 1);
      %let SELECTED_COVARIANCE=&SELECTED_COVARIANCE &gid/&selected;
    %end;
    %else %do;
      %put ERROR: 分组 &gid 的全部批准协方差结构均未满足选定条件。;
    %end;
  %end;
  %if &selected_groups = &GROUP_COUNT %then %do;
    %let MMRM_FIT_SUCCESS=1;
    %let RUN_STATUS=model_fitted;
  %end;
  %else %do;
    %let MMRM_FIT_SUCCESS=0;
    %let RUN_STATUS=fit_failed;
    %put ERROR: 至少一个分组的 MMRM 拟合未成功，按设计只写诊断与运行记录，不导出 raw 与 final TFL。;
  %end;
%mend;

/* =============================================================================
   第 6 部分：统计推断
   ========================================================================== */
/* 本部分只渲染批准 plan 中显式为 true 的估计量；未批准的估计量不会出现在代码中。 */
/* LSMEANS 结果通过 ODS OUTPUT 捕获，随后映射成与同一 TFL 的 R 程序相同的列语义。 */

/* PROGRAM-MARKER:ESTIMAND:visit_lsmeans */
/* PROGRAM-WHY:ESTIMAND:visit_lsmeans: 批准的估计量：逐访视 LS mean。 */
/* PROGRAM-MARKER:ESTIMAND:treatment_visit_lsmeans */
/* PROGRAM-WHY:ESTIMAND:treatment_visit_lsmeans: 批准的估计量：逐治疗组、逐访视 LS mean。 */
/* PROGRAM-MARKER:ESTIMAND:pairwise_differences */
/* PROGRAM-WHY:ESTIMAND:pairwise_differences: 批准的估计量：按批准方向与置信水平的逐访视组间差值。 */

/* 成对比较方向说明：PROC MIXED 的 DIFF=CONTROL 只能为交互效应指定单个 control 单元格， */
/* 无法表达“每个访视内与参照组比较”。因此使用 DIFF 生成全部成对差值， */
/* 再按批准的 reference/comparator 与 comparator_minus_reference 方向精确筛选同一访视内的对比， */
/* 得到的估计量与批准语义完全一致，且不依赖运行时的自由解释。 */
/* 批准的 multiplicity_adjustment=none，对应 ADJUST=T（未调整 t 检验），不使用任何隐式默认。 */

%macro mmrm_estimand_statements;
  lsmeans _visit / cl alpha=0.05;
  lsmeans _treatment*_visit / cl alpha=0.05 diff adjust=t;
%mend;

/* 按批准顺序执行 primary 与 fallback covariance；宏体在第 5 部分定义。 */
%run_mmrm_with_fallback;

%macro build_raw_results;
  %global INFERENCE_COMPLETE RUN_STATUS INFERENCE_ROWS INFERENCE_MISSING;
  %if &PROGRAM_ACTIVE ne 1 %then %return;
  %let INFERENCE_COMPLETE=0;
  %let INFERENCE_ROWS=0;
  %let INFERENCE_MISSING=1;
  %if &MMRM_FIT_SUCCESS ne 1 %then %do;
    %put ERROR: 模型未满足批准的选定条件，跳过统计推断结果整理。;
    %return;
  %end;
/*   LS mean 结果映射：与 R 程序相同的列语义（estimand/treatment/contrast/visit/estimate/...）。 */
  data _raw_lsmeans;
    set _selected_lsmeans;
    length analysis_id $200 tfl_id $200 estimand $40 treatment $200 contrast $400;
    analysis_id = "&ANALYSIS_ID";
    tfl_id = "&TFL_ID";
    if Effect = '_visit' then estimand = 'visit_lsmean';
    else if Effect = '_treatment*_visit' then estimand = 'treatment_visit_lsmean';
    else delete;
    if Effect = '_treatment*_visit' then treatment = _treatment;
    else treatment = '';
    contrast = '';
    _estimate = Estimate;
    _standard_error = StdErr;
    _degrees_of_freedom = DF;
    _lower = Lower;
    _upper = Upper;
    _statistic = tValue;
    _p_value = Probt;
    keep analysis_id tfl_id _analysis_group _covariance estimand treatment contrast _visit
         _estimate _standard_error _degrees_of_freedom _lower _upper _statistic _p_value;
  run;
/*   成对比较：只保留同一访视内、方向为 comparator 减 reference 的批准对比。 */
  data _raw_diffs;
    set _selected_diffs;
    where Effect = '_treatment*_visit' and _visit = __visit
      and _treatment = 'Active"quoted"''apostrophe''\backslash;#%中文'
      and __treatment = 'Placebo"quoted"''apostrophe''\backslash;#%中文';
    length analysis_id $200 tfl_id $200 estimand $40 treatment $200 contrast $400;
    analysis_id = "&ANALYSIS_ID";
    tfl_id = "&TFL_ID";
    estimand = 'treatment_pairwise_difference';
    treatment = '';
    contrast = 'Active"quoted"''apostrophe''\backslash;#%中文 - Placebo"quoted"''apostrophe''\backslash;#%中文';
    _estimate = Estimate;
    _standard_error = StdErr;
    _degrees_of_freedom = DF;
    _lower = Lower;
    _upper = Upper;
    _statistic = tValue;
    _p_value = Probt;
    keep analysis_id tfl_id _analysis_group _covariance estimand treatment contrast _visit
         _estimate _standard_error _degrees_of_freedom _lower _upper _statistic _p_value;
  run;

/*   合并 LS mean 与成对比较，并接入分组标签与访视标签，形成 raw 推断结果。 */
  data _raw_stacked;
    set _raw_lsmeans _raw_diffs;
  run;
  proc sql noprint;
    create table _raw_results as
      select r.analysis_id as analysis_id,
             r.tfl_id as tfl_id,
             r._analysis_group as analysis_group_id,
             g._analysis_group_label as analysis_group_label,
             r.estimand as estimand,
             r.treatment as treatment,
             r.contrast as contrast,
             r._visit as visit_index,
             v._visit_label as visit,
             r._estimate as estimate,
             r._standard_error as standard_error,
             r._degrees_of_freedom as degrees_of_freedom,
             r._lower as lower_confidence_limit,
             r._upper as upper_confidence_limit,
             r._statistic as statistic,
             r._p_value as p_value,
             r._covariance as covariance_used
        from _raw_stacked as r
        left join (select distinct _analysis_group, _analysis_group_label from _standard_mmrm) as g
          on r._analysis_group = g._analysis_group
        left join (select _visit, _visit_label from _visit_map) as v
          on r._visit = v._visit
        order by analysis_group_id, visit_index, estimand, treatment;
    select count(*) into :INFERENCE_ROWS trimmed from _raw_results;
    select sum(missing(estimate) or missing(standard_error) or missing(degrees_of_freedom)
               or missing(lower_confidence_limit) or missing(upper_confidence_limit) or missing(p_value))
      into :INFERENCE_MISSING trimmed from _raw_results;
  quit;
/*   输出前检查 estimate、SE、df、置信区间与 p-value 是否完整；任一缺失都不允许写出正式 TFL。 */
  %if &INFERENCE_ROWS gt 0 and &INFERENCE_MISSING = 0 %then %do;
    %let INFERENCE_COMPLETE=1;
  %end;
  %else %do;
    %let INFERENCE_COMPLETE=0;
    %put ERROR: 推断字段不完整（行数=&INFERENCE_ROWS，缺失计数=&INFERENCE_MISSING），不写出正式 TFL。;
  %end;
  %put NOTE: 推断结果行数=&INFERENCE_ROWS；推断字段完整=&INFERENCE_COMPLETE;
%mend;
%build_raw_results;

/* =============================================================================
   第 7 部分：TFL 结果整理与导出
   ========================================================================== */
/* 本部分把 observed summary 与 MMRM 推断结果整理成该 TFL 专属的最终 table， */
/* 使用固定小数位与 p-value/置信区间格式，输出文件名逐字来自 contract，编码为 UTF-8 BOM CSV。 */
/* 固定格式：estimate/SE/CI/统计量 3 位小数；自由度 1 位小数；p-value 4 位小数，极小值写成 <0.0001。 */

/* 规范化 UTF-8 BOM CSV writer（DATA step 实际写出，不是注释 stub）： */
/*   1 文件首三字节固定为 BOM EF BB BF； */
/*   2 字段分隔符固定为半角逗号； */
/*   3 每个字段一律用半角双引号包裹，字段内的双引号按 CSV 规则转义成两个双引号； */
/*   4 缺失值写成空字段（两个连续双引号）； */
/*   5 行结束固定为 CRLF（0D0A）。 */
/* 为什么不使用 proc export：proc export 不保证 BOM 三字节、逐字段引号转义、缺失值语义与固定行结束， */
/* 因此本程序用显式 DATA step writer 控制全部字节语义；导出不是注释，而是真实执行的写出步骤。 */
%macro write_csv_utf8_bom(data=, path=, columns=);
  data _null_;
    set &data;
    file "&path" recfm=n lrecl=32767 encoding='utf-8';
    length _csv_field $32767 _csv_line $32767 _csv_name $32;
    if _n_ = 1 then do;
      put 'EFBBBF'x;
      _csv_line = '';
      do _csv_i = 1 to countw("&columns", ' ');
        _csv_name = scan("&columns", _csv_i, ' ');
        _csv_line = catx(',', _csv_line, cats('"', _csv_name, '"'));
      end;
      _csv_len = length(_csv_line);
      put _csv_line $varying32767. _csv_len;
      put '0D0A'x;
    end;
    _csv_line = '';
    do _csv_i = 1 to countw("&columns", ' ');
      _csv_name = scan("&columns", _csv_i, ' ');
      _csv_field = strip(vvaluex(_csv_name));
      if _csv_field = '.' then _csv_field = '';
      _csv_line = catx(',', _csv_line, cats('"', tranwrd(_csv_field, '"', '""'), '"'));
    end;
    _csv_len = length(_csv_line);
    put _csv_line $varying32767. _csv_len;
    put '0D0A'x;
  run;
%mend;

/* PROGRAM-MARKER:FINAL_CSV_WRITE:EXECUTABLE */
/* 只有在全部分组拟合成功且推断字段完整时才写 raw 与 final TFL； */
/* 否则只在第 8 部分写诊断与运行记录，绝不创建冒充正式结果的 final 文件。 */
%macro export_tfl_results;
  %global RUN_STATUS RAW_OUTPUT_WRITTEN FINAL_OUTPUT_WRITTEN;
  %if &PROGRAM_ACTIVE ne 1 %then %return;
  %if &MMRM_FIT_SUCCESS ne 1 or &INFERENCE_COMPLETE ne 1 %then %do;
    %if &MMRM_FIT_SUCCESS = 1 %then %let RUN_STATUS=partial;
    %else %let RUN_STATUS=fit_failed;
    %put ERROR: 模型或推断未满足批准的完整性条件，按设计不写出 raw 与 final TFL。;
    %return;
  %end;
/*   observed summary 独立生成后再与 LS mean 结果合并。 */
  proc sort data=_standard_mmrm out=_summary_input;
    by _analysis_group _analysis_group_label _treatment _visit;
  run;
  proc means data=_summary_input noprint;
    by _analysis_group _analysis_group_label _treatment _visit;
    var _response _baseline;
    output out=_observed_summary(drop=_type_ _freq_)
           n=n_response n_baseline
           mean=mean_response mean_baseline
           std=sd_response sd_baseline
           median=median_response median_baseline
           min=min_response min_baseline
           max=max_response max_baseline;
  run;
  proc sql noprint;
    create table _final_source as
      select o._analysis_group as analysis_group_id,
             o._analysis_group_label as analysis_group_label,
             o._treatment as treatment,
             o._visit as visit_index,
             v._visit_label as visit_label,
             o.n_response, o.mean_response, o.sd_response, o.median_response, o.min_response, o.max_response,
             o.n_baseline, o.mean_baseline, o.sd_baseline,
             r.estimate, r.standard_error, r.degrees_of_freedom,
             r.lower_confidence_limit, r.upper_confidence_limit, r.statistic, r.p_value, r.covariance_used
        from _observed_summary as o
        left join (select _visit, _visit_label from _visit_map) as v
          on o._visit = v._visit
        left join (select * from _raw_results where estimand = "&PRIMARY_ESTIMAND") as r
          on o._analysis_group = r.analysis_group_id and o._visit = r.visit_index
             and o._treatment = r.treatment
        order by analysis_group_id, visit_index, treatment;
  quit;
  data _final_observed;
    set _final_source;
    length analysis_id $200 tfl_id $200 row_type $40 estimand $40 contrast $400 visit $400
           observed_n $32 observed_mean $32 observed_sd $32 observed_median $32 observed_min $32 observed_max $32
           baseline_n $32 baseline_mean $32 baseline_sd $32
           mmrm_estimate $32 _f_standard_error $32 confidence_interval $64 _f_degrees_of_freedom $32
           _f_statistic $32 _f_p_value $32 _f_covariance_used $32;
    analysis_id = "&ANALYSIS_ID";
    tfl_id = "&TFL_ID";
    row_type = 'observed_with_mmrm';
    estimand = "&PRIMARY_ESTIMAND";
    contrast = '';
    visit = visit_label;
    observed_n = strip(put(n_response, 32.));
    observed_mean = ifc(missing(mean_response), '', strip(put(mean_response, 32.3)));
    observed_sd = ifc(missing(sd_response), '', strip(put(sd_response, 32.3)));
    observed_median = ifc(missing(median_response), '', strip(put(median_response, 32.3)));
    observed_min = ifc(missing(min_response), '', strip(put(min_response, 32.3)));
    observed_max = ifc(missing(max_response), '', strip(put(max_response, 32.3)));
    baseline_n = strip(put(n_baseline, 32.));
    baseline_mean = ifc(missing(mean_baseline), '', strip(put(mean_baseline, 32.3)));
    baseline_sd = ifc(missing(sd_baseline), '', strip(put(sd_baseline, 32.3)));
    mmrm_estimate = ifc(missing(estimate), '', strip(put(estimate, 32.3)));
    _f_standard_error = ifc(missing(standard_error), '', strip(put(standard_error, 32.3)));
    confidence_interval = ifc(missing(lower_confidence_limit) or missing(upper_confidence_limit), '', cats('(', catx(', ', strip(put(lower_confidence_limit, 32.3)), strip(put(upper_confidence_limit, 32.3))), ')'));
    _f_degrees_of_freedom = ifc(missing(degrees_of_freedom), '', strip(put(degrees_of_freedom, 32.1)));
    _f_statistic = ifc(missing(statistic), '', strip(put(statistic, 32.3)));
    _f_p_value = ifc(missing(p_value), '', ifc(p_value lt 0.0001, '<0.0001', strip(put(p_value, 32.4))));
    _f_covariance_used = covariance_used;
    drop standard_error degrees_of_freedom statistic p_value estimate lower_confidence_limit
         upper_confidence_limit covariance_used visit_label visit_index
         n_response mean_response sd_response median_response min_response max_response
         n_baseline mean_baseline sd_baseline;
    rename _f_standard_error=standard_error _f_degrees_of_freedom=degrees_of_freedom
           _f_statistic=statistic _f_p_value=p_value _f_covariance_used=covariance_used;
  run;
/*   批准的成对比较行追加在观测行之后，与 R 程序的最终 table 行顺序一致。 */
  data _final_contrast;
    set _raw_results;
    where estimand = 'treatment_pairwise_difference';
    length row_type $40 observed_n $32 observed_mean $32 observed_sd $32 observed_median $32 observed_min $32 observed_max $32
           baseline_n $32 baseline_mean $32 baseline_sd $32 mmrm_estimate $32 confidence_interval $64
           _c_standard_error $32 _c_degrees_of_freedom $32 _c_statistic $32 _c_p_value $32;
    row_type = 'treatment_contrast';
    observed_n = ''; observed_mean = ''; observed_sd = ''; observed_median = ''; observed_min = ''; observed_max = '';
    baseline_n = ''; baseline_mean = ''; baseline_sd = '';
    mmrm_estimate = ifc(missing(estimate), '', strip(put(estimate, 32.3)));
    _c_standard_error = ifc(missing(standard_error), '', strip(put(standard_error, 32.3)));
    confidence_interval = ifc(missing(lower_confidence_limit) or missing(upper_confidence_limit), '', cats('(', catx(', ', strip(put(lower_confidence_limit, 32.3)), strip(put(upper_confidence_limit, 32.3))), ')'));
    _c_degrees_of_freedom = ifc(missing(degrees_of_freedom), '', strip(put(degrees_of_freedom, 32.1)));
    _c_statistic = ifc(missing(statistic), '', strip(put(statistic, 32.3)));
    _c_p_value = ifc(missing(p_value), '', ifc(p_value lt 0.0001, '<0.0001', strip(put(p_value, 32.4))));
    drop standard_error degrees_of_freedom statistic p_value estimate lower_confidence_limit upper_confidence_limit visit_index;
    rename _c_standard_error=standard_error _c_degrees_of_freedom=degrees_of_freedom
           _c_statistic=statistic _c_p_value=p_value;
  run;
  data _final_table;
    set _final_observed _final_contrast;
    keep analysis_id tfl_id analysis_group_id analysis_group_label row_type estimand treatment contrast visit observed_n observed_mean observed_sd observed_median observed_min observed_max baseline_n baseline_mean baseline_sd mmrm_estimate standard_error confidence_interval degrees_of_freedom statistic p_value covariance_used;
  run;

/*   raw 结果集使用与 R 程序相同的列语义，数值保留较高精度以便复核。 */
  data _raw_export;
    set _raw_results(rename=(estimate=_n_estimate standard_error=_n_standard_error
                             degrees_of_freedom=_n_degrees_of_freedom
                             lower_confidence_limit=_n_lower upper_confidence_limit=_n_upper
                             statistic=_n_statistic p_value=_n_p_value));
    length estimate $32 standard_error $32 degrees_of_freedom $32 lower_confidence_limit $32
           upper_confidence_limit $32 statistic $32 p_value $32;
    estimate = ifc(missing(_n_estimate), '', strip(put(_n_estimate, 32.6)));
    standard_error = ifc(missing(_n_standard_error), '', strip(put(_n_standard_error, 32.6)));
    degrees_of_freedom = ifc(missing(_n_degrees_of_freedom), '', strip(put(_n_degrees_of_freedom, 32.4)));
    lower_confidence_limit = ifc(missing(_n_lower), '', strip(put(_n_lower, 32.6)));
    upper_confidence_limit = ifc(missing(_n_upper), '', strip(put(_n_upper, 32.6)));
    statistic = ifc(missing(_n_statistic), '', strip(put(_n_statistic, 32.6)));
    p_value = ifc(missing(_n_p_value), '', ifc(_n_p_value lt 0.0001, '<0.0001', strip(put(_n_p_value, 32.4))));
    keep analysis_id tfl_id analysis_group_id analysis_group_label estimand treatment contrast visit estimate standard_error degrees_of_freedom lower_confidence_limit upper_confidence_limit statistic p_value covariance_used;
  run;

/*   实际写出 raw 与 final CSV；文件名逐字来自 contract 的 sas_raw_file 与 sas_final_file。 */
  %write_csv_utf8_bom(data=_raw_export, path=&OUTPUT_DIR/&SAS_RAW_FILE, columns=analysis_id tfl_id analysis_group_id analysis_group_label estimand treatment contrast visit estimate standard_error degrees_of_freedom lower_confidence_limit upper_confidence_limit statistic p_value covariance_used)
  %let RAW_OUTPUT_WRITTEN=1;
  %write_csv_utf8_bom(data=_final_table, path=&OUTPUT_DIR/&SAS_FINAL_FILE, columns=analysis_id tfl_id analysis_group_id analysis_group_label row_type estimand treatment contrast visit observed_n observed_mean observed_sd observed_median observed_min observed_max baseline_n baseline_mean baseline_sd mmrm_estimate standard_error confidence_interval degrees_of_freedom statistic p_value covariance_used)
  %let FINAL_OUTPUT_WRITTEN=1;
  %let RUN_STATUS=complete;
  %put NOTE: 已写出 raw 与 final TFL：&SAS_RAW_FILE / &SAS_FINAL_FILE;
%mend;
%export_tfl_results;

/* =============================================================================
   第 8 部分：诊断信息与运行记录
   ========================================================================== */
/* 本部分写出诊断信息与运行记录。只要程序进入执行路径，这两个文件都会写出，用于审计与排查。 */
/* 本程序只写本 analysis、本语言的运行记录，不写也不修改任何全局 manifest。 */
/* planned（code-generation-only）程序在第 2 部分已正常结束，不会进入本部分，因此不创建任何产物。 */

%macro write_diagnostics_and_run_record;
  %global RUN_STATUS;
  %if &PROGRAM_ACTIVE ne 1 %then %do;
    %put NOTE: 程序未进入执行路径（RUN_STATUS=&RUN_STATUS），不创建任何诊断或运行记录文件。;
    %return;
  %end;
  %local finished risk reason failed_attempts;
  %let finished=%sysfunc(putn(%sysfunc(datetime()),E8601DZ20.));
/*   计算风险由 fallback 使用情况决定：主协方差一次成功为 Green，用到 fallback 为 Yellow，未完成为 Red。 */
  %let failed_attempts=0;
  %if %sysfunc(exist(work._fit_attempts)) %then %do;
    proc sql noprint;
      select count(*) into :failed_attempts trimmed from _fit_attempts where outcome ne 'selected';
    quit;
  %end;
  %if &RUN_STATUS = complete and &failed_attempts = 0 %then %let risk=Green;
  %else %if &RUN_STATUS = complete %then %let risk=Yellow;
  %else %let risk=Red;
  %if &risk = Green %then %let reason=主协方差结构一次成功，推断字段完整。;
  %else %if &risk = Yellow %then %let reason=使用了批准的 fallback 协方差结构或存在需人工复核的情况。;
  %else %let reason=模型或推断未完成，不得把本次结果当作正式 TFL 使用。;
  data _diagnostic_table;
    length study_id $200 analysis_id $200 tfl_id $200 title $400 profile_version $100 programming_language $10
           plan_sha256 $64 approval_payload_sha256 $64 contract_sha256 $64
           dataset_binding_mode $20 dataset_file $400 dataset_format $20
           expected_input_sha256 $64 actual_input_sha256 $64
           covariance_path $2000 selected_covariance $400 convergence_status $20 inference_complete $10
           input_rows $32 population_filtered_rows $32 analysis_rows $32 missing_required_rows $32
           subject_count $32 visit_level_count $32 treatment_level_count $32 derivation_count $32
           qc_group_overlap $32 qc_endpoint_unapproved $32 qc_duplicate_key $32 qc_baseline_inconsistent $32
           qc_treatment_level $32 qc_visit_label $32 qc_error_total $32
           run_status $40 computational_risk $10 risk_reason $400 run_started_utc $40 run_finished_utc $40;
    study_id = "&STUDY_ID";
    analysis_id = "&ANALYSIS_ID";
    tfl_id = "&TFL_ID";
    title = 'Synthetic self-contained analysis "quoted" ''apostrophe'' \backslash ;#% 中文';
    profile_version = "&PROFILE_VERSION";
    programming_language = 'SAS';
    plan_sha256 = "&PLAN_SHA256";
    approval_payload_sha256 = "&APPROVAL_PAYLOAD_SHA256";
    contract_sha256 = "&CONTRACT_SHA256";
    dataset_binding_mode = "&DATASET_BINDING_MODE";
    dataset_file = "&DATASET_FILE";
    dataset_format = "&DATASET_FORMAT";
    expected_input_sha256 = upcase("&EXPECTED_INPUT_SHA256");
    actual_input_sha256 = upcase("&ACTUAL_INPUT_SHA256");
    covariance_path = symget('COVARIANCE_PATH');
    selected_covariance = symget('SELECTED_COVARIANCE');
    if "&MMRM_FIT_SUCCESS" = '1' then convergence_status = 'converged';
    else convergence_status = 'not_converged';
    if "&INFERENCE_COMPLETE" = '1' then inference_complete = 'yes';
    else inference_complete = 'no';
    input_rows = "&INPUT_ROWS";
    population_filtered_rows = "&POPULATION_FILTERED_ROWS";
    analysis_rows = "&ANALYSIS_ROWS";
    missing_required_rows = "&MISSING_REQUIRED_ROWS";
    subject_count = "&SUBJECT_COUNT";
    visit_level_count = "&VISIT_LEVEL_COUNT";
    treatment_level_count = "&TREATMENT_LEVEL_COUNT";
    derivation_count = "&DERIVATION_COUNT";
    qc_group_overlap = "&QC_GROUP_OVERLAP";
    qc_endpoint_unapproved = "&QC_ENDPOINT_UNAPPROVED";
    qc_duplicate_key = "&QC_DUPLICATE_KEY";
    qc_baseline_inconsistent = "&QC_BASELINE_INCONSISTENT";
    qc_treatment_level = "&QC_TREATMENT_LEVEL";
    qc_visit_label = "&QC_VISIT_LABEL";
    qc_error_total = "&QC_ERROR_TOTAL";
    run_status = "&RUN_STATUS";
    computational_risk = "&risk";
    risk_reason = symget('reason');
    run_started_utc = "&RUN_STARTED_UTC";
    run_finished_utc = "&finished";
  run;
  %write_csv_utf8_bom(data=_diagnostic_table, path=&OUTPUT_DIR/&SAS_DIAGNOSTIC_FILE, columns=study_id analysis_id tfl_id title profile_version programming_language plan_sha256 approval_payload_sha256 contract_sha256 dataset_binding_mode dataset_file dataset_format expected_input_sha256 actual_input_sha256 covariance_path selected_covariance convergence_status inference_complete input_rows population_filtered_rows analysis_rows missing_required_rows subject_count visit_level_count treatment_level_count derivation_count qc_group_overlap qc_endpoint_unapproved qc_duplicate_key qc_baseline_inconsistent qc_treatment_level qc_visit_label qc_error_total run_status computational_risk risk_reason run_started_utc run_finished_utc)

  data _run_record_table;
    length study_id $200 analysis_id $200 tfl_id $200 programming_language $10 profile_version $100
           plan_sha256 $64 approval_payload_sha256 $64 contract_sha256 $64 dataset_binding_mode $20
           actual_input_sha256 $64 execution_status $40 run_status $40 computational_risk $10
           raw_output_file $400 final_output_file $400 diagnostic_file $400 run_record_file $400
           run_started_utc $40 run_finished_utc $40;
    study_id = "&STUDY_ID";
    analysis_id = "&ANALYSIS_ID";
    tfl_id = "&TFL_ID";
    programming_language = 'SAS';
    profile_version = "&PROFILE_VERSION";
    plan_sha256 = "&PLAN_SHA256";
    approval_payload_sha256 = "&APPROVAL_PAYLOAD_SHA256";
    contract_sha256 = "&CONTRACT_SHA256";
    dataset_binding_mode = "&DATASET_BINDING_MODE";
    actual_input_sha256 = upcase("&ACTUAL_INPUT_SHA256");
    if "&RUN_STATUS" = 'complete' then execution_status = 'executed';
    else execution_status = 'failed';
    run_status = "&RUN_STATUS";
    computational_risk = "&risk";
    if "&RAW_OUTPUT_WRITTEN" = '1' then raw_output_file = "&SAS_RAW_FILE";
    else raw_output_file = '';
    if "&FINAL_OUTPUT_WRITTEN" = '1' then final_output_file = "&SAS_FINAL_FILE";
    else final_output_file = '';
    diagnostic_file = "&SAS_DIAGNOSTIC_FILE";
    run_record_file = "&SAS_RUN_RECORD_FILE";
    run_started_utc = "&RUN_STARTED_UTC";
    run_finished_utc = "&finished";
  run;
  %write_csv_utf8_bom(data=_run_record_table, path=&OUTPUT_DIR/&SAS_RUN_RECORD_FILE, columns=study_id analysis_id tfl_id programming_language profile_version plan_sha256 approval_payload_sha256 contract_sha256 dataset_binding_mode actual_input_sha256 execution_status run_status computational_risk raw_output_file final_output_file diagnostic_file run_record_file run_started_utc run_finished_utc)

  %put NOTE: 协方差尝试路径：&COVARIANCE_PATH;
  %put NOTE: 选定协方差：&SELECTED_COVARIANCE;
  %put NOTE: 运行状态=&RUN_STATUS；计算风险=&risk;
  %if &RUN_STATUS ne complete %then %do;
    %put ERROR: 本次运行未产生完整的正式 TFL，运行状态=&RUN_STATUS。请阅读诊断文件后处理。;
    %abort cancel;
  %end;
%mend;
%write_diagnostics_and_run_record;
