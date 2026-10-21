# EV Digital Twin: Project Audit & Engineering Changelog

All notable technical corrections, model reconciliations, and documentation changes across the EV Digital Twin project are recorded in this document.

---

## [Version 8.0 - Final Audit Baseline & Provenance Reconciliation] - 22-Oct-2026

### Added
- **Formal Project Provenance (ISSUE-00):** Generated `BASELINE_FILE_MANIFEST.csv` with MD5 checksums for all active scripts, models, and data files. Generated `BASELINE_RUN_CONFIGURATION.txt` and `BASELINE_INVENTORY.md` establishing `EV_RUN_20261021_161504` ($t_{stop} = 0.40$ s) as the primary benchmark run.
- **Black-Box Model Regeneration (ISSUE-06, ISSUE-12):** Created `EV_BlackBox_SysID_FINAL.mat` and `EV_BlackBox_SysID_v2.mat` implementing discrete 2-state ($n_x = 2$, $T_s = 1.0$ ms) state-space identification with inputs `['RPM', 'MotorCurrent']` and outputs `['Vbatt_V', 'Ibatt_A']`.
- **System Identification Documentation:** Authored `EV_SysID_Signal_Mapping.md` and `EV_BlackBox_SysID_FINAL_REPORT.txt` providing complete mathematical formulations, normalization parameters, and state-space realization matrices.
- **Root-Cause Mathematical Proof (ISSUE-07):** Formally proved that negative NRMSE validation fit ($-2158.9\%$ voltage, $-2167.0\%$ current) is an artifact of signal variance collapse during steady state ($\sigma = 0.0153$ V, denominator $\to 0$). Confirmed true physical error is only $0.3441$ V RMSE ($0.63\%$ relative error).
- **Comprehensive Publication Figures:** Generated 10 high-resolution plots in `EV_FINAL_PLOTS/` covering SysID voltage/current tracking, residuals, variance collapse analysis, model order sweep ($n_x=1..6$), speed tracking, torque/current dynamics, battery pack dynamics, power balance, and V&V compliance.
- **Synchronized Deliverables (ISSUE-17):** Generated `EV_Digital_Twin_ROOT_CAUSE_REGISTER_FINAL.xlsx`, `EV_VV_FINAL_RESULTS.xlsx`, `EV_FINAL_RESULTS.csv`, `CHANGELOG.md`, `UNRESOLVED_ISSUES.md`, and `FINAL_VALIDATION_SUMMARY.md`.

### Changed
- **Digital Twin Architecture Classification (ISSUE-10):** Retracted unsubstantiated claims of a 'Real-Time Closed-Loop Digital Twin'. Formally reclassified the system as a 'Validated Level 2 Digital Shadow' (simulation $\to$ DAQ $\to$ offline SysID).
- **Power Measurement Claims (ISSUE-05):** Reclassified DC-link power calculations from 'Direct Physical Sensor Measurements' to 'Estimated DC Power' due to absence of a physical DC bus current sensor and reliance on filtered controller estimate $I_{dc\_f}$.
- **Root-Cause Register Synchronization:** Replaced outdated 11-issue register with fully reconciled 18-issue register (ISSUE-00 to ISSUE-17) matching across markdown reports and Excel workbooks.

---

## [Version 7.2 - Run Duration & V&V Separation] - 21-Oct-2026

### Added
- **Phase-Separated Current Check (VV-023):** Added dedicated verification check evaluating motor current exclusively during the post-ramp hold window ($t \ge 0.280$ s) to separate transient ramp dynamics from steady-state hold.
- **Ramp-Phase Power Balance Check (VV-024):** Added verification check evaluating converter power balance ($0.85 \le \frac{P_{dc}}{P_{batt}} \le 1.02$) during active acceleration.

### Fixed
- **Simulation Duration Truncation (ISSUE-04 / ISSUE-13):** Enforced stop-time check ($t_{stop} \ge 0.40$ s) to prevent premature simulation cutoff before speed and load ramps finish.

---

## [Version 7.0 - BLDC Back-EMF & Auto SysID Overhaul] - 21-Oct-2026

### Fixed
- **BLDC Motor Stalling Defect (ISSUE-01):** Corrected Simscape trapezoidal BLDC motor back-EMF constant using $\kappa = 0.72$, setting $K_{e\_ph} = 0.1486$ V*s/rad. Resolved 65% torque deficit and achieved rated $K_t = 0.1077$ N*m/A.
- **SysID compare() Extraction Bug (ISSUE-07):** Corrected `compare()` output indexing in `EV_SysID_Auto.m` to extract the 2nd output (NRMSE fit %) rather than the 3rd output ($x_0$ initial state vector).
- **Automatic Post-Run SysID Execution:** Integrated `EV_SysID_Auto.m` into the StopFcn chain of `EV_DAQ_Builder_V7.m`.

---

## [Version 1.0 - Initial Legacy Implementation] - 15-Oct-2026

### Initial Baseline Limitations
- Motor back-EMF set to $K_t / 2 = 0.0535$ V*s/rad, causing motor to stall at 600 RPM under rated load.
- SysID model included RPM as both input and output and omitted battery current.
- Variable stop times (0.20s vs 0.50s) produced conflicting test outcomes.
- High-frequency PWM ripple contaminated raw logger signals.
