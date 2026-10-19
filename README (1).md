# EV Digital Twin: BLDC Motor + Battery + Black Box

One-click run of the Simulink / Simscape model **BLDCSpeedControl_EV_Layout_v2**. It loads the parameters, builds the data logging and the Black Box, runs the simulation, saves the data and checks the result.

---

## 0. Project overview (what this is and why)

**EVTWIN (eVideo)** is a simulation-based **digital twin of an e-bike / EV powertrain** with a **Black Box recorder**. It is an MTech project; no physical hardware is built.

**Problem (India-focused):** (1) no black box, so after an EV accident or fire the root cause is unknown; (2) no real-time health monitoring, owners only see SOC %; (3) no cloud history across vehicles.

**Idea:** a digital twin of the vehicle (battery, buck converter, inverter, BLDC motor, controller, wheel load) + a 1 ms Black Box + BMS/VMS intelligence + cloud telemetry. Long-term hardware target: below Rs 5,000.

**Digital twin concept:** a virtual model connected to a physical asset by data [1][2]. By the Kritzinger classification [3] the project is a digital model plus an automatic digital shadow in simulation (data flows from the plant to the DAQ, Black Box and archive); the two-way digital twin level is planned.

**Implemented:**

| Layer | What exists |
|---|---|
| Plant | Simscape model based on the MathWorks BLDC Speed Control example [8]: 13S10P 50 Ah pack, buck converter, inverter, BLDC motor (Kt 0.107 N*m/A), 11:1 gearbox, wheel load, I^2t current limiter (45 A peak / 30 A continuous) |
| DAQ | 9 logged signals, signal map, LIVE telemetry every 0.1 s of simulation time, archive per run |
| Black Box | `EV_BlackBox` subsystem, 8 channels at 1 ms, 301 x 8 samples per 0.3 s run |
| Verification | about 25 V&V rows in the builder + 14 checks in `RunAll` |
| Run control | one-click `RunAll.m` (auto path, checks, simulation, log) |

**Planned (not yet built):** temperature and speed-reference logging, event-triggered Black Box, fault scenarios, SOC/SOH estimation, risk and maintenance prediction, MQTT cloud telemetry, validation with real e-bike data.

**Result of the reference run (9 Oct 2026):** speed 2942 rpm (target 2950), torque per amp 0.108 N*m/A (datasheet 0.107), wheel speed 28.0 rad/s, battery sag 0.29 V, SOC 0.99998. One open point: battery current of Black Box vs archive differs by 3.35 A (13.8 %) in the last 20 ms.

The full end-to-end description (architecture, parameters, equations, V&V, results, user guide, limitations, glossary, references) is in the Word report **`EVTWIN_Project_Report.docx`**.

---

## 1. Quick start (3 steps)

1. Copy the whole project folder to your PC (OneDrive or any path works; nothing is hard-coded).
2. Open MATLAB and open `RunAll.m`.
3. Press **Run** (or type `RunAll` in the Command Window).

You do not need to set any path or edit any file. `RunAll` finds the folder, sets the path, loads everything, runs the simulation and prints the result.

---

## 2. What is in the folder

| File | Purpose | Required |
|---|---|---|
| `RunAll.m` | One-click runner (this is the file you run) | Yes |
| `EV_DAQ_Builder_V7.m` | Builds the data logging, LIVE telemetry and Black Box, runs post-processing and the data archive | Yes |
| `BLDCSpeedControl_EV_Layout_v2.slx` | Main model (motor, controller, buck converter, battery, wheel, Black Box) | Yes |
| `BLDCSpeedControlData.m` | All model parameters (motor, battery, controller, drivetrain, run length) | Yes |
| `BLDCSpeedControlInput.mat` | Signal Editor input (load-torque profile `Test_1`) | Yes |
| `Batteries2_lib.slx` | Battery pack library (Simscape Battery) | Yes |
| `Batteries2.slx` | Battery example model | Optional |
| `BLDCSpeedControl_EV_Layout_v2.slxc` | Simulink cache (created by MATLAB, do not edit) | Auto |
| `EVTWIN_Project_Report.docx` | Full project report and user guide (Word) | Documentation |

Folders created by a run:

| Folder | Content |
|---|---|
| `results/` | `RunAll_<time>.txt` (log of all RunAll messages) and `RunAll_<time>.mat` (result struct) |
| `EV_RUN_<time>/` | Full data archive of one run (raw and cleaned data, V&V results, Excel files, figures, command log). Never overwritten |

