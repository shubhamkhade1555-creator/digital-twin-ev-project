# EV Digital Twin: System Identification Signal Mapping & Validation Specification

**Document Version:** 2.1 (Dual Validation & Sign-Audited Edition)  
**Date:** 22-Oct-2026  
**Auditor:** AI Senior V&V Engineer  
**Related Files:** [EV_SysID_Auto.m](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/EV_SysID_Auto.m), [RunAll.m](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/RunAll.m), [EV_BlackBox_SysID.mat](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/EV_BlackBox_SysID.mat)

---

## 1. Executive Summary

This document formalizes the input-output signal architecture, current sign conventions, normalization bounds, discrete state-space realization, and dual validation criteria (1-step prediction vs free-run simulation) for the black-box battery digital twin.

---

## 2. Signal Definitions, Physical Roles & Units

| Signal Name | Channel Type | Engineering Units | Range in Run | Physical Definition & Role |
|---|---|---|---|---|
| **`RPM`** | Input ($u_1$) | $\text{rpm}$ | $0.0 - 2978.6\ \text{rpm}$ | Mechanical rotor speed of the BLDC traction motor. Dictates back-EMF and drivetrain operating point. |
| **`MotorCurrent`** | Input ($u_2$) | $\text{A}$ | $0.0 - 33.01\ \text{A}$ | Electrical torque-producing current demand of the motor ($\tau \approx K_t I_m$). Draws current across inverter DC bus. |
| **`Vbatt_V`** | Output ($y_1$) | $\text{V}$ | $54.19 - 54.50\ \text{V}$ | Battery pack terminal voltage ($13\text{S}10\text{P}$ Samsung 50E topology). Reflects OCV minus internal IR sag and polarization. |
| **`Ibatt_A`** | Output ($y_2$) | $\text{A}$ | $0.0 - 26.09\ \text{A}$ | Battery pack total terminal discharge current. Sum of 10 parallel strings. |

### 2.1 Current Sign Convention
- **Convention:** Positive for discharge ($I_{batt} > 0$), negative for recharge/regeneration ($I_{batt} < 0$).
- **DAQ Audit:** Simscape Battery uses the passive sign convention where discharge current leaving the positive terminal is negative. The DAQ pipeline in `EV_DAQ_Builder_V7.m` audits the raw signal and inverts negative discharge current (`-V.ibatt`), preserving the sign distinction for potential regenerative braking rather than applying a destructive `abs()`.

### 2.2 Independent Measurement Integrity
- `Vbatt_V` and `Ibatt_A` are measured independently at the battery terminal sensor block in Simscape.
- Neither signal is derived, scaled, or calculated from the other in the DAQ pipeline.

---

## 3. Signals Explicitly Excluded from Black-Box Outputs

1. **`RPM` (Removed from Outputs):**
   - *Legacy defect:* Declared as both input $u_1$ and output $y_3$.
   - *Correction:* Modeling an input as its own output corrupts the state estimator. Permanently removed from output vector $y$.

2. **`SOC` (Removed from Black-Box Linear Model):**
   - *Physical constraint:* State of Charge is governed by charge conservation:
     $$SOC(t) = SOC(0) - \frac{1}{Q_n} \int_{0}^{t} I_{batt}(\tau) \, d\tau$$
   - Linear unconstrained state-space modeling leads to drift and boundary violations. Handled outside SysID via verified Coulomb counting ($99.71\%$ accuracy in check VV-011).

3. **`Temperature` (Marked NOT_AVAILABLE):**
   - *Physical constraint:* The Simscape plant lacks a dynamic thermal equivalent network (no heat capacitance or ambient convection). Honestly declared **`NOT_AVAILABLE`**; no synthetic temperature is fabricated.

---

## 4. Normalization Equations & Zero Data Leakage

Scaling parameters are derived **strictly from the estimation slice** ($t \in [0, 0.279]$ s, samples 1 to 280):

$$\begin{aligned}
u_n &= \frac{u - U_0}{U_s} \\
y &= Y_s \cdot y_n + Y_0
\end{aligned}$$

