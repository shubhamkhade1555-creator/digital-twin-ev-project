# Black-Box Model-Based Real-Time Digital Twin for Electric Vehicle Battery & BLDC Powertrain

[![MATLAB](https://img.shields.io/badge/MATLAB-R2024b-blue.svg)](https://www.mathworks.com/products/matlab.html)
[![Simulink](https://img.shields.io/badge/Simulink-Simscape_Battery-orange.svg)](https://www.mathworks.com/products/simulink.html)
[![Architecture](https://img.shields.io/badge/Digital_Twin-Level_2_Digital_Shadow-brightgreen.svg)]()
[![License](https://img.shields.io/badge/License-MIT-blue.svg)]()

> **Project Title:** Design and Development of a Black-Box Model-Based Real-Time Digital Twin for an Electric Vehicle Battery Using MATLAB/Simulink  
> **Repository:** `shubhamkhade1555-creator/digital-twin-ev-project`

## Comparison graph utility

Use `EV_MakeComparisonGraphs.m` to create one clearly named comparison figure per available channel and save both PNG and MATLAB FIG files to `EV_COMPARISON_GRAPHS/`. The utility avoids reusing the same actual-only plot as if it were a validation comparison.

### Run from MATLAB R2024b

```matlab
% First run the existing DAQ/simulation pipeline so EV_DAQ_Clean is available.
RunAll

% Battery black-box comparison: pass the identified idss model if available.
% Replace sysModel below with the actual model variable loaded from your .mat.
EV_MakeComparisonGraphs(EV_DAQ_Clean, sysModel);

% Or create plant/reference comparisons only when no battery model is loaded.
EV_MakeComparisonGraphs(EV_DAQ_Clean, []);
```

You can limit a plot set to a specific time window:
```matlab
opts = struct('OutputDir', fullfile(pwd,'EV_COMPARISON_GRAPHS_0p5s'), ...
              'ShowFigures', true, 'TimeRange', [0 0.5]);
EV_MakeComparisonGraphs(EV_DAQ_Clean, [], opts);
```

### Comparison semantics

- **Battery voltage/current:** when an identified battery state-space model is supplied, the validation plots overlay Simulink measurements, black-box one-step prediction, and black-box free-run simulation.
- **Motor RPM:** actual speed is compared against the logged RPM reference/setpoint.
- **Motor current:** actual current is compared against a logged current reference or limit if that signal exists.
- **Motor voltage, torque/load and DC-link voltage:** comparisons are generated only when a matching reference/load channel exists in the logged data. Missing signals are skipped rather than fabricated.
- **Residuals:** generated only when measured and prediction channels are explicitly present in the input table.

**Important model boundary:** the currently documented identified black-box model predicts battery terminal voltage and battery current from RPM and motor-current inputs. It is not a motor black-box model. Motor-voltage/current/RPM/torque black-box one-step and free-run curves require separately identifying a motor model and logging the corresponding outputs; the plotting utility does not invent those predictions.

The plotting utility accepts a MATLAB table or timetable with a numeric time channel in seconds and numeric signal columns. Channel names are matched against explicit aliases in the script. If your DAQ uses different names, add those exact names to the corresponding alias list in `EV_MakeComparisonGraphs.m`.

## Existing project pipeline

The project models a 48 V-class, 50 Ah, 13S10P lithium-ion battery pack, DC-DC converter, inverter, BLDC motor, and vehicle load in MATLAB/Simulink. The battery digital twin uses a discrete state-space model identified with N4SID. See the source scripts and run-specific validation reports for the exact baseline, data fields, and acceptance status.

## License

Distributed under the MIT License. See `LICENSE`.
