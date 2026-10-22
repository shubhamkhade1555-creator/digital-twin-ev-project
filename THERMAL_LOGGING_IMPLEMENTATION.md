# Thermal logging implementation notes

Branch: `feature/temperature-logging`

## Scope of this code change
- Adds provisional thermal parameters to `BLDCSpeedControlData.m`.
- Adds DAQ definitions for `BatteryTemperature`, `BatteryTemperatureMax`, and `MotorTemperature`.
- Adds optional black-box channels `Tmotor_C` and `Tbatt_C`, sourced only from the global tags `MON_Tmotor_C` and `MON_Tbatt_C` or the matching logged signals.
- Adds motor temperature and battery maximum-temperature plots.
- Allows `RunAll.m` to accept either the existing 8-channel black box or the 10-channel temperature-extended black box. Temperature channels are not added to the SysID fit inputs/outputs.
- Adds thermal channels to the master data workbook and thermal report group.

## Provisional parameters (not validated)
- Ambient: 25 degC.
- Housing convection conductance: 18 W/(m^2 K) × 0.0407 m^2 = 0.7326 W/K, estimated.
- Battery cell thermal capacitance: 100 J/K per cell, provisional model value; a 53 J/K estimate is not adopted without a 21700-specific source.
- Motor resistance remains 0.1 ohm in the existing model to avoid changing controller behaviour in this pass. The 0.0215 ohm datasheet comparison remains documented in the parameter file.
- Temperature gains/biases remain unity/zero placeholders.

## Required Simulink GUI work (not performed by repository code)
1. Wire a valid ambient-temperature boundary and convection path to the existing motor thermal port.
2. Connect a Simscape Temperature Sensor output through a **PS-Simulink Converter** to the logging signal.
3. Verify the actual dimensions, units, and meaning of `MON_Tbat_Cell` before deriving average/max temperature; do not blindly divide by 130.
4. Provide scalar Celsius signals/logging variables `log_Tmotor_C`, `log_Tbatt_C`, and `log_TbattMax_C`, plus global tags `MON_Tmotor_C` and `MON_Tbatt_C`.
5. Do not create duplicate battery or motor blocks.

## Verification status
No MATLAB/Simulink compile or simulation was run by this code change. Until the model signals exist, temperature entries are expected to remain unavailable and the optional black-box layout may remain at 8 channels. The new 10-channel path must be tested in MATLAB R2024b before declaring thermal logging operational.