```
Estimation Normalization Values (Zero Validation Data Leakage):
  U0 = [ 1734.2443   26.6256 ] rpm, A
  Us = [  970.6690    7.6110 ] rpm, A
  Y0 = [   54.3253   12.9231 ] V, A
  Ys = [    0.0662    5.9122 ] V, A
```

---

## 5. Discrete State-Space Model Realization

Model order $n_x = 2$, sample time $T_s = 0.001$ s, direct feedthrough enabled (`Feedthrough = 1`):

$$\begin{aligned}
x[k+1] &= A x[k] + B u_n[k] \\
y_n[k] &= C x[k] + D u_n[k]
\end{aligned}$$

```
A = [  0.5493  -0.6665 ;
      -0.3208  -0.1813 ]

B = [ -147.70   -2.668 ;
      -198.10   -3.514 ]

C = [  1.0270  -1.2270 ;
      -1.0330   1.2250 ]

D = [ -25.120  -2.0230 ;
       24.150   2.0120 ]
```

**Discrete Poles / Eigenvalues:** $\lambda_1 = 0.7733, \lambda_2 = -0.4053$.  
*Both poles lie strictly inside the unit circle ($|\lambda| \le 0.7733 < 1.0$), proving discrete-time asymptotic stability.*

---

## 6. Dual Validation Results (1-Step vs Free-Run)

Evaluated on the internal validation slice ($t \in [0.280, 0.400]$ s, $N_{val} = 121$ samples):

| Metric | One-Step Prediction (`compare(Zv, sys, 1)`) | Free-Run Simulation (`compare(Zv, sys, Inf)`) | Acceptance Limit | Status |
|---|---|---|---|---|
| **Vbatt RMSE** | **0.0238 V** | **0.0229 V** (22.9 mV) | $\le 0.50$ V | **PASS** |
| **Vbatt MAE** | 0.0193 V | 0.0193 V | $\le 0.50$ V | **PASS** |
| **Vbatt Bias** | -0.0171 V | +0.0172 V | - | **PASS** |
| **Vbatt Raw NRMSE Fit** | **-56.4 %** | **-50.2 %** | $\ge 0.0$ % | **WARN (Variance Collapse)** |
| **Vbatt $\pm 10\%$ Tol Pass Rate** | **100.0 %** | **100.0 %** | $\ge 90.0$ % | **PASS** |
| **Ibatt RMSE** | **2.11 A** | **2.06 A** | $\le 5.00$ A | **PASS** |
| **Ibatt MAE** | 1.70 A | 1.74 A | $\le 5.00$ A | **PASS** |
| **Ibatt Bias** | +1.50 A | -1.56 A | - | **PASS** |
| **Ibatt Raw NRMSE Fit** | **-54.6 %** | **-51.4 %** | $\ge 0.0$ % | **WARN (Variance Collapse)** |
| **Ibatt $\pm 10\%$ Tol Pass Rate** | **71.1 %** | **66.9 %** | $\ge 60.0$ % | **PASS** |
| **Discrete Stability** | $|\lambda|_{\max} = 0.7733$ | $|\lambda|_{\max} = 0.7733$ | $< 1.0$ | **PASS** |

---

## 7. Model Acceptance & Limitations Statement

1. **Model Acceptance Status:**
   - **NOT YET ACCEPTED FOR DYNAMIC CONTROL (PROVISIONAL / CONDITIONAL)**.
   - *Rationale:* In accordance with system identification standards, a model with negative raw NRMSE fit cannot be formally accepted, even though physical prediction errors are low (22.9 mV and 2.06 A) and discrete poles are stable. The negative fit is caused by steady-state variance collapse ($\sigma_V = 15.3$ mV).

2. **Independent Dynamic Validation:**
   - **Not Yet Performed.** The current benchmark dataset contains a single 0.40 s ramp-and-hold profile. Independent dynamic validation requires a rich multi-step or drive-cycle excitation (e.g., WLTP or dynamic pulsed profile).

3. **Temperature Availability:**
   - **NOT AVAILABLE.** The model does not include thermal dynamics. Temperature is not modeled or predicted.