---

## 3. Requirements

- **MATLAB R2024b** (the project was built in R2024b; other releases give a warning and the model may not open in older ones)
- Simulink
- Simscape
- Simscape Electrical
- Simscape Battery
- Windows with Microsoft Excel installed, only for the Excel files in the data archive (the simulation itself does not need Excel)

---

## 4. What RunAll does, step by step

| Step | Action |
|---|---|
| 1 | Finds the project folder (the folder where `RunAll.m` is), changes into it, sets the MATLAB path (run archives are left out), opens the log file in `results/` |
| 2 | Checks that all required files exist. Prints FOUND or MISSING and stops with a clear message if a required file is missing |
| 3 | Checks the MATLAB release and the Simulink / Simscape products |
| 4 | Runs `BLDCSpeedControlData.m` and prints the key values (target rpm, current limits, Kt, run time, pack capacity) |
| 5 | Closes any old copy of the model and reloads it from disk. Clears the results of any earlier run from the workspace |
| 6 | Calls the builder: model fix (buck snubber = exclude), then DAQ setup (LIVE tap, Black Box, callback hooks, model saved) |
| 7 | Compile check (update diagram). If the model does not compile, the Simulink error is printed and the run does not start |
| 8 | Starts the simulation. `[LIVE]` lines print every 0.1 s of simulation time and a progress line every 5 s of wall time. When the simulation stops, the builder archives the data into `EV_RUN_<time>/` |
| 9 | Verifies the result (see section 6) and prints the summary |

### Options

```matlab
RunAll                    % normal run
RunAll('Fixes', false)    % skip the buck snubber model fix
RunAll('Timeout', 1800)   % wait at most 1800 s of wall time for the simulation (default 3600)
```

`RunAll` returns a struct: `result.pass`, `result.warn`, `result.fail`, `result.checks` (table), `result.runDir`, `result.logFile`.

---

## 5. What you see in the Command Window

```
==============================================================
  EV DIGITAL TWIN - RunAll   <date and time>
==============================================================
[RunAll] 1. Project folder (auto-detected): ...
[RunAll] 2. Checking files ...
[RunAll] 3. Checking MATLAB ...
[RunAll] 4. Loading parameters (BLDCSpeedControlData.m) ...
[RunAll] 5. Loading models ...
[RunAll] 6a. Model fix: buck snubber -> exclude ...
[RunAll] 6b. DAQ setup ...
[RunAll] 7. Compile check (update diagram) ...
[RunAll] 8. Starting simulation ...
   [LIVE] lines from the model every 0.1 s of simulation time
[RunAll] 9. Verifying the result ...
==============================================================
  SUMMARY   PASS n   WARN n   FAIL n
==============================================================
```

---

## 6. The checks (step 9)

Each check ends as **PASS**, **WARN** or **FAIL**.

| Check | Rule | If it fails |
|---|---|---|
| Black Box size | 301 x 8 samples (1 ms spacing, t_stop = 0.3 s) | FAIL |
| Black Box NaN | no NaN values | FAIL |
| Reached t_stop | last time = t_stop | FAIL |
| Initial state | SOC > 0.999, rpm = 0, battery voltage 45-55 V | FAIL |
| Final speed | 2900-3000 rpm (target 2950) | FAIL |
| Torque per amp | 0.107 N*m/A +/- 5 % (last 10 ms) | WARN |
| Peak motor current | <= 1.1 x I_peak (45 A limit) | FAIL |
| Motor current vs I_cont | mean of last 20 ms <= 30 A | WARN |
| SOC vs coulomb count | SOC drop is 0.8-1.25 x the charge drawn | WARN |
| Black Box vs archive: motor current | within 2 % | FAIL |
| Black Box vs archive: battery voltage | within 0.2 V | FAIL |
| Black Box vs archive: RPM | within 0.5 % | FAIL |
| Black Box vs archive: battery current | within 10 % | WARN |
| Power balance (Black Box and archive) | Pdc / Pbatt = 0.85-1.02 | WARN |

**How to read the result**

- `RESULT: ALL CHECKS PASSED`: everything is fine.
- `RESULT: OK, with n warning(s)`: the run is valid, but read the WARN lines.
- `RESULT: n CHECK(S) FAILED`: something is wrong; the FAIL line says what and gives the numbers.

---

## 7. Model summary

