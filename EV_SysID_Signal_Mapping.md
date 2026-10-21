# EV Digital Twin: System Identification Signal Mapping Specification

**Document Version:** 2.0  
**Date:** 22-Oct-2026  
**Auditor:** AI V&V Engineer  
**Related Issues:** ISSUE-06, ISSUE-07, ISSUE-12  

---

## 1. Executive Summary

This document formalizes the input-output architecture for the black-box discrete state-space battery digital twin. It details the legacy signal mapping deficiencies, provides engineering justifications for the corrected signal mapping, and documents the normalisation bounds and sampling infrastructure.

---

## 2. Legacy vs Corrected Signal Mapping Comparison

| Attribute | Legacy Model (`EV_BlackBox_SysID.mat` - Root) | Corrected Model (`EV_BlackBox_SysID_FINAL.mat`) | Technical Rationale for Change |
|---|---|---|---|
| **Inputs ($u$)** | `['RPM_rpm', 'Idc_f_A']` | `['RPM', 'MotorCurrent']` | Uses direct physical motor phase current magnitude rather than filtered DC-link estimate. |
| **Outputs ($y$)** | `['Vbatt_V', 'SOC', 'RPM_rpm']` | `['Vbatt_V', 'Ibatt_A']` | 1) Removed duplicate RPM output.<br>2) Added `Ibatt_A` as core battery state variable.<br>3) Handled SOC via Coulomb counting. |
| **Model Order ($n_x$)** | 6 states | 2 states | Order 6 suffered from severe over-parameterization on 0.4s run; Order 2 achieves optimal stability and minimal validation error. |
| **Sample Time ($T_s$)** | 1 ms (discrete) | 1 ms (discrete) | Synchronized with 1 kHz DAQ clean window-averaged logging. |
| **Conditioning** | Raw / Unscaled | Normalized ($u_n = \frac{u - U_0}{U_s}$, $y = Y_s \cdot y_n + Y_0$) | Normalization ensures well-conditioned estimation across disparate units (3000 RPM vs 0.05 V sag). |

---

## 3. Detailed Justification for Signal Allocation

### 3.1 Input Channel 1: `RPM` (Rotor Speed)
- **Physical Role:** Represents the mechanical operating velocity of the vehicle drivetrain.
- **Justification:** Motor speed determines the counter-electromotive force (back-EMF) and the mechanical operating point along the torque-speed curve, directly dictating inverter commutation frequency and load power demands.

### 3.2 Input Channel 2: `MotorCurrent` (Inverter Phase Current)
- **Physical Role:** Represents the electrical torque-producing current demand of the traction motor.
- **Justification:** Motor torque is directly proportional to phase current ($\tau = K_t \cdot I_m$). This current demand draws power across the DC link and pulls discharge current from the battery pack via the buck converter.

### 3.3 Output Channel 1: `Vbatt_V` (Battery Pack Terminal Voltage)
- **Physical Role:** Primary electrical observation of the battery digital twin.
- **Justification:** Terminal voltage reflects open-circuit voltage (OCV) minus internal IR sag and electrochemical transient dynamics ($V_{term} = OCV(SOC) - I_{batt} \cdot R_0 - V_{RC}$). Predicting terminal voltage enables online fault detection and state-of-charge tracking.

### 3.4 Output Channel 2: `Ibatt_A` (Battery Pack Discharge Current)
- **Physical Role:** Pack current drawn by the powertrain.
- **Justification:** Essential for tracking battery power dissipation ($P_{batt} = V_{batt} \cdot I_{batt}$) and integration for energy accounting. The legacy model omitted `Ibatt_A`, rendering it incapable of functioning as a complete battery twin.

### 3.5 Signals Explicitly Excluded from Black-Box Outputs

1. **`RPM` (Removed from Outputs):**
   - *Defect in Legacy:* The legacy model declared `RPM` as both input $u_1$ and output $y_3$.
   - *Consequence:* Modeling an input as its own output forces the state estimator to learn a trivial identity feedthrough or observer state, wasting model capacity and severely corrupting the dynamic estimation of the battery channels.
   - *Action:* Permanently removed from output vector $y$.

2. **`SOC` (Removed from Black-Box Linear Estimation):**
   - *Justification:* State of Charge is governed strictly by charge conservation:
     $$SOC(t) = SOC(0) - \frac{1}{Q_n} \int_{0}^{t} I_{batt}(\tau) \, d\tau$$
   - Treating SOC as an unconstrained output in a linear black-box state-space model produces numerical drift, violates monotonicity during discharge, and fails to enforce [0, 1] physical boundaries.
   - *Action:* Handled through high-accuracy Coulomb counting with 1 ms trapz integration, achieving a Coulomb ratio of 0.985 (verified in VV-011).

3. **`Temperature` (Marked NOT_AVAILABLE):**
   - *Justification:* The current Simscape physical model does not incorporate a thermal equivalent circuit (no heat capacitance or convective boundary). 
   - *Action:* Honestly marked as `NOT_AVAILABLE`. No synthetic temperature data is fabricated.

---

## 4. Normalization and Scaling Bounds

To prevent numerical ill-conditioning during subspace estimation, all channels are scaled using full-run sample statistics from `EV_RUN_20261021_161504`:

```
Inputs:
  Channel 1 (RPM)          : U0[1] = 2100.28 rpm,  Us[1] = 983.88 rpm
  Channel 2 (MotorCurrent) : U0[2] =   27.85 A,    Us[2] =   6.64 A

Outputs:
  Channel 1 (Vbatt_V)      : Y0[1] =   54.29 V,    Ys[1] =   0.0770 V
  Channel 2 (Ibatt_A)      : Y0[2] =   16.03 A,    Ys[2] =   6.8765 A
```

---

## 5. Discrete State-Space Realization ($T_s = 1$ ms)

$$\begin{aligned}
x[k+1] &= A x[k] + B u_n[k] \\
y_n[k] &= C x[k] + D u_n[k]
\end{aligned}$$

With verified system matrices ($n_x = 2$):
```
A = [ 0.8322  -0.1924 ;
     -0.4729   0.4090 ]

B = [-0.7242   0.9108 ;
      2.7390  -6.8860 ]

C = [ 1.2780   0.3417 ;
     -1.2820  -0.3383 ]

D = [ 0.0000   0.0000 ;
      0.0000   0.0000 ]
```

**Eigenvalues of A:** $\lambda_1 = 0.9890$, $\lambda_2 = 0.2522$  
*Both eigenvalues lie strictly inside the unit circle ($|\lambda| < 1$), guaranteeing asymptotic stability.*
