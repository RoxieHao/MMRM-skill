# Standard MMRM collector 运行汇总

- 运行模式：`run-and-collect`
- Profile：`standard-mmrm-profile/v1`
- 程序运行顺序（R 程序文件名升序）：`MMRM-01.R, MMRM-02.R, MMRM-03.R, MMRM-04.R, MMRM-05.R`
- Collector 从不执行 SAS：SAS 只作为代码交付物。

| Analysis ID | TFL ID | 语言 | Binding | Execution status | Run status | Final TFL |
|---|---|---|---|---|---|---|
| `MMRM-01` | `T14-2-10-1-2` | `R` | `linked` | `executed` | `complete` | `studies/fcn_159_002_luna/output/analyses/MMRM-01/T14-2-10-1-2_r_final.csv` |
| `MMRM-01` | `T14-2-10-1-2` | `SAS` | `linked` | `program_generated_not_executed` | `not_run` | `` |
| `MMRM-02` | `T14-2-11-2` | `R` | `linked` | `executed` | `complete` | `studies/fcn_159_002_luna/output/analyses/MMRM-02/T14-2-11-2_r_final.csv` |
| `MMRM-02` | `T14-2-11-2` | `SAS` | `linked` | `program_generated_not_executed` | `not_run` | `` |
| `MMRM-03` | `T14-2-12-1-2` | `R` | `linked` | `executed` | `complete` | `studies/fcn_159_002_luna/output/analyses/MMRM-03/T14-2-12-1-2_r_final.csv` |
| `MMRM-03` | `T14-2-12-1-2` | `SAS` | `linked` | `program_generated_not_executed` | `not_run` | `` |
| `MMRM-04` | `T14-2-13-1-2` | `R` | `linked` | `failed` | `fit_failed` | `` |
| `MMRM-04` | `T14-2-13-1-2` | `SAS` | `linked` | `program_generated_not_executed` | `not_run` | `` |
| `MMRM-05` | `T14-2-14-1-2` | `R` | `linked` | `blocked` | `unknown` | `` |
| `MMRM-05` | `T14-2-14-1-2` | `SAS` | `linked` | `program_generated_not_executed` | `not_run` | `` |
