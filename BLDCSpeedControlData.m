%% Parameters for BLDC Speed Control - EV digital twin (MERGED: motor + drivetrain)
% This ONE file replaces BLDCSpeedControlData.m + WheelDrivetrainData.m.
% The model PreLoadFcn calls BLDCSpeedControlData, so everything loads automatically.
% Base: MathWorks BLDCSpeedControl example (Copyright 2017-2023 The MathWorks, Inc.)
% Drop-in replacement for BLDCSpeedControlData.m (same file name, so the
% model PreLoadFcn picks it up automatically).
%
% DESIGN TARGET (from the user)
%  - Load = 1 kW at ~3000 rpm  ->  T = P/w = 1000/(3000*2*pi/60) = 3.18 Nm
%    (this is also the final value of the Signal Editor torque profile)
%  - Motor current between about 10 A and 30 A  (I_cont = 30 A)
%  - Speed target unchanged: 2950 rpm (window 2900-3000 rpm)
%
% CORRECTION OF AN EARLIER VERSION OF THIS FILE
%  The earlier version set Ke_ph = Kt/2 = 0.0535. That was wrong for the
%  Simscape BLDC block: with those table values the model produced only about
%  0.038 N*m per amp (measured from your scopes), not 0.107. The block's
%  effective torque constant is about 0.71 x the table amplitude (kappa below).
%  The original MathWorks motor (0.1528) therefore gives ~0.108 N*m/A, which
%  already matches the datasheet Kt = 0.107. Ke_ph is now Kt/kappa.
%  kappa is estimated from scope data - verify it (see the check at the bottom).

%% Motor datasheet: APBA80L048030-EB
Vmotor_nom = 48;       % Rated voltage                      [V]
rpm_nom    = 3000;     % Rated speed                        [rpm]
Kt         = 0.107;    % Torque constant                    [N*m/A]
I_cont     = 30;       % Continuous current (1 kW / 48 V class)   [A]
I_peak     = 45;       % Peak current limit (limiter ceiling)  [A]  (was 40; datasheet 40 A - 45 A used per your check)

%% !! FILL FROM DATASHEET (still MathWorks example values) !!
p    = 4;              % Number of pole pairs (check datasheet: poles/2)
Rs   = 0.1;            % Stator resistance per phase        [Ohm]
Ls   = 8e-5;           % Stator self-inductance per phase   [H]
Ms   = 1e-5;           % Stator mutual inductance           [H]
Jm   = 0.002;          % Rotor inertia (+ reflected load)   [Kg*m^2]

%% Back-EMF table amplitude derived from Kt (used by the script to set the BLDC block)
% kappa = effective torque constant of the Simscape BLDC block / table amplitude
% (about 0.71, estimated from the scope traces: 0.038 N*m/A / 0.0535 V*s/rad).
kappa      = 0.72;
Ke_ph      = Kt/kappa;                    % table amplitude [V*s/rad] (~0.151, original example 0.1528)
w_meas_rpm = 600;                         % speed at which emf_max is defined
emf_max_ev = Ke_ph*w_meas_rpm*2*pi/60;    % table amplitude at w_meas [V] (~9.5 V, original example 9.6 V)
psim       = 0.0175*(Ke_ph/0.1528);       % scaled with the same ratio as Ke

%% Battery pack  (Batteries2.slx / Batteries2_lib.slx / +Batteries2 - Simscape Battery Builder)
% The supplied pack is 13 series x 10 parallel with 27 Ah cells = 270 Ah (not 50 Ah).
% The module block already carries AHCell = 5 Ah (13S10P = 50 Ah); no run_EV.m override is needed.
%   OCV window 45.4 V (SOC 0) ... 54.5 V (SOC 100 %); pack resistance about 0.011 Ohm
% NOTE: this changes only the capacity (SOC behaviour). Cell resistance stays as in the supplied 27 Ah cell.
% For a physically exact 50 Ah pack, rebuild it in Battery Builder (e.g. 13S2P of 27 Ah = 54 Ah).
pack_Ah        = 50;                    % wanted pack capacity [Ah]
cells_series   = 13;
cells_parallel = 10;
cell_Ah        = pack_Ah/cells_parallel;  % 5 Ah per cell
Ah_pack        = cell_Ah*cells_parallel;

%% Control parameters
Ts  = 1e-5;     % Fundamental sample time            [s]  FINAL: 10 us = 2x faster than the old 5 us baseline
                % (verified: 15 PASS / 4 WARN / 0 FAIL, 2950.2 rpm, motor current -0.36 %, RPM error 0.017 %)
if exist('Ts_override','var') && ~isempty(Ts_override), Ts = Ts_override; end   % optional test hook (EV_SpeedBenchmark only); leave empty for normal runs
Tsc = 1e-4;     % Sample time for inner control loop [s]
Vdc = 48;       % DC link voltage / speed PI upper limit [V]
Kpw = 0.05;     % Proportional gain speed controller  [V/rpm]
Kiw = 10;       % Integrator gain speed controller    [V/(rpm*s)]
Kpv = 0.3;      % Proportional gain voltage controller
Kiv = 1.5;      % Integrator gain voltage controller

%% Speed reference (used by add_current_limiter_EV.m)
rpm_ref  = 2950;   % target speed, inside the 2900-3000 rpm window [rpm]
rpm_ramp = 13000;  % reference ramp rate [rpm/s] -> ref reaches 2950 rpm at 2950/13000 = 0.227 s 
t_stop   = 0.3;    % simulation stop time [s] = about 2.5-3 min of wall time at Ts = 1e-5 (0.5 s took 283 s measured). Must stay > rpm_ref/rpm_ramp (0.227 s)