| Item | Value |
|---|---|
| Motor | APBA80L048030-EB, 48 V, 3000 rpm, Kt = 0.107 N*m/A |
| Current limits | I_cont = 30 A, I_peak = 45 A (I^2*t limiter) |
| Battery | 13S10P pack, 50 Ah, full-charge voltage about 54.5 V, pack resistance about 0.011 Ohm |
| Speed target | 2950 rpm (window 2900-3000 rpm), ramp 13000 rpm/s |
| Load | 1 kW at about 3000 rpm = 3.18 Nm (0 Nm to 0.23 s, ramp to 3.18 Nm at 0.28 s) |
| Run length | t_stop = 0.3 s |
| Drivetrain | gear ratio 11, wheel radius 0.25 m |
| Controller | speed PI Kpw = 0.05, Kiw = 10; voltage PI Kiv = 1.5 |
| Black Box | `EV_BlackBox` subsystem, 8 channels at 1 ms: Vbatt_V, Ibatt_A, SOC, RPM_rpm, Idc_f_A, Vdc_m_V, omega_wheel, Torque_Nm. Logged to `EV_BlackBox_log` |

To change a parameter, edit `BLDCSpeedControlData.m` and run again. Do not change parameters inside the model.

---

## 8. Reading the results by hand

After a run, these variables are in the MATLAB workspace:

```matlab
bb  = EV_BlackBox_log;                                        % timeseries, 301 x 8
lab = get_param('BLDCSpeedControl_EV_Layout_v2/EV_BlackBox','UserData');   % column names
disp(array2table(bb.Data([1 end],:), 'VariableNames', lab))   % first and last row
C   = EV_DAQ_Clean;                                           % cleaned 1 ms archive table
```

Other entry points of the builder (normally not needed, `RunAll` calls them):

```matlab
EV_DAQ_Builder_V7                       % setup and run
EV_DAQ_Builder_V7('Run', false)         % setup only
EV_DAQ_Builder_V7('PostProcess')        % archive the data currently in the workspace
EV_DAQ_Builder_V7('BlackBox')           % build or verify the Black Box
EV_DAQ_Builder_V7('BlackBox','remove')  % remove the Black Box
EV_DAQ_Builder_V7('SysID')              % offline system identification on EV_BlackBox_log
```

---

## 9. Known points (not errors)

- **Ramp warning:** `Ramp 13000 rpm/s needs 30.4 A > I_cont = 30 A`. The ramp briefly needs a little more than the continuous current. To remove the warning set `rpm_ramp` <= 11500 and `t_stop` >= 0.31 in `BLDCSpeedControlData.m`.
- **Motor current at the end is above 30 A (about 33 A).** It is below I_peak = 45 A. The load only reaches 3.18 Nm at 0.28 s, so the current is still settling at 0.3 s.
- **Not logged:** `rpm_ref` and temperature are not in the model. They show as NOT_AVAILABLE and are never invented.
- **Battery current WARN:** the Black Box and the archive can differ in battery current (the Black Box samples the switching current once per millisecond). The power-balance lines show which one is physically consistent.
- **"The timeseries Variable Editor will be removed in a future release"** is a MATLAB message and is harmless.
- **No backup files:** the builder no longer creates `*_backup_before_DAQ.slx` or `*_before_stepN.slx`. If you want a backup, copy the project folder yourself (or use Git).

---

## 10. Troubleshooting

| Message or problem | What to do |
|---|---|
| `MISSING <file>` in step 2 | Copy that file into the same folder as `RunAll.m` and run again |
| `Cannot find BLDCSpeedControl_EV_Layout_v2.slx` or a folder window opens | `RunAll.m` is not in the model folder. Move it there, or select the folder in the window |
| `Model ... is still running` | Press STOP in Simulink, wait for Ready, run again |
| `Compile check` FAIL | Read the Simulink message printed. Usually a missing product (Simscape Electrical / Battery) or a different MATLAB release |
| `the simulation never started` | Open the Simulink Diagnostic Viewer; a block parameter is invalid |
| Excel errors during archive | Excel is not installed or not on Windows. The data (.csv, .mat) is still written |
| Model will not open in an older MATLAB | Use R2024b |
| Slow run | A 0.3 s simulation takes about 3 minutes of wall time; the archive step adds time |

---

## 11. Change notes

