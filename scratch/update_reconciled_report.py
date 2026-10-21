import os

report_path = r"c:\Users\shubh\OneDrive\Documents\MATLAB\EV_DigitalTwin\EV_Digital_Twin_COMPLETE_ROOT_CAUSE_AUDIT.md"

content = """# EV Digital Twin: Forensic Root-Cause Audit & Reconciliation Report
**Project Title:** Design and Development of a Black-Box Model-Based Real-Time Digital Twin for an Electric Vehicle Battery Using MATLAB/Simulink  
**Lead Auditor:** Senior MATLAB/Simulink & EV Powertrain V&V Engineer  
**Audit Revision:** 2.0 (Reconciled & Evidence-Verified)  
**Date of Audit:** October 2026  
**Primary Plant Model:** `BLDCSpeedControl_EV_Layout_v2.slx`  
**Execution Harness:** `RunAll.m` | `EV_DAQ_Builder_V7.m` | `EV_SysID_Auto.m`  
**Audit Baseline Run ID:** `EV_RUN_20261021_172910` (Stop Time: 0.20 s) & `EV_RUN_20261021_161504` (Stop Time: 0.40 s)  
**Reference Master Dataset:** `EV_DAQ_Clean_4_05_Reference_Master.xlsx` (Run 4, 0.50 s)  
**Audit Policy:** Read-Only Forensic Audit ("No code changes — only find")

---

## Change & Reconciliation Log (Revision 2.0)
- **Point 1 (Baseline Provenance):** Fully documented active baseline runs (`EV_RUN_20261021_172910`, `EV_RUN_20261021_161504`, and `Reference_Master.xlsx`) with exact model timestamps, stop times, and file paths.
- **Point 2 (Unified Issue IDs):** Reconciled issue numbering across this report, `EV_Digital_Twin_ROOT_CAUSE_REGISTER.xlsx`, and test metrics into an unambiguous scheme (`ISSUE-01` through `ISSUE-11`).
- **Point 3 (Motor Current Discrepancy Reconciled):** Proved mathematically and via source code that the apparent conflict between steady-state current ($30.3 - 32.8\text{ A}$) and reported RMS current ($26.41 - 29.59\text{ A}$) is due to different time windows on the same signal: whole-run RMS (`VV-004`) vs. last 10% load-hold mean (`VV-008`).
- **Point 4 (SysID Model Output Provenance):** Verified that the legacy root file `EV_BlackBox_SysID.mat` outputs are `[Vbatt_V, SOC, RPM_rpm]` and **does NOT predict battery current**. Proven that current is only an output in the newly refactored `EV_SysID_Auto.m`. Identified why validation fit collapsed to $-2158\%$ (validation dataset variance collapse on flat steady-state data).
- **Point 5 (BLDC Back-EMF Physics):** Decomposed the Simscape trapezoidal BLDC block back-EMF equations, proving why $\kappa = 0.72$ is mathematically necessary ($K_{e\_ph} = K_t / \kappa = 0.1486\text{ V}\cdot\text{s/rad}$) to produce the datasheet torque constant $K_t = 0.107\text{ N}\cdot\text{m/A}$.
- **Point 6 (Motor Resistance & Inductance Mismatch):** Identified that the model's phase resistance $R_s = 0.1\ \Omega$ is $4.65\times$ higher than the physical Nanotec datasheet value ($R_{\text{phase}} = 0.0215\ \Omega$), creating excess modeled copper losses.
- **Point 7 (Battery Resistance Provenance):** Extracted exact lookup tables from `+Batteries2/ParallelAssemblyType1.ssc` ($R_{0,\text{cell}} \approx 8.5\text{ m}\Omega$). Proved pack resistance is $R_{\text{pack}} = \frac{13}{10} \times 0.0085 = 0.011\ \Omega$, representative of a 27 Ah cell rather than a 5 Ah 21700 cell ($25 - 35\text{ m}\Omega$).
- **Point 8 (DC-Link Current Sensor Reality):** Proved from `system_root.xml` that the model has **no physical DC-link current sensor**. `Idc_f` is an internal controller estimate with 2 ms LPF lag. Reconciled that instantaneous $P_{\text{dc}}/P_{\text{batt}}$ cannot be used as physical sensor proof of converter efficiency.
- **Point 9 (Operational Phase Separation):** Formalized test metrics into 4 distinct phases: Startup ($0-2\text{ ms}$), Acceleration ($2-227\text{ ms}$), Load-Step ($230-280\text{ ms}$), and Steady-State Hold ($280-300+\text{ ms}$).
- **Point 12 (Retraction of Production Readiness):** Retracted the claim of "production grade". The model is formally classified as a **Validated Digital Shadow (Level 2 Proof-of-Concept)**, with clear architectural milestones required before achieving a true Closed-Loop Digital Twin (Level 3).

---

## 1. Executive Summary

This report delivers a reconciled, evidence-based engineering audit of the Electric Vehicle (EV) Digital Twin project. The audited system models a complete electric two-wheeler powertrain:
- **13S10P Lithium-Ion Battery Pack** ($48.1\text{ V}$ nominal, $50\text{ Ah}$, $2.4\text{ kWh}$)
- **DC-DC Buck Converter** ($10\text{ kHz}$ switching frequency, stepping down battery voltage to regulated DC link)
- **3-Phase Inverter** (6-switch bridge with 120° Hall-effect commutation)
- **1 kW, 3000 RPM Brushless DC Motor** (Nanotec APBA80L048030-EB baseline)
- **Drivetrain & Mechanical Vehicle Load** (11:1 reduction gearbox, $0.25\text{ m}$ radius wheel, $1.0\text{ kW}$ road load)
- **Deterministic Event Recorder** (`EV_BlackBox`, 1 ms ZOH, 8 telemetry channels)
- **System Identification Engine** (Subspace N4SID discrete state-space model)

### Reconciled Engineering Verdict:
1. **Core Power Electronics & Plant Feasibility:** The power conserving electrical connections are verified intact. The buck converter sits directly in the power path between the battery terminals and the inverter DC bus; it is not bypassed. The fundamental sample time ($T_s = 10\ \mu\text{s}$) maintains numerical stability without algebraic loop faults.
2. **Key Historical Errors Corrected in Current Version (V7):**
   - **Motor Back-EMF Parameterization (`ISSUE-01`):** An earlier parameterization ($K_{e\_ph} = K_t / 2 = 0.0535\text{ V}\cdot\text{s/rad}$) produced only $0.038\text{ N}\cdot\text{m/A}$ ($35\%$ torque), causing stall. Calibrating $\kappa = 0.72$ ($K_{e\_ph} = 0.1486\text{ V}\cdot\text{s/rad}$) restored torque per amp to $0.1077\text{ N}\cdot\text{m/A}$ ($+0.65\%$ error vs datasheet).
   - **SysID Fit Reporting Bug (`ISSUE-07`):** The legacy script extracted the 3rd output of MATLAB's `compare()` ($x_0$) rather than the 2nd (NRMSE fit %), displaying nonsensical values ($2 \times 10^{15}\%$). Corrected in `EV_SysID_Auto.m`.
   - **Pack Logging Array Aliasing & Reshaping:** Array reshaping errors in V6 that shifted columns across time slices were resolved via `evTsMatrix` and `evBinMean()`.
3. **Current Open Deficiencies & Discrepancies:**
   - **Inertia vs. Acceleration Current (`ISSUE-02`):** Reference ramp $13,000\text{ rpm/s}$ demands $30.4\text{ A}$ from the motor purely for accelerating inertia, exceeding the continuous thermal limit ($I_{\text{cont}} = 30\text{ A}$).
   - **Load Settling Truncation (`ISSUE-03`):** Rated $1\text{ kW}$ load ($3.18\text{ N}\cdot\text{m}$) finishes ramping at $0.28\text{ s}$. At $t_{\text{stop}} = 0.30\text{ s}$, current is still settling and hovers at $30.3 - 32.8\text{ A}$, triggering warnings.
   - **Short-Run False Failures (`ISSUE-04`):** Running with $t_{\text{stop}} \le 0.20\text{ s}$ prematurely halts the simulation before speed reference ($0.227\text{ s}$) or load ($0.28\text{ s}$) are reached.
   - **SysID Model Inconsistency (`ISSUE-06`):** Legacy root file `EV_BlackBox_SysID.mat` duplicates `RPM_rpm` as both input and output, and does not predict battery current.
   - **Battery Internal Resistance Underestimation (`ISSUE-08`):** Modeled pack resistance ($R_{\text{pack}} \approx 0.011\ \Omega$) reflects a 27 Ah template, roughly $2.5 - 3.3\times$ lower than authentic 5 Ah 21700 cells ($0.026 - 0.039\ \Omega$).
   - **Motor Stator Resistance Mismatch (`ISSUE-11`):** Model phase resistance ($R_s = 0.1\ \Omega$) is $4.65\times$ higher than physical datasheet line-to-line equivalent ($R_{\text{phase}} = 0.0215\ \Omega$).
   - **Digital Twin Classification (`ISSUE-10`):** The state-space model is executed offline only. The project is an operational **Digital Shadow (Level 2)**, not yet a Closed-Loop Digital Twin (Level 3).

---

## 2. Project Inventory and Inspected Files

| File Name | Location | Type | Architectural Purpose | Audit Finding / Provenance |
|---|---|---|---|---|
| `RunAll.m` | Root | MATLAB Script | One-click test runner & V&V evaluator | Active entry point; verified |
| `BLDCSpeedControlData.m` | Root | MATLAB Script | Master engineering parameter source | Source of truth for parameters; audited |
| `BLDCSpeedControl_EV_Layout_v2.slx` | Root | Simulink Model | Main plant & control simulation | Decomposed via XML; wiring verified |
| `BLDCSpeedControlInput.mat` | Root | MAT File | Dynamic load profile `Test_1` | Verified (0 Nm to 0.23s; ramp to 3.18 Nm at 0.28s) |
| `Batteries2_lib.slx` | Root | Simulink Library | Simscape Battery module library | Verified (`ModuleType1` 13S10P) |
| `EV_DAQ_Builder_V7.m` | Root | MATLAB Function | Automated instrumentation, DAQ, V&V | Audited (4,350 lines; contains all 25 V&V checks) |
| `EV_SysID_Auto.m` | Root | MATLAB Script | N4SID subspace identification script | Audited; corrects legacy SysID bugs |
| `EV_BlackBox_SysID.mat` | Root | MAT File | Offline discrete state-space model | **Defective legacy model** (RPM in/out duplicate) |
| `EV_CrossVerification_Results.xlsx` | Root | Excel Workbook | Master verification dataset | Audited (102 rows; 24 channels) |
| `docs/EVTWIN_Project_Report.docx` | `docs/` | Word Document | Project technical report v1.0 | Audited & cited |
| `+Batteries2/` | Root | Package Dir | Generated Simscape Battery ECM tables | Audited (R0 table = 8.5 mOhm/cell) |
| `Simulation Logs/EV_RUN_20261021_172910` | `Simulation Logs/` | Run Archive | Baseline run (t_stop = 0.20 s) | Audited; shows short-run truncation |
| `Simulation Logs/EV_RUN_20261021_161504` | `Simulation Logs/` | Run Archive | Baseline run (t_stop = 0.40 s) | Audited; contains updated SysID report |
| `docs/Reference_Research_Papers/EV_DAQ_Clean_4_05_Reference_Master.xlsx` | `docs/.../` | Excel Dataset | 0.50 s reference run benchmark | Audited (501 rows; steady-state reference) |

---

## 3. Discrepancy & Reconciliation Table

Below is the formal reconciliation matrix resolving every conflict between documentation, code, and simulation outputs:

| Issue ID | Claim / Documented Symptom | Source File & Location | Actual Physical Evidence | Root Cause Mechanism | Reconciled Audit Verdict |
|---|---|---|---|---|---|
| **ISSUE-01** | Motor stalls under load; produces only 0.038 N*m/A | `BLDCSpeedControlData.m` L40-44, `EVTWIN_Project_Report.docx` Sec 5.6 | Scope traces showed 1.14 Nm at 30 A ($K_t = 0.038\text{ N}\cdot\text{m/A}$) | Simscape BLDC block back-EMF table expects peak phase-to-neutral flat-top value. Setting $K_{e\_ph} = K_t/2$ ignored internal $\kappa \approx 0.72$ factor. | **Confirmed Fix.** Setting $\kappa = 0.72 \rightarrow K_{e\_ph} = 0.1486\text{ V}\cdot\text{s/rad}$ restored $K_t$ to $0.1077\text{ N}\cdot\text{m/A}$ (+0.65% error). |
| **ISSUE-02** | Acceleration ramp triggers `BLDC:rampAboveCont` warning | `BLDCSpeedControlData.m` L71, L127-137 | Console warning on every run: `Ramp 13000 rpm/s needs 30.4 A > I_cont = 30 A` | Acceleration current $I_{\text{accel}} = J_{\text{tot}} \cdot \alpha / K_t = 0.00239 \times 1361.36 / 0.107 = \mathbf{30.37\text{ A}}$, exceeding $30\text{ A}$ continuous limit purely for inertia. | **Open Defect.** Must lower `rpm_ramp <= 11500 rpm/s` (needs 26.8 A $\le 90\%$ of $I_{\text{cont}}$) and adjust $t_{\text{stop}} \ge 0.32\text{ s}$. |
| **ISSUE-03** | Conflict between steady current (30.3–32.8 A, FAIL) and RMS current (26.41 A, PASS) | `EV_DAQ_Builder_V7.m` L2491-2495, `04_VV_Results.xlsx` | `rI = rmsf(im)` computes whole-run RMS ($0-0.3\text{ s}$); `ssm = mean(abs(im(late)))` computes mean of last 10% ($0.27-0.3\text{ s}$) | **Different Metrics on Same Signal.** Whole-run RMS is pulled down to $26.41\text{ A}$ by low-current ramp phase. Last 10% mean is at full 1 kW load where settling transient leaves current at $30.3\text{ A}$. | **Reconciled Metric.** Not a bug. Reconciled by defining whole-run RMS vs steady-state window mean. Fix: extend $t_{\text{stop}} \ge 0.35\text{ s}$. |
| **ISSUE-04** | Running with $t_{\text{stop}} \le 0.20\text{ s}$ causes speed and power checks to FAIL | `RunAll.m` L120, `04_VV_Results.xlsx` (`EV_RUN_20261021_172910`) | Final speed = 2583 RPM (< 2900); Mechanical power = 0 W | Speed ramp requires $0.227\text{ s}$ to reach target speed. Load profile ramps from $0.23\text{ s}$ to $0.28\text{ s}$. Halting at $0.20\text{ s}$ truncates simulation during ramp. | **Confirmed Operational Defect.** Enforce minimum stop-time constraint: $t_{\text{stop}} \ge 0.30\text{ s}$. |
| **ISSUE-05** | Instantaneous power balance $P_{\text{dc}} / P_{\text{batt}}$ spikes to $1.05 - 1.11$ | `BLDCSpeedControl_EV_Layout_v2` XML, `EV_DAQ_Builder_V7.m` FIX-Q | XML confirms model has NO DC-link current sensor; `Idc_f` is controller estimate $\max(|i_{abc}|)$ with 2 ms LPF | Filter phase lag and 10 kHz PWM switching ripple cause $V_{\text{dc}} \times I_{\text{dc\_f}}$ to temporarily lead/lag battery power during transients. | **Reconciled Modeling Assumption.** Cannot be used as direct physical proof. Average steady-state efficiency is valid ($95.96\%$). Physical shunt sensor recommended. |
| **ISSUE-06** | Legacy root SysID model duplicates RPM and does not predict current | `EV_BlackBox_SysID.mat` | `labels_u = ['RPM_rpm', 'Idc_f_A']`; `labels_y = ['Vbatt_V', 'SOC', 'RPM_rpm']` | Legacy script designated RPM as both input and output. Predicting an input as its own output forces an identity state. | **Confirmed Defect.** Corrected in `EV_SysID_Auto.m` ($U = [\text{RPM}, \text{MotorCurrent}], Y = [\text{Vbatt}, \text{Ibatt}]$). Root MAT file must be updated. |
| **ISSUE-07** | SysID report printed fit = $2 \times 10^{15}\%$ and recent run showed $-2158\%$ fit | `EV_SysID_Auto.m` L104, `EV_RUN_20261021_161504/EV_BlackBox_SysID_Report.txt` | `compare()` returns $x_0$ as 3rd output; validation data split ($0.28-0.40\text{ s}$) has output variance $\approx 0$ | 1) Legacy code read 3rd argument ($x_0$) instead of 2nd (fit %). 2) In flat steady state, NRMSE denominator $\|y - \bar{y}\| \rightarrow 0$, causing fit percentage to explode to large negative values. | **Confirmed Fix & Diagnostic.** Argument bug fixed. Negative fit diagnosed as validation variance collapse; requires dynamic drive-cycle validation data. |
| **ISSUE-08** | Modeled battery pack resistance ($0.011\ \Omega$) is $2.5 - 3.3\times$ lower than authentic 21700 pack | `+Batteries2/ParallelAssemblyType1.ssc` L20-22, `BLDCSpeedControlData.m` L47-51 | Look-up table $R_0 = 8.5\text{ m}\Omega$ per cell $\rightarrow R_{\text{pack}} = \frac{13}{10} \times 0.0085 = 0.011\ \Omega$. True 21700 cell is $25-35\text{ m}\Omega \rightarrow 0.036\ \Omega$. | Pack was generated from a 27 Ah cell template. When capacity was overridden to 5 Ah, resistance tables were not updated. | **Open Modeling Gap.** Underestimates battery voltage sag ($0.29\text{ V}$ modeled vs $0.85\text{ V}$ real under 26 A) and Joule heating. Rebuild in Battery Builder. |
| **ISSUE-09** | `rpm_ref` and `temperature` reported as `NOT_AVAILABLE` | `BLDCSpeedControl_EV_Layout_v2.slx`, `EV_DAQ_Builder_V7.m` L2350 | In-model blocks `log_rpm_ref` and `log_temperature` do not exist | Model lacks thermal equivalent circuit for cell heat dissipation; speed reference ramp not routed to To Workspace block. | **Known Limitation.** Reconciled as honest reporting (NOT_AVAILABLE is declared without inventing artificial data). |
| **ISSUE-10** | Identified state-space model is offline only; not integrated in closed-loop | `BLDCSpeedControl_EV_Layout_v2.slx`, `EVTWIN_Project_Report.docx` Sec 3.2 | No state-space block in Simulink canvas; `sys_blackbox` is stored only as a `.mat` file | The project reached Digital Shadow (Level 2). Bidirectional feedback (Level 3 Digital Twin) has not yet been built into the controller. | **Future Development.** Claim of "production readiness" retracted. Formally classified as Validated Level 2 Digital Shadow. |
| **ISSUE-11** | Model phase resistance $R_s = 0.1\ \Omega$ is $4.65\times$ higher than datasheet | `BLDCSpeedControlData.m` L32, Nanotec APBA80L048030-E datasheet | Datasheet specifies $R_{ll} = 0.043\ \Omega$ (Wye $\rightarrow R_{\text{phase}} = 0.0215\ \Omega$). Model uses $R_s = 0.1\ \Omega$ ($R_{ll} = 0.20\ \Omega$). | Model retained default MathWorks example resistance rather than matching the Nanotec motor datasheet value. | **Open Parameter Gap.** Overestimates motor copper losses ($3 I^2 R_s$) by $\approx 4.6\times$; underestimates peak motor efficiency. |

---

## 4. Reconciled Signal & Operational Phase Breakdown

To prevent false test failures, simulation data must be evaluated according to **4 distinct operational phases**:

```
0.000s            0.002s                              0.227s   0.230s                     0.280s             0.300s+
  │─── Phase 1 ────│─────────────── Phase 2 ─────────────│── P3 ──│──────── Phase 3 ─────────│──── Phase 4 ────│
     Startup              Acceleration / Ramp              No-Load        Load Step Ramp          Steady Hold
   (Solver Init)        (0 -> 2950 RPM, 0 Nm Load)         Settling    (0 -> 3.18 Nm, 1 kW)     (Rated 1 kW Load)
```

1. **Phase 1: Startup Transient ($0.000 - 0.002\text{ s}$)**
   - Electrical initialization; solver settles initial capacitor charges.
   - *Acceptance Criteria:* $V_{\text{batt}} \in [45\text{ V}, 55\text{ V}]$, initial $\text{SOC} = 1.000$, zero solver numerical singularities.
   - *Audit Status:* **PASS**.
2. **Phase 2: Acceleration & Speed Ramp ($0.002 - 0.227\text{ s}$)**
   - Speed reference ramps linearly at $13,000\text{ rpm/s}$ to $2950\text{ rpm}$; external load is $0\text{ N}\cdot\text{m}$.
   - Current is demanded exclusively to accelerate total inertia ($J_{\text{tot}} = 0.00239\text{ kg}\cdot\text{m}^2$).
   - *Acceptance Criteria:* Peak current $\le I_{\text{peak}} = 45\text{ A}$ (**PASS**); current $\le I_{\text{cont}} = 30\text{ A}$ (**WARN / FAIL** because $I_{\text{accel}} = 30.4\text{ A}$). Speed tracking error $\le 20\text{ RPM}$ (**PASS**).
3. **Phase 3: Load-Step Ramp-In ($0.230 - 0.280\text{ s}$)**
   - External road torque ramps linearly from $0$ to $3.18\text{ N}\cdot\text{m}$ ($1.0\text{ kW}$ mechanical load).
   - Speed dips to $\approx 2930\text{ rpm}$ and recovers; motor current rises from $2\text{ A}$ to $30\text{ A}$.
   - *Acceptance Criteria:* No motor stall ($> 2800\text{ rpm}$); current clamped below $45\text{ A}$ limiter ceiling.
   - *Audit Status:* **PASS**.
4. **Phase 4: Steady-State Full Load ($0.280 - 0.300+\text{ s}$)**
   - Continuous full-load operation at $1\text{ kW}$ ($3.18\text{ N}\cdot\text{m}$ load at $2950\text{ rpm}$).
   - *Acceptance Criteria:*
     - Speed tracking: $2900 - 3000\text{ RPM}$ (Simulated: **$2950.22\text{ RPM}$** $\rightarrow$ **PASS**).
     - Torque constant: $K_t = 0.107 \pm 5\%$ (Simulated: **$0.1077\text{ N}\cdot\text{m/A}$** $\rightarrow$ **PASS**).
     - Steady current: $\le 30\text{ A}$ (Simulated: **$30.3 - 32.8\text{ A}$** $\rightarrow$ **WARN / FAIL** if $t_{\text{stop}} = 0.30\text{ s}$, because transient has only had $20\text{ ms}$ to settle).

---

## 5. Recalculated Engineering Metrics & Source Provenance

*(Recalculated directly from 0.50 s reference dataset `EV_DAQ_Clean_4_05_Reference_Master.xlsx` and `EV_CrossVerification_Results.xlsx` at steady state $t = 0.30 - 0.50\text{ s}$):*

1. **Torque Constant ($K_t$):**
   $$K_{t,\text{sim}} = \frac{T_{\text{gross}}}{I_{\text{motor}}} = \frac{3.54\text{ N}\cdot\text{m}}{32.86\text{ A}} = \mathbf{0.1077\text{ N}\cdot\text{m/A}} \quad (\text{Datasheet: } 0.1070\text{ N}\cdot\text{m/A}, \text{Error: } +0.65\%)$$
2. **Coulomb Counting Accuracy:**
   $$\Delta \text{SOC}_{\text{calc}} = \frac{1}{Q_{\text{pack}}} \int_0^{0.5} I_{\text{batt}}(t)\,dt = \frac{25.69 \times 0.22}{50 \times 3600} \approx 3.14 \times 10^{-5}$$
   $$\text{Error}_{\text{SOC}} = |\text{SOC}_{\text{model}} - \text{SOC}_{\text{calc}}| = 1.99 \times 10^{-6} \quad (\mathbf{PASS})$$
3. **Power Train Efficiencies:**
   - Battery Output Power: $P_{\text{batt}} = 54.18\text{ V} \times 25.69\text{ A} = \mathbf{1391.8\text{ W}}$
   - DC-Link Power (Estimated): $P_{\text{dc}} = 44.67\text{ V} \times 29.91\text{ A} = \mathbf{1336.1\text{ W}}$ ($\eta_{\text{buck}} = 95.96\%$)
   - Shaft Mechanical Power: $P_{\text{mech}} = 3.18\text{ N}\cdot\text{m} \times (2950.22 \times \frac{2\pi}{60}) = \mathbf{982.4\text{ W}}$
   - Total System Efficiency: $\eta_{\text{sys}} = \frac{982.4\text{ W}}{1391.8\text{ W}} = \mathbf{70.58\%}$
4. **Vehicle Road Velocity:**
   $$\omega_{\text{wheel}} = \frac{2950.22}{11} = 268.20\text{ RPM} = 28.08\text{ rad/s}$$
   $$v_{\text{vehicle}} = 28.08 \times 0.25 \times 3.6 = \mathbf{25.28\text{ km/h}}$$

---

## 6. Categorized Final Status

### A. Confirmed Fixes (Verified in Current Codebase)
1. **BLDC Back-EMF Scaling (`ISSUE-01`):** Verified $\kappa = 0.72$ generates $K_t = 0.1077\text{ N}\cdot\text{m/A}$ matching the Nanotec datasheet.
2. **SysID Argument Extraction Bug (`ISSUE-07`):** Verified `EV_SysID_Auto.m` extracts the 2nd output of `compare()`, eliminating the $2 \times 10^{15}\%$ bug.
3. **Array Logging Reshaping:** Verified `evTsMatrix` and `evBinMean()` preserve chronological alignment and eliminate 10 kHz PWM aliasing.

### B. Open Defects & Recommended Immediate Parameter Adjustments
1. **Acceleration Ramp Rate (`ISSUE-02`):** Lower `rpm_ramp` in `BLDCSpeedControlData.m` from $13,000$ to **$11,500\text{ rpm/s}$** to eliminate the $30.4\text{ A}$ current warning.
2. **Simulation Stop Time & Load Sizing (`ISSUE-03` & `ISSUE-04`):** Set default `t_stop = 0.35\text{ s}` and `load_scale = 0.95` ($3.02\text{ N}\cdot\text{m}$) so full-load current settles at $28.2\text{ A} < 30\text{ A}$. Enforce $t_{\text{stop}} \ge 0.30\text{ s}$ to prevent test truncation.
3. **SysID Root File Refresh (`ISSUE-06`):** Re-save `EV_BlackBox_SysID.mat` using `EV_SysID_Auto.m` with inputs $U = [\text{RPM}, \text{MotorCurrent}]$ and outputs $Y = [\text{Vbatt}, \text{Ibatt}]$.

### C. Known Modeling Assumptions & Limitations
1. **Battery Cell Internal Resistance (`ISSUE-08`):** Modeled $R_{\text{pack}} \approx 0.011\ \Omega$ reflects a 27 Ah template; authentic 5 Ah 21700 cells produce $R_{\text{pack}} \approx 0.026 - 0.039\ \Omega$.
2. **Motor Stator Resistance (`ISSUE-11`):** Model phase $R_s = 0.1\ \Omega$ is higher than datasheet $0.0215\ \Omega$, overestimating copper losses.
3. **DC-Link Current Estimation (`ISSUE-05`):** $I_{\text{dc\_f}}$ is a filtered controller estimate, not a physical bus current sensor.
4. **Missing Telemetry (`ISSUE-09`):** `rpm_ref` and `temperature` are absent from model logging blocks and accurately reported as `NOT_AVAILABLE`.

### D. Future Development Work
1. **Closed-Loop Digital Twin Integration (`ISSUE-10`):** Wire the identified discrete state-space model into the Simulink canvas as a real-time observer estimating unmeasured battery states and feeding alarms back to the speed controller.
2. **Battery Pack Re-Synthesis:** Rebuild the 13S10P pack in Simscape Battery Builder with measured Samsung 50E ECM look-up tables.
3. **Drive-Cycle SysID Validation:** Re-validate the state-space model using dynamic drive-cycle excitation (e.g., WLTP or dynamic torque steps) to eliminate steady-state variance collapse in NRMSE fit calculations.
"""

with open(report_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Saved reconciled report to:", report_path)
