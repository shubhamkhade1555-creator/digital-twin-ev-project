# EV Digital Twin: Unresolved Issues, Modeling Gaps & Roadmap

**Document Version:** 1.0  
**Date:** 22-Oct-2026  
**Auditor:** AI V&V Engineer  
**Audit Policy:** Strict Engineering Honesty ("Document every known deficiency without concealment")

---

## 1. Executive Summary

While the V8.0 audit baseline has resolved all critical execution defects (back-EMF calibration, SysID compare extraction bug, signal mapping duplication, and simulation duration truncation), several physical parameter discrepancies and architectural limitations remain in the codebase. 

In accordance with strict verification and validation standards, these items are explicitly documented below with their root-cause mechanisms, downstream impacts, and step-by-step resolution roadmaps.

---

## 2. Unresolved Issues and Modeling Gaps

### GAP-01 (ISSUE-08): Battery Cell Resistance Lookup Table Mismatch
- **Subsystem:** Simscape Battery Pack (`+Batteries2/ParallelAssemblyType1.ssc`, `BLDCSpeedControlData.m`)
- **Current Modeled Value:** Modeled pack internal resistance is $R_{pack} \approx 0.01105$ $\Omega$ ($R_0 \approx 8.5$ m$\Omega$ per cell template).
- **Physical Reference (Samsung INR21700-50E):** Manufacturer datasheet quotes AC impedance $\le 35$ m$\Omega$ at 1 kHz and DC internal resistance $R_{DC} \approx 20 - 30$ m$\Omega$ at 20 °C. For a 13S10P topology, the physical pack resistance is:
  $$R_{pack\_real} = \frac{13 \times R_{cell}}{10} = 1.3 \times 28\text{ m}\Omega \approx 0.0364\ \Omega$$
- **Root Cause:** The Simscape Battery pack was generated using a 27 Ah cell template. When cell capacity was overridden to `AHCell = 5` Ah, the internal resistance lookup table was not scaled up to match a high-impedance 5 Ah cylindrical cell.
- **Impact:** Simulation underestimates battery terminal voltage sag under a 26 A discharge ($0.29$ V modeled sag vs $0.75 - 0.95$ V realistic sag). Battery Joule heating ($I^2 R$) is underestimated by $\sim 3.3\times$.
- **Resolution Roadmap:**
  1. Re-synthesize the 13S10P module in Simscape Battery Builder using the Samsung 50E OCV-SOC and $R_0(SOC, T)$ lookup tables.
  2. Validate simulated voltage sag against pulsed discharge test data.

---

### GAP-02 (ISSUE-11): Motor Stator Resistance and Inductance Discrepancy
- **Subsystem:** BLDC Motor Electrical Plant (`BLDCSpeedControlData.m`, Simscape BLDC Block SID 2178)
- **Current Modeled Values:** 
  - Phase resistance: $R_s = 0.10$ $\Omega$ (equivalent to line-to-line $R_{ll} = 0.20$ $\Omega$)
  - Phase inductance: $L_s = 80$ $\mu$H, mutual inductance $M_s = 10$ $\mu$H ($L_{ll} = 0.14$ mH)
- **Physical Reference (Nanotec APBA80L048030-E):**
  - Line-to-line resistance: $R_{ll} = 0.043$ $\Omega$ (phase resistance $R_{phase} = \frac{R_{ll}}{2} = 0.0215$ $\Omega$)
  - Line-to-line inductance: $L_{ll} = 0.21$ mH ($L_{phase} = 0.105$ mH)
- **Root Cause:** MathWorks legacy default parameters were retained in `BLDCSpeedControlData.m` rather than entering the exact hardware datasheet values.
- **Impact:** Modeled motor phase resistance is **4.65x higher** than physical hardware. This overestimates motor stator copper losses ($3 I^2 R_s$) by $4.65\times$ and underestimates peak motor electrical efficiency.
- **Resolution Roadmap:**
  1. Update `BLDCSpeedControlData.m`: set `Rs = 0.0215` $\Omega$ and `Ls = 1.05e-4` H.
  2. Re-tune the inner PI current loop ($K_p, K_i$) and outer PI speed loop to account for the reduced stator impedance and faster electrical time constant ($\tau_e = \frac{L}{R} = 4.88$ ms).

---