- **RunAll.m**: new one-click runner with automatic path detection, file / product checks, simulation, verification and log file.
- **EV_DAQ_Builder_V7.m**: backup-file creation removed. The model is saved by the buck snubber fix only when something is changed.
- Hard-coded path: inside `EV_DAQ_Builder_V7.m`, function `evRunAll` still has the path `C:\Users\shubh\...`. `RunAll.m` does not use it. If you call `EV_DAQ_Builder_V7('RunAll')` directly, change that line to `root = evFindRoot(MDL);`.

---

## 12. References

Journal DOIs were checked against their DOI records on 9 Oct 2026. Numbers match the Word report.

1. Grieves, M. and Vickers, J. (2017). Digital Twin: Mitigating Unpredictable, Undesirable Emergent Behavior in Complex Systems. In: Kahlen, F.-J., Flumerfelt, S., Alves, A. (eds) Transdisciplinary Perspectives on Complex Systems. Springer, Cham, pp. 85-113. <https://doi.org/10.1007/978-3-319-38756-7_4>
2. Glaessgen, E. H. and Stargel, D. S. (2012). The Digital Twin Paradigm for Future NASA and U.S. Air Force Vehicles. 53rd AIAA/ASME/ASCE/AHS/ASC Structures, Structural Dynamics and Materials Conference, Honolulu, HI, AIAA Paper 2012-1818. <https://ntrs.nasa.gov/citations/20120008178>
3. Kritzinger, W., Karner, M., Traar, G., Henjes, J. and Sihn, W. (2018). Digital Twin in manufacturing: A categorical literature review and classification. IFAC-PapersOnLine 51(11), 1016-1022. <https://doi.org/10.1016/j.ifacol.2018.08.474>
4. Li, W., Rentemeister, M., Badeda, J., Jost, D., Schulte, D. and Sauer, D. U. (2020). Digital twin for battery systems: Cloud battery management system with online state-of-charge and state-of-health estimation. Journal of Energy Storage 30, 101557. <https://doi.org/10.1016/j.est.2020.101557>
5. Wu, B., Widanage, W. D., Yang, S. and Liu, X. (2020). Battery digital twins: Perspectives on the fusion of models, data and artificial intelligence for smart battery management systems. Energy and AI 1, 100016. <https://doi.org/10.1016/j.egyai.2020.100016>
6. Fuller, A., Fan, Z., Day, C. and Barlow, C. (2020). Digital Twin: Enabling Technologies, Challenges and Open Research. IEEE Access 8, 108952-108971. <https://doi.org/10.1109/ACCESS.2020.2998358>
7. Lu, L., Han, X., Li, J., Hua, J. and Ouyang, M. (2013). A review on the key issues for lithium-ion battery management in electric vehicles. Journal of Power Sources 226, 272-288. <https://doi.org/10.1016/j.jpowsour.2012.10.060>
8. MathWorks. BLDC Speed Control (Simscape Electrical example documentation). The project model is based on this example. <https://www.mathworks.com/help/sps/ug/bldc-speed-control.html>
9. Krishnan, R. (2010). Permanent Magnet Synchronous and Brushless DC Motor Drives. CRC Press, Boca Raton. (book)
10. MathWorks. Create Battery Pack (Simscape Battery documentation, Battery Builder workflow). <https://www.mathworks.com/help/simscape-battery/create-battery-pack.html>
11. Erickson, R. W. and Maksimovic, D. (2020). Fundamentals of Power Electronics, 3rd edition. Springer, Cham. (book) <https://doi.org/10.1007/978-3-030-43881-4>
12. Ng, K. S., Moo, C.-S., Chen, Y.-P. and Hsieh, Y.-C. (2009). Enhanced coulomb counting method for estimating state-of-charge and state-of-health of lithium-ion batteries. Applied Energy 86(9), 1506-1511. <https://doi.org/10.1016/j.apenergy.2008.11.021>
13. Plett, G. L. (2004). Extended Kalman filtering for battery management systems of LiPB-based HEV battery packs. Journal of Power Sources 134(2), 252-261. <https://doi.org/10.1016/j.jpowsour.2004.02.031>
14. Van Overschee, P. and De Moor, B. (1994). N4SID: Subspace algorithms for the identification of combined deterministic-stochastic systems. Automatica 30(1), 75-93. <https://doi.org/10.1016/0005-1098(94)90230-5>
15. Ljung, L. (1999). System Identification: Theory for the User, 2nd edition. Prentice Hall, Upper Saddle River. (book)
16. OASIS (2019). MQTT Version 5.0, OASIS Standard. <https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html>
