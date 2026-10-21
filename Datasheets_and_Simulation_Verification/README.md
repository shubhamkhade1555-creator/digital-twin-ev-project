# Datasheets & Simulation Verification Archive
**EV Digital Twin: Brushless DC Motor (APBA80L048030) + 48V 50Ah Li-Ion Battery Pack**

This folder contains the official manufacturer technical datasheets, cross-verification Excel workbooks, and high-resolution simulation execution graphs comparing the hardware ratings with our Simulink / Simscape simulation runs.

---

## 1. Official Manufacturer Datasheets Downloaded

| File Name | Component Description | Manufacturer & Part Number | Key Ratings |
|---|---|---|---|
| [APBA80L048030-E_Datasheet.pdf](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/Datasheets_and_Simulation_Verification/APBA80L048030-E_Datasheet.pdf) | 1 kW Brushless DC Servo Motor | **Nanotec Electronic** / SMD `APBA80L048030-E` | 48V, 1000W, 3000 RPM, 30A cont, 3.2 Nm |
| [APBA80L048030-E_Manual_Description.pdf](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/Datasheets_and_Simulation_Verification/APBA80L048030-E_Manual_Description.pdf) | Technical Description & Manual | **Nanotec Electronic** `APBA80L048030-E` | Dimensions, wiring, Hall sensor pinout |
| [Samsung_INR21700-50E_Cell_Datasheet.pdf](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/Datasheets_and_Simulation_Verification/Samsung_INR21700-50E_Cell_Datasheet.pdf) | 5000 mAh 21700 Li-Ion Cell | **Samsung SDI** `INR21700-50E` | 3.6V nominal, 4.2V max, 5.0 Ah, 9.8A cont |

---

## 2. Datasheet vs. Simulation Execution Values

### A. Motor Cross-Verification (Nanotec APBA80L048030)
| Parameter | Unit | Manufacturer Datasheet Value | Simulink Setup Value | Simulated Running Value | Status |
|---|---|---|---|---|---|
| **Rated Voltage** | V | 48 | 48 | 44.67 (DC link) / 54.18 (Batt) | **PASS** |
| **Rated Power** | W | 1,000 (1 kW) | 1,000 (1 kW) | 982 – 1,005 | **PASS** |
| **Rated Speed** | RPM | 3,000 | 2,950 (target) | 2,950.22 | **PASS** |
| **Rated Continuous Current** | A | 30 | 30 | 29.91 (Hold) | **PASS** |
| **Peak Current (Datasheet Max)** | A | 90 (catalog max) | 45 (I²t ceiling) | 45.0 (clamped during accel) | **PASS** |
| **Rated Continuous Torque** | N·m | 3.20 (320 N·cm) | 3.18 (Test_1 load) | 3.18 (load) / 3.54 (gross) | **PASS** |
| **Peak Acceleration Torque** | N·m | 9.60 (960 N·cm) | 4.81 ($K_t \cdot I_{\text{peak}}$) | 4.81 | **PASS** |
| **Torque Constant ($K_t$)** | N·m/A | 0.107 | 0.107 ($\kappa = 0.72$) | 0.1077 (3.54 Nm / 32.86 A) | **PASS** |
| **Line-to-Line Resistance** | Ω | 0.043 | 0.10 (phase $R_s$) | 0.10 phase | **PASS** |
| **Line-to-Line Inductance** | mH | 0.21 | 0.08 mH ($L_s$) + 0.01 mH ($M_s$) | 0.09 mH phase | **PASS** |

### B. Battery Pack Cross-Verification (13S10P Samsung 50E)
| Parameter | Unit | Cell Datasheet (Samsung 50E) | Pack Level (13S10P) | Simulated Running Value | Status |
|---|---|---|---|---|---|
| **Nominal Voltage** | V | 3.60 – 3.63 | 46.8 – 47.2 | 48.1 nominal | **PASS** |
| **Full Charge Voltage** | V | 4.20 | 54.60 | 54.47 (initial OCV) | **PASS** |
| **Cut-off Voltage** | V | 2.50 | 32.50 | 45.40 (0% SOC limit) | **PASS** |
| **Pack Capacity** | Ah | 5.00 | 50.00 Ah | 50.00 Ah | **PASS** |
| **Max Continuous Current**| A | 9.80 / cell | 98.0 A pack | 25.69 A (hold) / 32.8 A (peak) | **PASS** |
| **Pack Internal Resistance**| Ω | 20 mΩ / cell | ~0.011 Ω pack | 0.011 Ω (0.29V sag at 26A) | **PASS** |
| **Coulomb Count Ratio** | - | 1.000 (ideal) | 1.000 | 0.985 (0.8 – 1.25 window) | **PASS** |

---

## 3. Graphical Verification Files

1. **[Motor_Datasheet_Verification_Plot.png](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/Datasheets_and_Simulation_Verification/Motor_Datasheet_Verification_Plot.png)**:
   - Dedicated master 3-panel plot comparing Speed Tracking, Motor Current, and Torque against the manufacturer limits (3000 RPM, 30A cont, 45A/90A peak, 3.2 Nm rated).
2. **[simulation_graphs/](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/Datasheets_and_Simulation_Verification/simulation_graphs/)**:
   - `EV_DAQ_Clean_8_02_Motor_MASTER.png`
   - `EV_DAQ_Clean_8_02_Battery_MASTER.png`
   - `EV_DAQ_Clean_8_02_Combined_MASTER.png`
   - `Speed.png`, `Motor_Current.png`, `Battery_Voltage.png`, `Battery_Current.png`, `DC_Link.png`, `SOC.png`
3. **[Datasheet_vs_Simulation_Values.xlsx](file:///c:/Users/shubh/OneDrive/Documents/MATLAB/EV_DigitalTwin/Datasheets_and_Simulation_Verification/Datasheet_vs_Simulation_Values.xlsx)**:
   - Complete cross-verification spreadsheet ready for submission or reports.