%% Current limiter (motor current, from datasheet)
% Limit is I_peak while the I^2*t budget lasts, then falls back to I_cont.
t_peak     = 1;                                  % time allowed at I_peak [s] (assumption; the I^2*t switch will not be reached in a 0.3 s run)
Emax       = (I_peak^2 - I_cont^2)*t_peak;       % I^2*t budget [A^2*s]
Emax_thr   = 0.98*Emax;                          % switch-over threshold
Kpi        = 0.2;     % limiter PI proportional gain [V/A]  (was 0.05: too slow, current overshot to 65 A)
Kii        = 100;     % limiter PI integral gain     [V/(A*s)] (was 20)
Vlim_min   = 2;       % lowest voltage ceiling [V] - stops the limiter from latching the duty at 0
T_Ifilt    = 2e-3;    % current measurement filter   [s]

%% Load torque: 1 kW at ~3000 rpm = 3.18 Nm (profile is rewritten by EV_DAQ_Builder_V7: 0 Nm to 0.23 s, ramp to -3.18 Nm at 0.28 s, hold to t_stop)
load_scale  = 1;                                 % 1 = full profile (1 kW). Use <1 for a lighter test
T_load_end  = 3.18*load_scale;                   % final load torque [Nm]
T_cap_cont  = Kt*I_cont;                         % torque available at I_cont [Nm]

%% Sanity checks (run on every model load)
rpm_noload = Vdc/Kt*60/(2*pi);       % ideal no-load speed with effective Ke_ll = Kt
if rpm_noload < 1.2*rpm_ref
    warning('BLDC:speedReach', ...
        'No-load speed %.0f rpm is too close to the %.0f rpm target. Check Kt and Vdc.', ...
        rpm_noload, rpm_ref);
end
if T_load_end > T_cap_cont
    warning('BLDC:loadTooHigh', ...
        'Final load %.2f Nm needs %.1f A, above I_cont = %d A.', T_load_end, T_load_end/Kt, I_cont);
end
if Vdc > 13*4.19
    warning('BLDC:vdcTooHigh', 'Vdc is above the full-charge pack voltage (54.5 V).');
end
% Expected: 3.18 Nm / 0.107 = 29.7 A at full load. VERIFY after the first run:
% torque (TQ scope) divided by motor current (Current_limiter_scope) should be ~0.107.
% If it reads e.g. 0.100, set kappa = 0.71*0.107/0.100 and rerun.


%% =====================================================================
%%  DRIVETRAIN (was WheelDrivetrainData.m)   Gearbox -> Wheel -> Vehicle
%% =====================================================================
gear_ratio  = 11;        % [-]     motor rpm / wheel rpm
r_wheel     = 0.25;      % [m]     effective rolling radius
wheel_mass  = 1.5;       % [kg]    wheel + tyre mass (3-D wheel display)
wheel_width = 0.10;      % [m]     wheel width (3-D wheel display)

% derived (for printing / checks)
rpm_wheel_nom = rpm_ref/gear_ratio;                       % wheel speed at target [rpm]
v_vehicle_kmh = rpm_wheel_nom*2*pi/60*r_wheel*3.6;        % vehicle speed at target [km/h]
t_reach_ref   = rpm_ref/rpm_ramp;                         % time the reference reaches 2950 rpm [s]
if t_stop < t_reach_ref + 0.05
    warning('BLDC:stopTooShort', ['t_stop = %.3f s is too short: the reference only reaches %.0f rpm at %.3f s. ' ...
        'Keep at least 0.05 s of hold: t_stop >= %.3f s.'], t_stop, rpm_ref, t_reach_ref, t_reach_ref+0.05);
end
% acceleration feasibility: current needed to follow the ramp (rotor inertia only; add vehicle inertia if it is reflected in the model)
% V7.1: total inertia at the MOTOR shaft = rotor Jm + wheel inertia reflected through the gearbox (J_wheel/gear_ratio^2).
% The earlier check used Jm only (25 A) and hid that the ramp itself needs more than I_cont.
J_wheel   = 0.5*wheel_mass*r_wheel^2;                     % block 'Vehicle Mechanical Load' [kg*m^2]
J_tot     = Jm + J_wheel/gear_ratio^2;                    % [kg*m^2] at the motor shaft
I_accel   = J_tot*(rpm_ramp*2*pi/60)/Kt;                  % [A] needed only to follow the ramp (no external load)
rpm_ramp_max_cont = 0.9*I_cont*Kt/J_tot*60/(2*pi);        % ramp that needs 90 % of I_cont [rpm/s]
if I_accel > 0.8*I_peak
    warning('BLDC:rampTooSteep', 'Ramp %.0f rpm/s needs about %.1f A (limit %.0f A). Lower rpm_ramp.', rpm_ramp, I_accel, I_peak);
end
if I_accel > I_cont
    warning('BLDC:rampAboveCont', ['Ramp %.0f rpm/s needs %.1f A > I_cont = %d A (J_tot = %.5f kg*m^2). ' ...
        'Use rpm_ramp <= %.0f rpm/s or accept I_cont is exceeded during the ramp.'], rpm_ramp, I_accel, I_cont, J_tot, rpm_ramp_max_cont);
end
if I_peak <= I_cont
    warning('BLDC:limits', 'I_peak must be larger than I_cont (I2t limiter).');
end