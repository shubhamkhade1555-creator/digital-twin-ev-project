# Black-Box Model-Based Real-Time Digital Twin for Electric Vehicle Battery & BLDC Powertrain

[![MATLAB](https://img.shields.io/badge/MATLAB-R2024b-blue.svg)](https://www.mathworks.com/products/matlab.html)
[![Simulink](https://img.shields.io/badge/Simulink-Simscape_Battery-orange.svg)](https://www.mathworks.com/products/simulink.html)
[![Architecture](https://img.shields.io/badge/Digital_Twin-Level_2_Digital_Shadow-brightgreen.svg)]()
[![License](https://img.shields.io/badge/License-MIT-blue.svg)]()

> **Project Title:** Design and Development of a Black-Box Model-Based Real-Time Digital Twin for an Electric Vehicle Battery Using MATLAB/Simulink  
> **Repository:** `shubhamkhade1555-creator/digital-twin-ev-project`

## Automatic comparison graphs (no extra MATLAB command)

Comparison graph generation is integrated into the existing `EV_DAQ_Builder_V7.m` StopFcn post-processing workflow. The same graph step runs automatically when you:

- use `RunAll`, or
- open the Simulink model and click **Run**.

No separate graph-generation command or extra MATLAB helper source file is required. Run outputs are saved under the current simulation's existing `Figures/Motor` folder. Existing battery and System Identification validation plots continue to be handled by the project's existing pipeline.

The integrated motor comparisons include RPM reference vs actual RPM and motor current vs the configured continuous/peak current limits. Motor voltage, torque/load, and DC-link reference comparisons are generated only when the required measured and reference channels are present in the cleaned DAQ table. Missing reference data is skipped rather than fabricated.

**Model boundary:** the current N4SID black-box model predicts battery voltage and battery current. Motor one-step/free-run prediction curves require a separately identified motor model; the plotting code does not mislabel measured plant channels as black-box motor predictions.

## Existing project pipeline

The project models a 48 V-class, 50 Ah, 13S10P lithium-ion battery pack, DC-DC converter, inverter, BLDC motor, and vehicle load in MATLAB/Simulink. The battery digital twin uses a discrete state-space model identified with N4SID. See the source scripts and run-specific validation reports for the exact baseline, data fields, and acceptance status.

## License

Distributed under the MIT License. See `LICENSE`.
