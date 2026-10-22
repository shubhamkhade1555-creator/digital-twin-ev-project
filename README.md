# Black-Box Model-Based Real-Time Digital Twin for Electric Vehicle Battery & BLDC Powertrain

[![MATLAB](https://img.shields.io/badge/MATLAB-R2024b-blue.svg)](https://www.mathworks.com/products/matlab.html)
[![Simulink](https://img.shields.io/badge/Simulink-Simscape_Battery-orange.svg)](https://www.mathworks.com/products/simulink.html)
[![Architecture](https://img.shields.io/badge/Digital_Twin-Level_2_Digital_Shadow-brightgreen.svg)]()
[![License](https://img.shields.io/badge/License-MIT-blue.svg)]()

> **Project Title:** Design and Development of a Black-Box Model-Based Real-Time Digital Twin for an Electric Vehicle Battery Using MATLAB/Simulink  
> **Repository:** `shubhamkhade1555-creator/digital-twin-ev-project`

## Unified production graphs

`EV_Graphs.m` is the dedicated source for normal Battery and Motor plots plus N4SID validation comparisons. It writes 300 dpi PNG and vector PDF figures where supported. Plots intentionally do not contain PASS/FAIL verdicts; those remain in the text/CSV validation reports. Missing signals and inadequate excitation are recorded in `Figures/Graph_Inventory.txt`.

The DAQ StopFcn invokes the graph source after data logging and battery N4SID identification. `RunAll.m` uses the same pipeline and avoids duplicate graph generation when the StopFcn already completed.

Manual testing (after the DAQ callback hooks have been installed):
- `EV_Graphs('help')`
- `EV_Graphs('run',0.1)`
- `EV_Graphs('run',0.2)`
- `EV_Graphs('run',0.4)`
- `EV_Graphs('run',0.5)`

Battery prediction plots use the saved battery N4SID model and its held-out validation data. Motor prediction plots are produced only if a separate motor N4SID model can be estimated from sufficiently informative logged data; otherwise the inventory explains why they were skipped.

## Existing project pipeline

The project models a 48 V-class, 50 Ah, 13S10P lithium-ion battery pack, DC-DC converter, inverter, BLDC motor, and vehicle load in MATLAB/Simulink. The battery digital twin uses a discrete state-space model identified with N4SID. See the source scripts and run-specific validation reports for the exact baseline, data fields, and acceptance status.

## License

Distributed under the MIT License. See `LICENSE`.
