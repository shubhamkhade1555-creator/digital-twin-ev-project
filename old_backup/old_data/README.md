# EV Digital Twin - final files

| File | Role |
|---|---|
| Create_Simulation.m | FILE 1 - builds BLDCSpeedControl_EV_Layout_FINAL.slx (battery 5 Ah, black box, fast set-up, benchmark) |
| Run_Simulation_Log.m | FILE 2 - fast run + logs (CSV 1 ms / 100 ms, MAT, Summary, plot) |
| Run_Simulation_Live.m | FILE 3 - run + live app + MQTT + CSV + logs, all at once |
| EV_BlackBox_App.m | live desktop app (used by file 3, also runnable alone) |
| BLDCSpeedControlData.m | motor, control, drivetrain AND battery pack parameters |
| BLDCSpeedControlInput.mat | speed reference / load torque for the Signal Editor |
| BLDCSpeedControl_EV_Layout_v2.slx | source model (read once by file 1) |
| Batteries2.slx, Batteries2_lib.slx | battery model + library |

NOT in this zip: the folder +Batteries2 (it was never uploaded to me).
Copy YOUR existing +Batteries2 folder next to these files.

## Steps (MATLAB)
    cd('C:\Users\shubh\OneDrive\Documents\MATLAB\EV_DigitalTwin')   % this folder
    Create_Simulation                 % once: builds FINAL.slx, prints measured speed-ups
    Run_Simulation_Log                % fast run + logs  (or 'Profile','turbo')
    Run_Simulation_Live               % live app + logs  (MQTT: Run_Simulation_Live('MQTT',true,'Broker','...'))

Logs: Simulation_Logs/Run_<time>/ and Simulation_Logs/Live_<time>/
Close the app before running Run_Simulation_Log (same model).

## Speed
Profiles: normal < fast (Accelerator, no scopes/logging) < turbo (fast + Ts=2e-5).
The speed-up is NOT promised: Create_Simulation measures it on your PC.
Turbo changes the solver step - compare its results with 'fast' before trusting it.
Accelerator needs a C compiler (mex -setup); otherwise the script falls back to Normal.
The live run must use Normal mode, so it is slower than Run_Simulation_Log.

## Not tested
Written without MATLAB access. Send the first error text if anything fails.
