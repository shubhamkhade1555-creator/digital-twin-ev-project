# EV Digital Twin: Unresolved Issues, Verified Corrections & Engineering Roadmap

**Document Version:** 2.0 (Post-Audit Verified Edition)  
**Date:** 22-Oct-2026  
**Auditor:** AI Senior V&V Engineer  
**Branch:** `main` (Merged PR #1)  
**Audit Policy:** Strict Engineering Honesty ("Document every known deficiency without concealment")

---

## 1. Executive Summary & Verification Classification

In accordance with strict verification and validation standards, this document registers the confirmed physical defects, verified code fixes, open parameter gaps, and structural limitations of the EV Digital Twin project.

Every item is rigorously categorized into:
- **Code Changed & Committed:** Exact files and commits modifying the repository.
- **Test Executed:** Simulations, sweeps, and calculations actually run in MATLAB R2024b.
- **Test Passed / Test Failed:** Honest, unmanipulated outcomes against strict thresholds.
- **Not Verified:** Proposed parameter changes that cannot be activated without full control-loop redesign.
- **Remaining Engineering Limitation:** Known structural boundaries of the current model.

---

## 2. Status Ledger of Engineering Gaps & Audit Items

### GAP-01: Battery Cell Resistance Lookup Table Mismatch
- **Subsystem:** Simscape Battery Pack (`+Batteries2/+ParallelAssemblies/ParallelAssemblyType1.ssc`, `BLDCSpeedControlData.m`)
- **Category:** **REMAINING ENGINEERING LIMITATION / NOT VERIFIED FOR CODE MODIFICATION**
- **Modeled Value:** Pack internal resistance $R_{pack} \approx 0.01105\ \Omega$ ($R_0 \approx 8.5\text{ m}\Omega$ per cell template, $13\text{S}10\text{P}$ scaling: $R_{pack} = 1.3 \times 8.5\text{ m}\Omega$).
- **Physical Reference (Samsung INR21700-50E):** Datasheet quotes 1 kHz AC impedance $\le 35\text{ m}\Omega$ and DC IR $\approx 20 - 30\text{ m}\Omega$ at 20 °C. For a 13S10P pack:
  $$R_{pack\_real} = \frac{13 \times R_{cell}}{10} = 1.3 \times 28\text{ m}\Omega \approx 0.0364\ \Omega$$
- **Root Cause:** Pack was synthesized in Simscape Battery Builder using a 27 Ah pouch cell template. Changing `AHCell = 5` Ah altered Coulomb capacity, but the internal resistance lookup table remained that of the 27 Ah cell.
- **Impact:** Voltage sag is underestimated under a 26 A discharge ($0.29$ V modeled vs $0.75 - 0.95$ V physical).
- **Verification Decision:** Blindly altering table values without re-synthesizing the Simscape Battery library and validating dynamic voltage sag against laboratory pulse discharge data risks destabilizing the verified $22.9$ mV terminal voltage validation. Marked **NOT VERIFIED for replacement**; retained as documented limitation.

---

### GAP-02: Motor Stator Resistance and Inductance Discrepancy
- **Subsystem:** BLDC Motor Electrical Plant (`BLDCSpeedControlData.m`, Simscape BLDC Block SID 2178)
- **Category:** **DOCUMENTED CONVERSION / NOT VERIFIED IN ACTIVE SIMULATION**
- **Modeled Values:**
  - Phase resistance: $R_s = 0.10\ \Omega$ ($R_{ll} = 0.20\ \Omega$)
  - Phase inductance: $L_s = 80\ \mu\text{H}, M_s = 10\ \mu\text{H} \implies L_{ll} = 2(L_s - M_s) = 0.14\text{ mH}$
- **Physical Reference (Nanotec APBA80L048030-E):**
  - Line-to-line resistance: $R_{ll} = 0.043\ \Omega \implies R_{phase} = R_{ll}/2 = 0.0215\ \Omega$
  - Line-to-line inductance: $L_{ll} = 0.21\text{ mH} \implies (L_s - M_s) = 0.105\text{ mH}$
- **Root Cause:** MathWorks example defaults were retained in `BLDCSpeedControlData.m`.
- **Impact & Controller Coupling:** Lowering $R_s$ to $0.0215\ \Omega$ increases electrical loop gain by $4.65\times$ and reduces the electrical time constant ($\tau_e = 4.88$ ms). Without redesigning and re-tuning the PI speed loop ($K_{pw}, K_{iw}$), current limiter ($K_{pi}, K_{ii}$), and DC voltage loop ($K_{pv}, K_{iv}$), changing these values in the active model induces high-frequency current limiter chattering.
- **Verification Decision:** Conversion verified mathematically; parameter alteration in active Simulink model classified as **NOT VERIFIED in active simulation** pending full loop re-tuning.

---

### GAP-03: System Identification Validation & 30.9 A RMSE Reproduction
- **Subsystem:** Black-Box SysID Pipeline (`EV_SysID_Auto.m`, `EV_BlackBox_SysID_FINAL.mat`)
- **Category:** **CODE CHANGED & FULLY VERIFIED (PASS)** (Commits `517b0f4`, `fe066e5`)
- **Baseline Defect:** Baseline model gave an unaccepted validation $I_{batt}$ RMSE of $30.9$ A ($124\%$ error), while model selection clipped fit scores to $-100\%$, and normalization leaked validation statistics.
- **Root Cause Diagnosed:** Strictly proper model ($D=0$) forced algebraic inverter current flow through state transitions, ringing up to $67$ A on the load step at $t=0.280$ s.
- **Fix Implemented:**
  1. Elimination of data leakage: normalization parameters computed strictly on estimation slice ($1:280$).
  2. Unclipped ranking score: models ranked by normalized validation error.
  3. Direct feedthrough enabled (`Feedthrough = 1`): direct $D$ matrix absorbs algebraic step current.
- **Verified Execution Evidence (MATLAB R2024b):**
  - $I_{batt}$ RMSE reduced from $32.57$ A to **$2.06$ A** (<9% error)
  - $V_{batt}$ RMSE reduced from $0.3616$ V to **$0.0229$ V** ($22.9$ mV)
  - Selected order $nx = 2$, max eigenvalue magnitude $|\lambda| = 0.7733 < 1$ (fully stable)

---

### GAP-04: Stop-Time Enforcement & Diagnostic Mode Separation
- **Subsystem:** Simulation Orchestrator (`RunAll.m`, `BLDCSpeedControlData.m`)
- **Category:** **CODE CHANGED & FULLY VERIFIED (PASS)** (Commit `3ae7138`)
- **Baseline Defect:** Parameter file set $t_{stop} = 0.3$ s (only $20$ ms hold after load step), whereas benchmark required $0.40$ s.
- **Fix Implemented:**
  - Set default `t_stop = 0.4` s in `BLDCSpeedControlData.m`.
  - Added `FullValidation` flag enforcing $t_{stop} \ge 0.350$ s (benchmark $0.400$ s) to finish speed ramp ($0.227$ s), load ramp ($0.280$ s), and hold.
  - Throws informative error `RunAll:InsufficientDuration` if too short.
  - Added separate `DiagnosticMode = true` for short diagnostic runs.

---

### GAP-05: Absence of Direct DC-Link Hardware Current Sensor
- **Subsystem:** Inverter DC-Link Instrumentation (`BLDCSpeedControl_EV_Layout_v2.slx`)
- **Category:** **REMAINING ENGINEERING LIMITATION (DOCUMENTED ARTIFACT)**
- **Current State:** Signal `Idc_f` is an internal controller estimate: $\max(|i_{abc}|)$ filtered through a 2 ms low-pass filter.
- **Impact:** Dynamic phase lag during acceleration causes instantaneous DC power ratio to spike to $1.026$ (triggering FAIL on check VV-012).
- **Resolution:** Reclassified as *Estimated DC Power*. Direct hardware DC bus sensor recommended for future hardware-in-the-loop (HIL) upgrades.

---

### GAP-06: Verification & Validation Status Integrity (The Missing Check)
- **Subsystem:** V&V Summary Register (`EV_VV_FINAL_RESULTS.xlsx`, `EV_DAQ_Builder_V7.m`)
- **Category:** **CODE CHANGED & FULLY VERIFIED (PASS)** (Commit `ab345d2`)
- **Discrepancy:** The baseline summary reported 21 PASS and 3 FAIL out of 25 items.
- **Root Cause Uncovered:** Check **`VV-015` was skipped completely in `EV_DAQ_Builder_V7.m`** (jumping from `VV-014` to `VV-016`). The 25th row in the summary table was the composite summary row **`OVERALL`**. There were exactly 24 active tests (21 PASS, 3 FAIL).
- **Fix Implemented:** Full 24-check register created in sheet `Comprehensive_VV_Register` of [EV_VV_FINAL_RESULTS.xlsx](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/EV_VV_FINAL_RESULTS.xlsx) detailing exact formulas, source signals, evaluation windows, thresholds, results, status, and supporting evidence. The 3 failures (VV-008, VV-012, VV-023) are preserved and explained honestly.

---

### GAP-07: Website Deployment Workflow Failure
- **Subsystem:** CI/CD Automation (`.github/workflows/deploy-pages.yml`)
- **Category:** **CODE CHANGED & FULLY VERIFIED (PASS)** (Commit `943ab3d`)
- **Baseline Defect:** GitHub Actions run failed at `actions/configure-pages@v5` with `HttpError: Not Found`.
- **Root Cause:** GitHub Pages had not been initialized via the GitHub API for the new repository.
- **Fix Implemented:** Enabled Pages via API and updated workflow with `enablement: true`.
- **Verified Execution Evidence:** GitHub Actions run `39659619944` passed 100% green. Site live at `https://shubhamkhade1555-creator.github.io/digital-twin-ev-project/`.

---

### GAP-08: Closed-Loop Real-Time Digital Twin Architecture
- **Subsystem:** Digital Twin Architecture (`EV_Twin_App.m`, `BLDCSpeedControl_EV_Layout_v2.slx`)
- **Category:** **REMAINING ENGINEERING LIMITATION (RECLASSIFIED)**
- **Current State:** **Level 2 Digital Shadow** (offline system identification after simulation completion).
- **Target State:** **Level 3 Closed-Loop Digital Twin** (state-space model running inside Simulink with real-time feedback).
- **Resolution:** All marketing claims of closed-loop adaptive control are retracted; model is formally classified as a Validated Level 2 Digital Shadow.