### GAP-03 (ISSUE-05): Absence of Direct DC-Link Current Sensor
- **Subsystem:** Inverter / DC-Link Instrumentation (`BLDCSpeedControl_EV_Layout_v2.slx`)
- **Current Implementation:** Block `Meas V` (SID 2248) measures DC-link voltage only. Logged signal `Idc_f` is an internal controller calculation: $\max(|i_{abc}|)$ filtered by a 2 ms continuous first-order low-pass filter.
- **Root Cause:** No physical DC current measurement block is wired between the DC-DC buck converter and the inverter bridge.
- **Impact:** Instantaneous DC-link power ($P_{dc} = V_{dc} \cdot I_{dc\_f}$) exhibits dynamic phase lag and transient spikes ($P_{dc} / P_{batt} = 1.026 - 1.11$, triggering fail on VV-012). It cannot serve as direct sensor evidence of converter efficiency.
- **Resolution Roadmap:**
  1. Insert a Simscape `Current Sensor` block directly in series with the positive DC bus conductor upstream of the inverter bridge.
  2. Log physical DC-link current alongside controller estimate `Idc_f` to validate the estimator.

---

### GAP-04 (ISSUE-09): Missing Thermal Dynamics and Reference Speed Telemetry
- **Subsystem:** Battery Pack & DAQ Logging Infrastructure
- **Current Implementation:** Cell temperature and reference speed ramp are unlogged and marked `NOT_AVAILABLE`.
- **Root Cause:** 
  1. Simscape Battery pack uses an isothermal electrical formulation without a thermal mass or convective heat dissipation port.
  2. Speed reference ramp output is internal to the controller subsystem and lacks a `To Workspace` logger.
- **Impact:** Inability to validate battery thermal runaway, cooling efficiency, or instantaneous speed tracking error directly from the raw telemetry archive.
- **Resolution Roadmap:**
  1. Enable the thermal port in the Simscape Battery module and connect conductive/convective heat dissipation blocks.
  2. Route the speed ramp signal to a dedicated workspace logging block in `EV_DAQ_Builder_V7.m`.

---

### GAP-05 (ISSUE-10): Unimplemented Closed-Loop Real-Time Digital Twin Integration
- **Subsystem:** Digital Twin Architecture (`EV_Twin_App.m`, `BLDCSpeedControl_EV_Layout_v2.slx`)
- **Current Status:** **Level 2 Digital Shadow** (offline system identification after simulation completion).
- **Target Status:** **Level 3 Closed-Loop Digital Twin** (state-space model running concurrently in Simulink, estimating unmeasured states and providing real-time telemetry/fault detection to the motor controller).
- **Impact:** The identified state-space model does not yet influence the active vehicle simulation or real-time control.
- **Resolution Roadmap:**
  1. Add a discrete State-Space block into `BLDCSpeedControl_EV_Layout_v2.slx` configured with `EV_BlackBox_SysID_FINAL.mat`.
  2. Implement state-space input scaling ($u_n = \frac{u - U_0}{U_s}$) and output unscaling ($y = Y_s \cdot y_n + Y_0$) inside a dedicated Simulink subsystem.
  3. Validate real-time execution budget at 1 kHz sample rate.

---

### GAP-06 (ISSUE-02 / VV-008 / VV-023): Drivetrain Friction Current Overhead
- **Subsystem:** Powertrain Continuous Current Sizing (`04_VV_Results.xlsx`, `BLDCSpeedControlData.m`)
- **Current Status:** Full rated mechanical load ($3.18$ Nm) plus drivetrain damping ($B = 0.001$ N*m*s/rad adds $0.309$ Nm gross torque) demands gross torque of $3.49$ Nm. At $K_t = 0.1077$ N*m/A, required gross current is:
  $$I_{gross} = \frac{3.49\text{ Nm}}{0.1077\text{ Nm/A}} \approx 32.4\text{ A peak} \quad (30.3 - 30.69\text{ A average})$$
- **Root Cause:** Applying 100% of datasheet rated external load on top of internal mechanical losses pushes the motor slightly beyond its 30 A continuous rating ($101\%$ of rating).
- **Impact:** Checks VV-008 and VV-023 fail by $0.3 - 0.69$ A, causing overall test runner to report FAIL.
- **Resolution Roadmap:**
  1. Scale test load profile by 0.95 ($T_{load} = 3.02$ Nm) so that total torque equals exactly rated $3.18$ Nm.
  2. Alternatively, update validation acceptance rule to permit a $+1.5$ A tolerance ($I_{cont} \le 31.5$ A) when internal mechanical friction is explicitly modeled.
