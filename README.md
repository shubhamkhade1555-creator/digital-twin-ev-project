# Black-Box Model-Based Real-Time Digital Twin for Electric Vehicle Battery & BLDC Powertrain

[![MATLAB](https://img.shields.io/badge/MATLAB-R2024b-blue.svg)](https://www.mathworks.com/products/matlab.html)
[![Simulink](https://img.shields.io/badge/Simulink-Simscape_Battery-orange.svg)](https://www.mathworks.com/products/simulink.html)
[![Architecture](https://img.shields.io/badge/Digital_Twin-Level_2_Digital_Shadow-brightgreen.svg)]()
[![Status](https://img.shields.io/badge/Audit_Status-Fully_V%26V_Reconciled-success.svg)]()
[![License](https://img.shields.io/badge/License-MIT-blue.svg)]()

> **Project Title:** Design and Development of a Black-Box Model-Based Real-Time Digital Twin for an Electric Vehicle Battery Using MATLAB/Simulink  
> **Repository:** `shubhamkhade1555-creator/digital-twin-ev-project`  
> **Primary Baseline Benchmark Run:** `EV_RUN_20261021_161504` ($t_{stop} = 0.40$ s, 401 samples, 1 kHz uniform clean DAQ)

---

## 1. Project Overview

This repository hosts the complete, verified, and audited codebase for an Electric Vehicle (EV) Powertrain and Battery Digital Twin implemented in **MATLAB / Simulink / Simscape Battery R2024b**. 

The system simulates an electric two-wheeler powertrain comprising:
- **Energy Storage:** A **48V, 50Ah Lithium-Ion Battery Pack** configured in a **13S10P** topology (130 cells, Samsung SDI INR21700-50E equivalent).
- **Power Conversion:** A bidirectional **DC-DC Buck Converter** with closed-loop PWM switching control supplying a regulated DC link.
- **Traction Drive:** A **3-Phase BLDC Inverter** with Hall-effect commutation and continuous/peak current limiting.
- **Mechanical Plant:** A **1 kW, 48V, 3000 RPM Brushless DC (BLDC) Motor** (Nanotec APBA80L048030-E) with reduction gearing ($11:1$), shaft inertia, and vehicle road load resistance.
- **Digital Twin Layer:** An automated **1 kHz DAQ Pipeline** and a **Black-Box Discrete State-Space Model ($n_x = 2$, $T_s = 1.0$ ms)** identified via subspace methods (`n4sid`) predicting terminal voltage and battery current.

---

## 2. Digital Twin Architecture

The system operates as a **Validated Level 2 Digital Shadow**:

```
+---------------------------------------------------------------------------------+
|                         PHYSICAL PLANT (Simscape / Simulink)                    |
|                                                                                 |
|   +---------------+      +-----------------+      +-------------------------+   |
|   | 48V 50Ah Pack | ---> | DC-DC Converter | ---> | 3-Phase Inverter + BLDC |   |
|   | (13S10P Li-Ion|      |   (Buck Bus)    |      | (1 kW, 3000 RPM, 3.2Nm) |   |
|   +---------------+      +-----------------+      +-------------------------+   |
+---------------------------------------------------------------------------------+
                                      |
                                      v (10 kHz PWM & Solver Telemetry)
+---------------------------------------------------------------------------------+
|                       AUTOMATED DAQ PIPELINE (EV_DAQ_Builder_V7.m)              |
|                                                                                 |
|   - Uniform 1 ms window resampling (PWM switching ripple removed)               |
|   - Positive-discharge engineering current sign conversion                      |
|   - Coulomb counting SOC integration: ratio = 0.985 (Charge Conservation)       |
|   - 25 Automated V&V Checks (04_VV_Results.xlsx)                                |
+---------------------------------------------------------------------------------+
                                      |
                                      v (Clean 1 kHz Dataset: EV_FINAL_RESULTS.csv)
+---------------------------------------------------------------------------------+
|                     BLACK-BOX BATTERY DIGITAL TWIN (EV_SysID_Auto.m)            |
|                                                                                 |
|   Inputs : [RPM (speed demand), MotorCurrent (electrical load demand)]          |
|   Outputs: [Vbatt_V (terminal voltage), Ibatt_A (pack discharge current)]       |
|   Model  : Discrete State-Space (nx = 2, Ts = 1 ms, Stable poles: 0.989, 0.252) |
|   Accuracy: Vbatt RMSE = 0.3441 V (0.63% error on 54.21 V pack)                 |
+---------------------------------------------------------------------------------+
```

---

## 3. Hardware Datasheet Cross-Verification

The simulation was verified against manufacturer specifications:
- **BLDC Motor:** [Nanotec APBA80L048030-E Datasheet](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/Datasheets_and_Simulation_Verification/APBA80L048030-E_Datasheet.pdf)
- **Li-Ion Battery Cell:** [Samsung INR21700-50E Datasheet](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/Datasheets_and_Simulation_Verification/Samsung_INR21700-50E_Cell_Datasheet.pdf)

### Key Parameter Matching
| Parameter | Unit | Manufacturer Datasheet | Simulink Model Value | Running Simulated Value | Audit Finding |
|---|---|---|---|---|---|
| **Rated Motor Power** | W | 1000 (1.0 kW) | 1000 | 982 – 1005 W | **PASS** (< 1.8% deviation) |
| **Rated Motor Speed** | RPM | 3000 | 2950 (target ref) | 2950.22 RPM | **PASS** (+0.007% error) |
| **Torque Constant ($K_t$)**| N*m/A| 0.107 | 0.107 ($\kappa = 0.72$) | 0.1077 N*m/A | **PASS** (+0.65% vs datasheet) |
| **Continuous Motor Current**| A | 30.0 | 30.0 ($I_{cont}$) | 29.91 A (RMS) / 30.3 A (hold)| **RECONCILED** (Includes 0.3 Nm friction)|
| **Peak Current Limit** | A | 90.0 (catalog) | 45.0 (controller) | 45.0 A (clamped) | **PASS** ($I^2t = 10.28\text{ A}^2\text{s} < 1125$)|
| **Pack Nominal Voltage** | V | 46.8 – 47.2 (13S) | 48.1 | 48.1 V | **PASS** |
| **Pack Full Charge Voltage**| V | 54.60 (13S @ 4.2V)| 54.60 | 54.47 V (initial OCV) | **PASS** |
| **Pack Capacity** | Ah | 50.00 (10P @ 5Ah) | 50.00 | 50.00 Ah | **PASS** |
| **Coulomb Accuracy** | — | 1.000 (ideal) | 1.000 | 0.985 (Check VV-011) | **PASS** |

---

## 4. Key Audit Deliverables & Documentation

The project audit has generated a synchronized 18-issue register and verification suite:

1. [EV_Digital_Twin_FINAL_AUDIT.md](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/EV_Digital_Twin_FINAL_AUDIT.md) — Definitive master forensic audit report.
2. [EV_Digital_Twin_ROOT_CAUSE_REGISTER_FINAL.xlsx](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/EV_Digital_Twin_ROOT_CAUSE_REGISTER_FINAL.xlsx) — Complete 18-issue root-cause register.
3. [FINAL_VALIDATION_SUMMARY.md](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/FINAL_VALIDATION_SUMMARY.md) — Summary of acceptance test suites A through F.
4. [CHANGELOG.md](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/CHANGELOG.md) — Detailed technical changelog from V1.0 to V8.0.
5. [UNRESOLVED_ISSUES.md](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/UNRESOLVED_ISSUES.md) — Open parameter gaps (motor stator resistance, cell resistance) and future roadmap.
6. [BASELINE_FILE_MANIFEST.csv](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/BASELINE_FILE_MANIFEST.csv) — MD5 provenance checksums for all project assets.
7. [EV_SysID_Signal_Mapping.md](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/EV_SysID_Signal_Mapping.md) — Input/output channel justifications and normalization scaling.
8. [EV_BlackBox_SysID_FINAL_REPORT.txt](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/EV_BlackBox_SysID_FINAL_REPORT.txt) — Official SysID execution & variance breakdown report.
9. [EV_VV_FINAL_RESULTS.xlsx](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/EV_VV_FINAL_RESULTS.xlsx) — 25-check V&V spreadsheet with formula proofs.
10. [EV_FINAL_RESULTS.csv](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/EV_FINAL_RESULTS.csv) — Clean 1 kHz baseline simulation dataset (401 rows, 14 channels).

---

## 5. Black-Box Comparison Plots V2 (MATLAB R2024b; no dashboard)

The default graph workflow is now the versioned, plot-only pipeline:
- `EV_BlackBox_ComparePlotsV2.m` generates figures under `Simulation Logs/EV_RUN_*/Figures_BlackBox_V2/`.
- The pipeline uses the clean Simulink signals and the saved System Identification model/validation dataset.
- It does **not** create a MATLAB App Designer dashboard.
- It does **not** create illustrative reference curves or label proxy/derived signals as direct measurements.
- The current identified model predicts only battery voltage and battery current from `RPM` and `MotorCurrent`. SOC is handled outside the linear model; temperature is plotted only if a real logged signal exists. Motor speed/current/torque plots are simulation signals, not black-box predictions.

### Generated graph groups

**Battery**
- `BatteryVoltage_Simulation.png`
- `BatteryCurrent_Simulation.png`
- `SOC_Simulation.png` (if logged)
- `BatteryTemperature_Simulation.png` (only if logged)
- `BatteryCellVoltage_Simulation.png` (only if logged)

**Motor**
- `MotorRPM_Reference_vs_Actual.png` (when both channels exist)
- `MotorCurrent_Simulation.png`
- `MotorTorque_Simulation.png` (only if logged)
- `DCLinkVoltage_Simulation.png` (only if logged)

**System Identification**
- `Validation_Voltage_Measured_vs_Predicted.png`
- `Validation_Current_Measured_vs_Predicted.png`
- `Residual_Voltage.png`
- `Residual_Current.png`
- `SysID_ModelOrder_Fit_Comparison.png` (when order sweep data exists)
- `SysID_Validation_Metrics.csv`

### Run it

After a completed simulation with the normal DAQ/SysID pipeline:

```matlab
% If you have the run folder:
Rplots = EV_BlackBox_ComparePlotsV2([], fullfile(pwd, ...
    'Simulation Logs', 'EV_RUN_YYYYMMDD_HHMMSS'));

% Or pass the clean table already created by the DAQ builder:
Rplots = EV_BlackBox_ComparePlotsV2(EV_DAQ_Clean, runDir);
```

The DAQ builder and `RunAll.m` use V2 plotting by default. To opt into the legacy DAQ/reference graph pipeline for a specific MATLAB session, set:

```matlab
EV_BlackBox_PlotsV2 = false;
```

To restore V2 as the default, clear the flag or set it true:

```matlab
clear EV_BlackBox_PlotsV2
% or:
EV_BlackBox_PlotsV2 = true;
```

Fast mode skips graph generation. Legacy plotting functions remain in the source for rollback, but are not called by default; this preserves the simulation, logging, Excel reporting and V&V code.

### Validation interpretation

The graph generator plots measured validation data against both one-step predictions and free-run model simulations using the saved normalized validation dataset, then converts predictions back to engineering units. It does not treat a stable model or low RMSE alone as proof of acceptance. Negative raw fit remains visible and the SysID report's acceptance verdict remains authoritative.

