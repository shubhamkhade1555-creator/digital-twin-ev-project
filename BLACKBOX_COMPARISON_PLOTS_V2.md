# EV Black-Box Comparison Plots V2

## Scope

This is a MATLAB R2024b **plot-generation workflow**, not a dashboard. It keeps the Simulink model, data acquisition, System Identification, validation and archives. It replaces the default legacy figure-generation calls with a new set of clearly separated figures.

The old plot functions are retained in source as an opt-in rollback path; they are not run by default when `EV_BlackBox_PlotsV2` is unset or true. The simulation and logging code is not deleted.

## Run

Run a normal simulation / `RunAll` with the new files on the MATLAB path. The DAQ builder runs SysID first and then calls:

```matlab
EV_BlackBox_ComparePlotsV2(Clean, runDir)
```

Manual run for an existing run folder:

```matlab
Rplots = EV_BlackBox_ComparePlotsV2([], fullfile(pwd, ...
    'Simulation Logs', 'EV_RUN_YYYYMMDD_HHMMSS'));
```

Output directory:

```
Simulation Logs/EV_RUN_<timestamp>/Figures_BlackBox_V2/
  Battery/
  Motor/
  SystemIdentification/
  PLOT_MANIFEST.txt
```

The output root is also returned in `Rplots.outputDir`.

## Plot groups

### Battery
- Simulation pack voltage
- Simulation discharge current
- SOC if present in the clean data
- Temperature only if a real temperature signal is logged
- Cell voltage only if a cell voltage signal is actually present in the clean data

### Motor
- Reference RPM versus actual simulated RPM if both are present
- Motor current, motor torque and DC-link voltage when available

These are Simulink plant signals. They are not labeled as black-box motor predictions because the current identified model takes RPM and motor current as inputs and predicts battery voltage and battery current only.

### System Identification
- Validation measured output versus one-step prediction and free-run simulation for battery voltage
- Same comparison for battery current
- Residual time plots for both outputs
- Model-order raw-fit comparison if the saved order sweep is available
- CSV of one-step and free-run RMSE, MAE and bias

The prediction data are produced using the normalized `Zv` dataset stored by `EV_SysID_Auto`. Predictions are converted back to engineering units with the saved `Ys` and `Y0`. The script does not feed physical RPM/current values directly into the normalized model.

## Source truth and interpretation

- The current linear model's inputs are `RPM` and `MotorCurrent`; outputs are `Vbatt_V` and `Ibatt_A`.
- SOC remains outside the identified linear model and should be labeled as a Coulomb-counting / simulation signal.
- Temperature is not fabricated. If there is no actual logged thermal signal, no temperature figure is created.
- Motor RPM/current/torque are shown as plant signals, not as black-box outputs.
- This V2 generator does not create orange illustrative reference traces.
- Stable poles or small RMSE alone do not mean the model is accepted. Negative raw fit and the report's model acceptance verdict must remain visible and must not be overwritten by the plotting script.

## Legacy graph rollback

To opt into the legacy plotting path for a MATLAB session:

```matlab
EV_BlackBox_PlotsV2 = false;
```

To return to V2:

```matlab
clear EV_BlackBox_PlotsV2
% or set EV_BlackBox_PlotsV2 = true
```

Fast DAQ mode skips graph generation. No App Designer file or dashboard is created by this version.

## Verification status

The source changes are committed on the feature branch for review. The MATLAB execution check must still be performed in the user's MATLAB R2024b environment because the GitHub connector cannot execute Simulink or MATLAB here.
