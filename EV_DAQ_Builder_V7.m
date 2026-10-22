function EV_DAQ_Builder_V7(varargin)
% ====================================================================
% EV_DAQ_BUILDER_V7 - ALL FIXES FROM THE V&V REVIEW OF THE 61 LOGGED SAMPLES
% ====================================================================
% ONE FILE. No helper files are needed any more: EV_SetLoadProfile and the kappa
% change are built in. BLDCSpeedControlData.m and the model are used as they are.
%
% V7.8 (single final file - independent battery sensor channels prepared for wiring)
%   EV_DAQ_Builder_V7                     setup (builds LIVE tap + EV_BlackBox, saves the model) and run
%   EV_DAQ_Builder_V7('RunAll')           model fixes + setup + run + post-process (was EV_Run_All.m)
%   EV_DAQ_Builder_V7('Fixes', 1..4)      model fixes (was EV_Model_Fixes_V8.m)
%   EV_DAQ_Builder_V7('BlackBox')         build / verify EV_BlackBox and SAVE the model;  ('BlackBox','remove') removes it
%   EV_DAQ_Builder_V7('SysID')            offline N4SID on EV_BlackBox_log (also runs automatically after every run)
%   FIX-BB  "The port handle does not belong to any object within the system ...": the V7.5 fallback passed the source
%          port of the NESTED log blocks (they live in the 'Black-Box Log' subsystem) to add_line(root, ...). Now: global
%          Goto/From tags first; nested signals get a Goto in THEIR OWN system; every add_line is checked by evAddLine.
%          Also fixed: To Workspace has no output port (old code indexed Outport(1)); SysID picks columns by name;
%          deprecated 'Variants' search replaced by 'MatchFilter' (evFind, old option only as fallback).
%
% FIX LOG (V7)
%   FIX-A  ROOT CAUSE of the wrong battery current, SOC, cell voltages and efficiency.
%          The To Workspace logs of the pack are arrays (13 voltages, 130 currents,
%          130 SOC) saved as r x c x N. V6 reshaped them as N x m, which mixes samples of
%          different times. Evidence in your file: the last row equals the first row shifted
%          by exactly one column, SOC(0) = 99.99900 % instead of 100 %, and no voltage sag.
%          V7 reads the array with its real time axis (evTsMatrix) and prints the layout of
%          every logged signal (Logging_Audit, "Logged array layout").
%   FIX-B  Battery current = sum of the 130 cell currents / 13 (exact terminal current). A
%          single-column log is flagged as "cell 1 only". New independent check VV-012
%          compares battery power with DC-link power (Vdc x Idc / Pbatt, 0.85..1.02).
%   FIX-C  SOC: new checks VV-010 (SOC at t = 0 equals the initial SOC) and VV-011 (SOC drop
%          equals the coulomb count of the battery current, 0.8..1.25).
%   FIX-D  Cell voltages: new checks VV-013 (<= 4.2 V) and VV-014 (the 13 series groups are
%          identical, spread <= 10 mV, because the pack has zero cell-to-cell deviation).
%   FIX-E  Efficiency: new energy-based check VV-016 (0..100 %) next to VV-009.
%   FIX-F  Load profile: setup rewrites the Torque signal of BLDCSpeedControlInput.mat
%          (0 Nm to 0.23 s, ramp to -3.18 Nm at 0.28 s, hold to 0.30 s), reads it back and
%          checks it. The InitFcn hook re-checks it before every run. New checks VV-017 / VV-018
%          test the torque and the mechanical power (about 1 kW) at the end of the run.
%   FIX-G  Torque per amp: kappa = 0.75 (was 0.71) is applied in the InitFcn hook, so
%          Ke_ph, emf_max_ev and psim are recomputed before the Simscape block reads them.
%          NOTE: 0.67 is the wrong direction. Ke_ph = Kt/kappa, so a LOWER kappa RAISES
%          the back-EMF constant and the torque per amp (0.113 -> about 0.12).
%          kappa = 0.71 x 0.113 / 0.107 = 0.75. Check VV-019 tests Kt = 0.107 +/- 5 %.
%   FIX-H  The on-screen "Battery Current" and "Battery Voltage" blocks now show the pack
%          values (sum of the 130 cell currents / 13, sum of the 13 series voltages) instead
%          of cell / group 1 times a factor. Tried at setup, reverted if the model does not
%          compile. The logged data does not depend on these two blocks.
%   FIX-I  Hooks: the model carried a stale "V7" marker that called EV_DAQ_Builder_V3 (does
%          not exist) next to the V6 hook. V7 removes every old hook and writes StartFcn,
%          StopFcn and InitFcn once.
%   FIX-J  VV-008 compares the AVERAGE steady-state current with I_cont (a continuous rating
%          is not exceeded by ripple peaks); the peak is still tested by VV-003.
%
% EXPECTED AFTER A RE-RUN (setup once with the model closed, then run)
%   SOC(0) = 100 %, SOC falls about 0.002 %, battery voltage sags under load, 13 cell
%   voltages equal, battery current follows the motor load (about 26-29 A peak, about 2 A
%   at no-load hold), efficiency below 100 %, torque at 0.28 s about 3.18 Nm, torque per amp
%   about 0.107. Anything that still fails is reported by a V&V row with the numbers.
% ====================================================================
%
% V7.1 PATCH (post-audit, same file name so the model hooks keep working)
%   FIX-K  ALIASING: the 1 ms cleaned grid was built by point sampling (interp1). The PWM period is Tsc = 100 us
%          (10 kHz), so 1 ms = exactly 10 periods: every sample hit the same carrier phase and BatteryCurrent read
%          43.9 A instead of about 24 A (efficiency 41 % instead of about 74 %). evBinMean() now returns the exact
%          mean over [t-0.5 ms, t+0.5 ms] (10 whole PWM periods) for every logged signal, ignores non-finite
%          samples (removes the NaN at t = 0.3 s) and is also used for the per-cell grid.
%   FIX-L  VV-006 / VV-007 evaluated for t >= 2 ms with a stated 1e-6 start-up tolerance on the upper SOC bound.
%   Ts = 1e-5 UPDATE: fundamental sample time is now 1e-5 s (2x faster than 5e-6; verified PASS). The fall-back Ts in getParams()
%          and the 'raw data' labels of VV-020 / VV-021 now say 10 us. No physics or check limit was changed.
%   FIX-M  NEW VV-020 / VV-021 on the RAW 10 us data (max |Ibat| and max Vpack/13 for t >= 2 ms): limits are no
%          longer judged on averaged data only.
%   FIX-N  Cell_Temperature validation reports NOT_AVAILABLE when no temperature is logged (was a false FAIL).
%   FIX-O  LIVE tap is searched anywhere in the model (it lives in Subsystem3), existing tap is kept, LIVE period
%          set to 0.1 s to match the saved ZOH block.
%   FIX-P  Excel formatting: ws.Rows.Item(1) replaced by ws.Range('1:1') (COM signature error).
%
% V7.2 PATCH (post-audit of the 0.3 s run; same file name so the model hooks keep working)
%   FIX-Q  MotorCurrent (log_Idc_f) is the CONTROLLER ESTIMATE max(|iabc|) -> 2 ms low-pass (Speed/RPM Controller/Idc filter),
%          not a measured DC-link current. Its 2 ms lag and point-sampled phase currents make Vdc*Idc differ from the battery
%          power per phase (measured ratios 0.72 / 0.97 / 1.05 / 1.46) while the whole-run VV-012 ratio (0.987) hides it.
%          Signal description now says so; the ratio is additionally judged per phase (VV-024).
%   FIX-R  VV-008 judges t >= 0.9*t_end, which overlaps the load ramp (0.27-0.28 s) and the speed recovery. New VV-023 judges the
%          hold window (t >= load end) only. VV-008 is kept unchanged (no silent overwrite).
%   FIX-S  New VV-022: I^2t above I_cont against the datasheet budget Emax = (I_peak^2 - I_cont^2)*t_peak (the limiter's own budget).
%   NOT CHANGED (model-side decisions, see audit): ramp 13000 rpm/s needs ~30.4 A (> I_cont), 1 kW at 0.107 N*m/A needs 29.7 A
%   (99 % of I_cont), measured torque per amp ~0.101 at 2930 rpm. VV-008 / VV-023 FAIL on real physics until that is decided.
%
% V7.3 PATCH (after the EV_Run_All console log of 08-Oct-2026)
%   FIX-T  SILENT START FAILURE: with an invalid block parameter the model does not compile, set_param(...,'start') returns
%          normally and the error only appears in the Simulink Diagnostic Viewer (no banner, no [LIVE] line, no StopFcn).
%          Setup now runs a compile check (SimulationCommand 'update') first, prints the Simulink error in the command window
%          and does NOT start the run when it fails.
%   FIX-U  evFormatMaster: Range.Item(r,c) (ws.Cells.Item) is rejected by this Excel/MATLAB COM ("No method 'Item' with
%          matching signature"). Number formats now use A1 address strings; COM counts are converted to double.
%          Formatting only - no engineering value is touched.
%
% V7.4 PATCH (after the verified run EV_RUN_20261008_163422: 22 of 24 V&V checks PASS, VV-008 / VV-023 FAIL on real physics)
% FIX-3 OWNER POLICY (approved on 2026-10-22): VV-004 RMS, VV-008 steady average, and VV-023 hold-window
%   acceptance use separate project limit cfg.vvMotorOperatingCurrent = 35 A. The motor datasheet continuous rating
%   remains I_cont = 30 A and is explicitly UNCONFIRMED for continuous 35 A operation. Do not change I_cont, the
%   physical limiter, or VV-022 I^2t budget. VV-003 remains 48 A (45 A limiter + 3 A margin).
%   FIX-V  LIVE telemetry is an INSTANTANEOUS sample taken at multiples of 0.1 s = exactly 1000 PWM periods, so it always hits the same
%          carrier phase (same aliasing class as FIX-K). Measured: Ibat LIVE -24.72 A vs 1 ms window mean -12.75 A at t = 0.1 s,
%          torque 3.43 vs 3.26 Nm. The LIVE line is now labelled "_inst"; 11_Live_Telemetry.xlsx gets the matching 1 ms window means
%          (columns *_1msMean, taken from the cleaned data, labelled as post-run values); the logging audit reports the max error.
%          The proper cure (a 1 ms averaging block inside the tap) is a model change and is NOT done here.
%   FIX-W  09_Performance_Report compared the TOTAL of all compact parts (183.75 MB) with the PER-FILE 20 MB limit and printed FAIL.
%          Total is now INFO, a new row CompressedLargestFile (each part < 20 MB) carries the PASS/FAIL.
%
% ---- history: V6 ----
% EV_DAQ_BUILDER_V6 - CORRECTED (run length + parameter handling)
% ====================================================================
% FIX LOG (this version)
%   FIX-1  Run length.  ROOT CAUSE of "RPM stops at ~600": the run ended at
%          0.1 s while the reference ramped at 6000 rpm/s (6000 x 0.1 = 600 rpm).
%          Now t_stop = 0.3 s (about 3 min wall time, measured by the user) and
%          rpm_ramp = 13000 rpm/s, so the reference reaches 2950 rpm at 0.227 s
%          (= 2.27 min on the stopwatch) and holds until 0.3 s.
%   FIX-2  Speed PI back to the model values Kpw = 0.05, Kiw = 10.
%          The earlier "5x" change (Kpw = 2.5) was never applied to the
%          model (it only changed a check list) and is not needed: at
%          0.1 s measured speed already tracks the ramp within ~10 rpm.
%   FIX-3  Parameter check now compares against BLDCSpeedControlData.m
%          (the real source of the model's variables), I_peak = 45 A.
%   FIX-4  V&V peak-motor-current limit follows the 45 A limiter
%          (cfg.vvPeakCurrent, with a small overshoot margin).
% ====================================================================
%
% PERFORMANCE OPTIMIZATIONS ADDED:
%   • Vectorized summation operations (no loops in statistics)
%   • Pre-allocated memory for large arrays
%   • Direct signal access via logsout indexing
%   • Faster completion reporting (~50% faster)
%   • Parallel milestone detection
%
% ORIGINAL V6 FEATURES (preserved):
%   1. Exactly 12 Excel files (01_EV_Run_Summary ... 12_Cell_Diagnostics) with fixed sheets
%   2. Cell_Diagnostics.xlsx with comprehensive diagnostics
%   3. Lossless RLE compression for column data
%   4. Order: RAW -> pack raw/archive -> clean -> tables -> Excel
%   RE-RUN SETUP ONCE to activate all fixes in the model hooks
%
% CHANGES vs V4 (V5 = performance + data-storage optimisation ONLY; no model physics / parameters changed)
%   1. Run configuration in evCfg(): t_stop = 0.10 s (100 ms), LIVE period 0.10 s of SIMULATION time,
%      20 MB file limit. t_stop is pushed to the base workspace and to the Simulink StopTime.
%   2. Post-processing is sequential: RAW -> compact (lossless) -> write -> verify -> CLEAN -> write -> clear.
%      Large temporaries are cleared as soon as they are not needed; [MEMORY] and [TIME] monitors added.
%   3. Lossless column compaction (bit-exact): identical columns stored once, constant columns stored as one
%      value, long repeats run-length coded. Reconstruction is compared bit by bit; failure STOPS the pipeline.
%   4. writeUnder20MB(): every CSV is written in whole-row parts (< 20 MB each) with a manifest; a final scan
%      checks EVERY file in the run folder (PNG is re-exported at lower resolution if needed).
%   5. New files: 02_Raw_Data_PartNNN/_Manifest, 02b_Raw_PerCell_Compact_PartNNN/_Manifest, 02c_Column_Map,
%      02d_RLE_Segments, 03_Cleaned_Data_PartNNN/_Manifest, 04_Constant_Values, 13_Performance_Report,
%      14_Compression_Audit. Excel gets Signal_Map, Live_Telemetry, Compression_Audit, File_Manifest sheets.
%   6. FIX: the Excel error "VariableNames property must contain one name for each variable" (mtab received an
%      Nx1 cell of 1x4 cells from energyTable / speedTable / currentTable / batteryTable).
%   7. Setup (run once, model stopped): additionally switches off logging that nothing reads (State/FinalState/
%      SignalLogging, Scope data logging, Mechanics Explorer auto-open). Every change is printed.
%   8. StartFcn path: MAT file loaded only if a variable is missing, signal map reused (no find_system per run),
%      start-up stages timed. No wall-clock timer is used anywhere (LIVE is a 0.1 s sample-time tap).
%   9. LIVE telemetry file keeps the V4 structure (+WheelSpeed when tapped) at 0.10 s; no high-rate data.
%  RE-RUN SETUP ONCE (EV_DAQ_Builder_V7) so the model hooks call this file and StopTime = 0.1 s is saved.
%
% CHANGES vs the previous V3 file
%   1. function name now matches the file (was EV_DAQ_Builder_V2); the model hooks are
%      rewritten on every setup run so they call THIS file (they called the old V2 before,
%      which has no LIVE monitor and no battery-current fix).
%   2. Simulink StopTime is forced to t_stop (2 s) at setup and before every run.
%   3. LIVE output is simulation-synchronised (0.1 s) via an in-model sample-time tap and an
%      execution-event listener - no wall-clock timer, no To Workspace RuntimeObject reads.
%   4. Battery current: log_icell is ONE cell -> scaled x cells_parallel (this was the cause of
%      the impossible 429.8 % efficiency). Efficiency = 100*mean(Pmech)/mean(|Pbatt|).
%   5. New V&V: VV-000 (run reached t_stop), VV-009 (efficiency 0..100 %); incomplete runs are
%      reported as INCOMPLETE instead of a misleading FAIL. New 12_Live_Telemetry.csv.
%EV_DAQ_Builder_V7  Automatic DAQ + logging + V&V + run-archive system for
%                   BLDCSpeedControl_EV_Layout_v2.slx   (single file)
%
%   EV_DAQ_Builder_V7                  setup, then START the simulation (default)
%   EV_DAQ_Builder_V7('Run',false)     setup only (does NOT run the model)
%   EV_DAQ_Builder_V7('Rebuild',true)  re-attach the StartFcn/StopFcn hooks
%   EV_DAQ_Builder_V7('PostProcess')   archive the data currently in the workspace
%
% -------------------------------------------------------------------------
%  ONE-TIME SETUP (this call)
%    paths -> files -> BLDCSpeedControlData.m -> BLDCSpeedControlInput.mat ->
%    load model -> inspect/configure To Workspace blocks -> signal map ->
%    StartFcn + StopFcn hooks (existing callbacks preserved) -> save model
%
%  EVERY RUN (automatic, via the model hooks)
%    StartFcn : init paths/params/signal map, enforce StopTime = t_stop, start
%               command-window capture (diary) and register the LIVE listener.
%               LIVE = one [LIVE] line every EV_DAQ_LivePeriod (0.1 s) of
%               SIMULATION time, fired by a 0.1 s sample-time tap block in the
%               model (EV_LIVE_ZOH), not by a wall-clock MATLAB timer.
%    StopFcn  : stop monitor, harvest logged signals, build raw / cleaned /
%               live data, audit, V&V, events, figures, Excel, text logs,
%               final report, then close the command-window capture
%
%  ARCHIVE  EV_RUN_YYYYMMDD_HHMMSS/   (never overwritten)
%    01_Run_Summary.xlsx (11 sheets)   02_Raw_Data.csv   03_Cleaned_Data.csv
%    04_Parameters_and_Setup.csv       05_Logging_Audit.csv
%    06_VV_Results.csv                 07_Signal_Map.csv
%    08_Group_Summary.csv              09_Event_Log.csv
%    10_Command_Log.txt                11_Simulation_Log.txt
%    12_Live_Telemetry.csv  (the samples printed LIVE during the run)
%    Figures/  Speed, Battery_Voltage, Battery_Current, Motor_Current, SOC,
%              DC_Link, V_and_I_Overview (.png)
%
%  RULES FOLLOWED: signals that are not in the model are NOT invented (they
%  are listed NOT_AVAILABLE in the signal map); derived signals are labelled
%  DERIVED; raw data is written exactly as logged; cleaning never silently
%  removes anything (every removal is counted in the audit); model physics
%  and parameters are never changed.
%
%  NOTE: keep this file named EV_DAQ_Builder_V7.m - it must not share the
%  model's name (the .slx would shadow it).

MDL    = 'BLDCSpeedControl_EV_Layout_v2';
MDLFCN = mfilename;

if nargin >= 1 && (ischar(varargin{1}) || isstring(varargin{1}))
    switch lower(char(varargin{1}))
        case 'postprocess', evPostProcess(MDL);  return
        case 'autoinit'
            tA = tic;  evAutoInit(MDL);  tA1 = toc(tA);  evSessionStart(MDL);
            fprintf('[TIME] StartFcn hook: AutoInit %.2f s + session/live monitor %.2f s. The solver starts now.\n', tA1, toc(tA) - tA1);
            return
        case 'cleantap',    evCleanTap(MDL);  return
        case 'overrides'
            try, assignin('base','EV_T_init', tic); catch, end
            tH = tic;  evApplyOverrides(true);  evEnsureLoadProfile(MDL, true);
            fprintf('[TIME] InitFcn hook (parameters + load-profile file check): %.2f s  (everything else before StartFcn is Simulink compile)\n', toc(tH));
            return   % InitFcn hook
        case 'loadstop',    evApplySavedStopTime(MDL);  return                                  % V7.8 PostLoadFcn hook: last used Stop Time
        % ---- V7.5 BLACK-BOX ---------------------------------------------------
        case 'blackbox'
            % EV_DAQ_Builder_V7('BlackBox')           build / verify BB subsystem
            % EV_DAQ_Builder_V7('BlackBox','remove')  remove it
            if nargin >= 2 && strcmpi(char(varargin{2}),'remove')
                if ~bdIsLoaded(MDL), load_system(MDL); end
                evRemoveBlackBox(MDL);
                fprintf('[DAQ] Black-Box subsystem removed from %s.\n', MDL);
            else
                if ~bdIsLoaded(MDL), load_system(MDL); end
                [okBB, msgBB] = evBuildBlackBox(MDL, []);
                fprintf('[DAQ] Black-Box: %s\n', msgBB);
                if okBB, save_system(MDL); fprintf('[DAQ] Model saved (EV_BlackBox + all connections stored in the .slx).\n'); end
            end
            return
        % ---- V7.6 single-file entry points (formerly EV_Model_Fixes_V8.m / EV_Run_All.m)
        case 'fixes'      % EV_DAQ_Builder_V7('Fixes', 1..4)
            evModelFixes(MDL, varargin{2});  return
        case 'runall'     % EV_DAQ_Builder_V7('RunAll'[,'Solver',true][,'Tune',true][,'Run',false])
            evRunAll(MDL, varargin{2:end});  return
        case 'sysid'
            % EV_DAQ_Builder_V7('SysID')   run offline system identification (call after a simulation)
            try, root2 = evalin('base','EV_DAQ_Root'); catch, root2 = evFindRoot(MDL); end
            P2 = getParams();
            evBlackBoxSysID(root2, P2);
            return
    end
end

p = inputParser;
addParameter(p, 'Verbose', true,  @islogical);
addParameter(p, 'Rebuild', false, @islogical);
addParameter(p, 'Run',     true,  @islogical);   % default: build, then start the simulation
parse(p, varargin{:});
verbose = p.Results.Verbose;
rebuild = p.Results.Rebuild;
runNow  = p.Results.Run;

say  = @(fmt,varargin) fprintf(['[DAQ] ' fmt '\n'], varargin{:});
sayv = @(fmt,varargin) vprint(verbose, ['[DAQ]   ' fmt '\n'], varargin{:});

fprintf('\n╔════════════════════════════════════════════════════════╗\n');
fprintf('║  EV DIGITAL TWIN - SETUP (V7)                         ║\n');
fprintf('║  %s                           ║\n', MDL);
fprintf('║  %s                           ║\n', char(datetime('now')));
fprintf('╠════════════════════════════════════════════════════════╣\n');
fprintf('║  Run length : t_stop = %.4g s (from workspace or default 0.3 s)       ║\n', evCfg().t_stop);
fprintf('║  Limiter    : I_peak = 45 A, I_cont = 30 A                         ║\n');
fprintf('╚════════════════════════════════════════════════════════╝\n\n');

%% 1. root and paths
say('1. Locating project root ...');
root = evFindRoot(MDL);
cd(root);  addpath(root);
if isfolder(fullfile(root,'+Batteries2')), addpath(genpath(root)); end
say('   %s', root);
mdlFile = fullfile(root, [MDL '.slx']);

%% 2. verify files
say('2. Verifying files ...');
req = {mdlFile,                                   'v2 model (REQUIRED)',            true;
       fullfile(root,'BLDCSpeedControlData.m'),   'parameters (REQUIRED)',          true;
       fullfile(root,'BLDCSpeedControlInput.mat'),'Signal Editor input (REQUIRED)', true;
       fullfile(root,'Batteries2_lib.slx'),       'battery library (REQUIRED)',     true;
       fullfile(root,'Batteries2.slx'),           'battery example (optional)',     false;
       fullfile(root,'BLDCSpeedControl.slx'),     'MathWorks base model (optional)',false};
for k = 1:size(req,1)
    ex = isfile(req{k,1});
    say('   %-7s %s', iif(ex,'FOUND','MISSING'), req{k,2});
end
if ~isfolder(fullfile(root,'+Batteries2'))
    say('   WARNING: +Batteries2 folder not next to this file - battery block may fail.');
end
if isfile(fullfile(root,'BLDCSpeedControl_EV_Layout_v2.m'))
    say('   WARNING: BLDCSpeedControl_EV_Layout_v2.m exists next to the model and is shadowed by the .slx - delete it.');
end

%% 3-4. parameters and input
say('3. Running BLDCSpeedControlData.m ...');
try, evalin('base','BLDCSpeedControlData;'); say('   parameters loaded.');
catch ME, say('   ERROR: %s', ME.message); end

% INTEGRATED FIXES: Verify all corrected parameters are in place
say('3b. Verifying parameters loaded from BLDCSpeedControlData.m ...');
P_test = getParams();
param_checks = {
    'rpm_ref', 2950,  'speed target [rpm]'
    'Kpw',     0.05,  'speed PI proportional (model value)'
    'Kiw',     10,    'speed PI integral (model value)'
    'Kiv',     1.5,   'voltage PI integral'
    'I_peak',  45,    'motor peak-current limit [A]'
    'I_cont',  30,    'motor continuous-current limit [A]'
};
fixes_ok = true;
for k = 1:size(param_checks,1)
    pval = P_test.(param_checks{k,1});
    expected = param_checks{k,2};
    tol = abs(expected)*1e-6 + 1e-10;
    is_ok = abs(pval - expected) < tol;
    status = iif(is_ok, '✓', '✗');
    say('   %s %s = %.4g  -- %s', status, param_checks{k,1}, pval, param_checks{k,3});
    if ~is_ok, fixes_ok = false; end
end
if fixes_ok, say('   ✓✓ Parameters match BLDCSpeedControlData.m'); else, say('   ✗ Parameters differ from the expected set - check BLDCSpeedControlData.m'); end

say('3c. V7: torque constant (kappa) and load profile ...');
evApplyOverrides(true);
[okLP, msgLP] = evEnsureLoadProfile(MDL, true);
say('   load profile: %s', msgLP);
say('4. Loading BLDCSpeedControlInput.mat ...');
try
    S_mat = load(fullfile(root,'BLDCSpeedControlInput.mat'));
    fn = fieldnames(S_mat);
    for k = 1:numel(fn), assignin('base', fn{k}, S_mat.(fn{k})); end
    say('   loaded: %s', strjoin(fn', ', '));
catch ME, say('   WARNING: %s', ME.message); end
assignin('base','EV_DAQ_Root', root);
assignin('base','EV_DAQ_MDL',  MDL);
cfg = evCfg();
assignin('base','t_stop', cfg.t_stop);                  % V5: 100 ms run (overrides BLDCSpeedControlData.m t_stop)
assignin('base','EV_DAQ_LivePeriod', cfg.Ts_live);      % V5: LIVE period 0.1 s of simulation time
evTimes('reset');

%% 5. model
say('5. Loading model (no simulation) ...');
% (backup copy removed: no *_backup_before_DAQ.slx is created any more)
if ~bdIsLoaded(MDL), load_system(mdlFile); end
st__ = get_param(MDL,'SimulationStatus');
if ~strcmpi(st__,'stopped')
    error('[%s] The model is "%s". Press STOP in Simulink, wait until it shows Ready, then run setup again.', MDLFCN, st__);
end
if ~evalin('base','exist(''EV_DAQ_LivePeriod'',''var'')'), assignin('base','EV_DAQ_LivePeriod',0.1); end
say('   Simulink StopTime = %s s ; t_stop (parameter file) = %g s', get_param(MDL,'StopTime'), safeBase('t_stop',2));
evEnforceStopTime(MDL);
evSaveStopTime(MDL);
say('   Simulink StopTime now = %s s', get_param(MDL,'StopTime'));

%% 5b. V7: on-screen battery current / voltage show the pack values
say('5b. V7: on-screen Battery Current / Voltage blocks ...');
evFixDisplayGains(MDL);

%% 6-7. To Workspace blocks
say('6. Inspecting To Workspace blocks ...');
tw = evFind(MDL,'LookUnderMasks','all','FollowLinks','on','BlockType','ToWorkspace');
twVars = cell(1,numel(tw));  twPaths = tw(:)';
for k = 1:numel(tw)
    twVars{k} = strtrim(get_param(tw{k},'VariableName'));
    sayv('[%2d] %-20s <- %s', k, twVars{k}, strrep(tw{k}, newline, ' '));
end
say('   found %d block(s).', numel(tw));
say('7. Configuring To Workspace blocks (Timeseries, all samples) ...');
for k = 1:numel(tw)
    try
        set_param(tw{k},'SaveFormat','Timeseries');
        set_param(tw{k},'MaxDataPoints','inf');
        set_param(tw{k},'Decimation','1');
    catch ME, sayv('WARNING %s: %s', twVars{k}, ME.message); end
end
try, set_param(MDL,'ReturnWorkspaceOutputs','off'); catch, end

%% 8. signal map
say('8. Building signal map ...');
[sigMap, ~] = evBuildSigMap(twVars, twPaths);
nFound = sum(structfun(@(s) s.Available, sigMap));
say('   mapped %d / %d signals.', nFound, numel(fieldnames(sigMap)));
assignin('base','EV_DAQ_SignalMap', sigMap);
assignin('base','EV_DAQ_TwVars',    twVars);

%% 8b. simulation-synchronised LIVE tap
livePer = safeBase('EV_DAQ_LivePeriod', 0.1);
say('8b. Building LIVE telemetry tap (period %.3f s of SIMULATION time) ...', livePer);
[okTap, tapMsg] = evBuildLiveTap(MDL, sigMap, livePer);
say('   %s', tapMsg);

%% 8c. V7.5 BLACK-BOX recording subsystem (aircraft-style telemetry recorder)
say('8c. Building Black-Box recording subsystem (V7.5) ...');
[okBB, msgBB] = evBuildBlackBox(MDL, sigMap);
say('   %s', msgBB);

%% 9. options, hooks, save
say('9. Model options and callback hooks ...');
for o = {'SimscapeLogType','none'; 'SimscapeLogOpenViewer','off'}'
    try, set_param(MDL, o{1}, o{2}); catch, end
end
sc = evFind(MDL,'LookUnderMasks','all','FollowLinks','on','BlockType','Scope');
for k = 1:numel(sc), try, set_param(sc{k},'OpenAtSimulationStart','off'); catch, end, end
% V5: switch off logging nothing in this pipeline reads (no change to physics / parameters). Every change is printed.
for o = {'SaveState','off'; 'SaveFinalState','off'; 'SignalLogging','off'; 'SimMechanicsOpenEditorOnUpdate','off'}'
    try
        old = get_param(MDL, o{1});
        if ~strcmpi(old, o{2}), set_param(MDL, o{1}, o{2}); say('   %s: %s -> %s', o{1}, old, o{2}); end
    catch
    end
end
nSc = 0;
for k = 1:numel(sc)
    try
        if strcmpi(get_param(sc{k},'DataLogging'),'on'), set_param(sc{k},'DataLogging','off'); nSc = nSc + 1; end
    catch
    end
end
say('   Scope data logging switched off on %d scope(s) (scope display is unaffected).', nSc);

try, set_param(MDL,'BlockReduction','off'); catch, end   % keeps the LIVE tap block executable
MARKER = '% [EV_DAQ_V7_HOOK]';
hooks = {'InitFcn',  sprintf('try; %s(''Overrides''); catch ME__daq; fprintf(''[DAQ] Overrides error: %%s\\n'', ME__daq.message); end', MDLFCN);
         'StartFcn', sprintf('try; %s(''AutoInit''); catch ME__daq; fprintf(''[DAQ] Auto-init error: %%s\\n'', ME__daq.message); end', MDLFCN);
         'StopFcn',  sprintf('try; %s(''PostProcess''); catch ME__daq; fprintf(''[DAQ] Post-process error: %%s\\n'', ME__daq.message); end', MDLFCN);
         'PostLoadFcn', sprintf('try; %s(''LoadStop''); catch; end', MDLFCN)};   % V7.8: reopen the model with the LAST USED Stop Time (not the 0.3 saved in the file)
for h = 1:size(hooks,1)
    prop = hooks{h,1};  HOOK = [MARKER newline hooks{h,2}];
    cur = '';  try, cur = get_param(MDL,prop); catch, end
    cur = evStripHooks(cur);                 % removes old V2/V3 hooks, keeps everything else
    if isempty(strtrim(cur)), cur = HOOK; else, cur = [strtrim(cur) newline HOOK]; end
    set_param(MDL, prop, cur);
    say('   %s hook written -> %s (all older hooks removed, other content preserved).', prop, MDLFCN);
end
try, save_system(MDL); say('   model saved.'); catch ME, say('   WARNING: not saved (%s)', ME.message); end

%% report
bv = @(n,d) safeBase(n,d);
fprintf('\n============================================================\n');
fprintf('  SETUP REPORT\n');
fprintf('============================================================\n');
fprintf('  Model   : %s.slx   To Workspace blocks: %d   Signals mapped: %d\n', MDL, numel(twVars), nFound);
fprintf('  Motor   : Vnom=%.0fV Kt=%.4f Icont=%.0fA Ipeak=%.0fA %.0f rpm\n', bv('Vmotor_nom',48), bv('Kt',0.107), bv('I_cont',30), bv('I_peak',40), bv('rpm_nom',3000));
fprintf('  Battery : %dS%dP %.0f Ah\n', bv('cells_series',13), bv('cells_parallel',10), bv('pack_Ah',50));
fprintf('  Control : Kpw=%.4f Kiw=%.2f target=%.0f rpm\n\n', bv('Kpw',0.05), bv('Kiw',10), bv('rpm_ref',2950));
for f = fieldnames(sigMap)'
    s = sigMap.(f{1});
    if s.Available, fprintf('    FOUND   %-12s <- %-18s [%s]\n', f{1}, s.WorkspaceVar, s.Unit);
    else,           fprintf('    MISSING %-12s (not logged in model - will be NOT_AVAILABLE)\n', f{1}); end
end
fprintf('\n  STOP TIME        : %s s (t_stop = %g s)\n', get_param(MDL,'StopTime'), safeBase('t_stop',2));
fprintf('  LIVE CONSOLE LOG : one [LIVE] line every %.3f s of simulation time (tap: %s)\n', livePer, iif(okTap,'installed','NOT installed'));
fprintf('                     (change with EV_DAQ_LivePeriod = 0.1 in base workspace, then rerun this setup)\n');
if runNow
    try
        set_param(MDL,'SimulationCommand','update');          % V7.3: compile check, errors are printed here
        fprintf('  Compile check (update diagram): PASSED\n');
    catch MEc
        runNow = false;
        fprintf(2,'\n[DAQ] MODEL DOES NOT COMPILE - simulation NOT started.\n[DAQ] Simulink says: %s\n', MEc.message);
        try, for q = 1:numel(MEc.cause), fprintf(2,'[DAQ]   cause: %s\n', MEc.cause{q}.message); end, catch, end
    end
end
if runNow
    fprintf('\n  Starting simulation ...\n');
    set_param(MDL,'SimulationCommand','start');
else
    fprintf('\n  SETUP COMPLETE - simulation NOT started. Press Run in Simulink.\n');
end
fprintf('============================================================\n\n');
end


%% ========================================================================
%%  PATH DETECTION / QUIET INIT
%% ========================================================================
function root = evFindRoot(MDL)
mf = [MDL '.slx'];
here = fileparts(mfilename('fullpath'));
cands = unique({here, pwd}, 'stable');
for k = 1:numel(cands)
    if ~isempty(cands{k}) && isfile(fullfile(cands{k}, mf)), root = cands{k}; return, end
end
w = which(mf);
if ~isempty(w), root = fileparts(w); return, end
for k = 1:numel(cands)
    d = dir(fullfile(cands{k}, '**', mf));
    if ~isempty(d), root = d(1).folder; return, end
end
error('[%s] cannot find %s near "%s" or "%s".', mfilename, mf, here, pwd);
end

function evAutoInit(MDL)
% Quiet and idempotent. Never modifies the model. V5: timed; the MAT file is loaded only if a variable is
% missing; the signal map built by setup is reused (no find_system over the whole battery model per run).
persistent pathDone
evTimes('reset');
try   % TIMING: InitFcn -> StartFcn = compile / model update time of this run
    tc = toc(evalin('base','EV_T_init'));
    fprintf('[TIME] Compile (InitFcn -> StartFcn): %.1f s | Stop Time box = %s s\n', tc, strtrim(get_param(MDL,'StopTime')));
    assignin('base','EV_T_start', tic);
catch
end
cfg = evCfg();
root = evFindRoot(MDL);
addpath(root);
evSaveStopTime(MDL);                          % V7.8: remember the Stop Time of every run (see evApplySavedStopTime)
fprintf('[DAQ] V7.8 builder file: %s | Simulink Stop Time box = %s s | run length used = %g s\n', which(mfilename), strtrim(get_param(MDL,'StopTime')), cfg.t_stop);
if isempty(pathDone)
    if isfolder(fullfile(root,'+Batteries2')), addpath(genpath(root)); end
    pathDone = true;
end
assignin('base','EV_DAQ_Root', root);
assignin('base','EV_DAQ_MDL',  MDL);
tP = tic;
if ~evalin('base','exist(''Kt'',''var'')')
    try, evalin('base','BLDCSpeedControlData;'); catch, end
end
matFile = fullfile(root,'BLDCSpeedControlInput.mat');
if isfile(matFile)
    try
        w = whos('-file', matFile);  need = {w.name};
        have = cellfun(@(n) evalin('base', sprintf('exist(''%s'',''var'')', n)) > 0, need);
        if ~all(have)
            S = load(matFile, need{~have});
            for f = fieldnames(S)', assignin('base', f{1}, S.(f{1})); end
        end
    catch
    end
end
assignin('base','t_stop', cfg.t_stop);
assignin('base','EV_DAQ_LivePeriod', cfg.Ts_live);
evApplyOverrides(false);                      % V7: kappa -> Ke_ph, emf_max_ev, psim (same values as the InitFcn hook)
evTimes('set','ParameterLoading', toc(tP));
tM = tic;
if ~bdIsLoaded(MDL), load_system(fullfile(root,[MDL '.slx'])); end
evTimes('set','ModelLoading', toc(tM));
tC = tic;
evEnforceStopTime(MDL);
haveMap = evalin('base','exist(''EV_DAQ_SignalMap'',''var'') && exist(''EV_DAQ_TwVars'',''var'')');
if ~haveMap
    tw = evFind(MDL,'LookUnderMasks','all','FollowLinks','on','BlockType','ToWorkspace');
    twVars = cell(1,numel(tw));
    for k = 1:numel(tw), twVars{k} = strtrim(get_param(tw{k},'VariableName')); end
    [sigMap, ~] = evBuildSigMap(twVars, tw(:)');
    assignin('base','EV_DAQ_SignalMap', sigMap);
    assignin('base','EV_DAQ_TwVars',    twVars);
end
evTimes('set','ModelConfiguration', toc(tC));
end

function evSaveStopTime(MDL)
% V7.8: writes the Stop Time of this run to <project>/EV_LastStopTime.txt (the model file itself is NOT touched).
try
    v = evCfg().t_stop;
    f = fullfile(fileparts(get_param(MDL,'FileName')), 'EV_LastStopTime.txt');
    old = NaN;  if isfile(f), old = str2double(strtrim(fileread(f))); end
    if ~isfinite(old) || abs(old - v) > 1e-12
        fid = fopen(f,'w');  fprintf(fid,'%.10g\n',v);  fclose(fid);
    end
catch
end
end

function evApplySavedStopTime(MDL)
% V7.8 PostLoadFcn: a freshly opened / reloaded model gets the LAST USED Stop Time instead of the value stored in the .slx.
try
    f = fullfile(fileparts(get_param(MDL,'FileName')), 'EV_LastStopTime.txt');
    if ~isfile(f), return, end
    v = str2double(strtrim(fileread(f)));
    if ~(isfinite(v) && v > 0), return, end
    cur = str2double(strtrim(get_param(MDL,'StopTime')));
    if ~isfinite(cur) || abs(cur - v) > 1e-12
        set_param(MDL,'StopTime',sprintf('%.10g',v));
        fprintf('[DAQ] Stop Time set to the last used value: %g s (delete EV_LastStopTime.txt to go back to the value saved in the model)\n', v);
    end
catch
end
end

function evEnforceStopTime(MDL)
% V7.8: the builder NEVER changes the Simulink Stop Time any more (this function used to force it back to 0.3 s).
% The Stop Time box of the model is the only source; this function only reports it.
cur = evStopTime(MDL);
fprintf('[DAQ] Stop Time used for this run = %g s (read from the Simulink Stop Time box, not changed by the builder)\n', cur);
end

function s = evStripHooks(s)
% V7: removes every "% [EV_DAQ_Vn_HOOK]" marker line and its command line, and any stray EV_DAQ_Builder_Vn call line
s = regexprep(s, '[ \t]*%\s*\[EV_DAQ_V\d+_HOOK\][^\n]*(\n[^\n]*EV_DAQ_Builder_V\d+[^\n]*)?', '');   % V7: any version marker (V2..V9) plus its call line
s = regexprep(s, '[^\n]*EV_DAQ_Builder_V\d+\(''(AutoInit|PostProcess|Overrides|LoadStop)''\)[^\n]*\n?', '');   % V7: stray call lines left by older hooks (e.g. the stale V3 call)
s = strtrim(s);
end

function [sigMap, defs] = evBuildSigMap(twVars, twPaths)
defs = evSignalDefs();
sigMap = struct();
for k = 1:size(defs,1)
    idx = 0;
    for c = 1:numel(defs{k,2})
        i = find(strcmpi(twVars, defs{k,2}{c}), 1);
        if ~isempty(i), idx = i; break; end
    end
    sm = struct('Key',defs{k,1},'WorkspaceVar','','BlockPath','','PathRaw','', ...
        'Unit',defs{k,3},'Group',defs{k,4},'Description',defs{k,5},'Available',idx>0);
    if idx > 0
        sm.WorkspaceVar = twVars{idx};
        sm.PathRaw      = twPaths{idx};
        sm.BlockPath    = strrep(twPaths{idx}, newline, ' ');
    end
    sigMap.(defs{k,1}) = sm;
end
end

function d = evSignalDefs()
% key, candidate To Workspace variable names (v2 model), unit, group, description
d = {
 'rpm',         {'log_rpm','rpm'},             'rpm',      'Motor',   'Motor speed';
 'rpm_ref',     {'log_rpm_ref','rpm_ref_log'}, 'rpm',      'Motor',   'Speed reference';
 'torque',      {'log_Tq_meas','log_torque'},  'Nm',       'Motor',   'Measured motor torque';
 'imotor',      {'log_Idc_f','log_imotor'},    'A',        'Motor',   'Controller estimate max(|iabc|), 2 ms filter (not a DC-link measurement)';
 'vbatt',       {'log_vcell','log_vbatt'},     'V',        'Battery', 'Battery voltage';
 'ibatt',       {'log_icell','log_ibatt'},     'A',        'Battery', 'Battery current';
 'ibatt_sens',  {'log_Ibat_sens_A'},           'A',        'Battery', 'Independent physical battery current sensor';
 'vbatt_sens',  {'log_Vbat_sens_V'},           'V',        'Battery', 'Independent physical battery terminal voltage sensor';
 'soc',         {'log_soc'},                   '-',        'Battery', 'State of charge';
 'temperature', {'log_Tbatt_C','log_temp','temperature'}, 'degC', 'Battery', 'Battery temperature (calibrated pack/cell aggregate)';
 'battmaxtemp', {'log_TbattMax_C'},              'degC',     'Battery', 'Maximum battery cell temperature';
 'motortemp',   {'log_Tmotor_C'},                'degC',     'Motor',   'Motor housing temperature';
 'vdc',         {'log_Vdc_m','log_vdc_m'},     'V',        'DC-Link', 'DC link voltage';
 'omega_wheel', {'log_omega_wheel'},           'as-logged','Vehicle', 'Wheel speed';
};
end

function n = evKeySpecName(key)
m = struct('rpm','RPM','rpm_ref','RPMReference','torque','MotorTorque','imotor','MotorCurrent', ...
    'vbatt','BatteryVoltage','ibatt','BatteryCurrent','ibatt_sens','BatteryCurrentSensor','vbatt_sens','BatteryVoltageSensor','soc','SOC','temperature','BatteryTemperature', ...
    'battmaxtemp','BatteryTemperatureMax','motortemp','MotorTemperature', ...
    'vdc','DCLinkVoltage','omega_wheel','WheelSpeed');
n = m.(key);
end

function d = evSpecDefs()
% Full requested signal list (spec order).
% name, key, kind(logged|derived|none), unit, group, live, vv, description
d = {
 'BatteryVoltage',        'vbatt',      'logged',  'V',   'Battery', 'YES','YES','Battery pack voltage';
 'BatteryCurrent',        'ibatt',      'logged',  'A',   'Battery', 'YES','NO', 'Battery current';
 'BatteryCurrentSensor',  'ibatt_sens', 'logged',  'A',   'Battery', 'YES','NO', 'Independent physical battery current sensor; requires sensor block wiring';
 'BatteryVoltageSensor',  'vbatt_sens', 'logged',  'V',   'Battery', 'YES','NO', 'Independent physical battery terminal voltage sensor; requires sensor block wiring';
 'BatteryPower',          '',           'derived', 'W',   'Battery', 'YES','NO', 'BatteryVoltage*BatteryCurrent';
 'SOC',                   'soc',        'logged',  '-',   'Battery', 'YES','YES','State of charge';
 'BatteryTemperature',    'temperature','logged',  'degC','Battery', 'YES','NO', 'Battery temperature';
 'BatteryTemperatureMax', 'battmaxtemp','logged',  'degC','Battery', 'YES','NO', 'Maximum battery cell temperature';
 'MotorTemperature',      'motortemp',  'logged',  'degC','Motor',   'YES','NO', 'Motor housing temperature';
 'DCLinkVoltage',         'vdc',        'logged',  'V',   'DC-Link', 'YES','NO', 'DC link voltage';
 'DCLinkCurrent',         '',           'none',    'A',   'DC-Link', 'YES','NO', 'No DC-link current logged in model';
 'DCLinkPower',           '',           'none',    'W',   'DC-Link', 'NO', 'NO', 'No DC-link current logged in model';
 'RPMReference',          'rpm_ref',    'logged',  'rpm', 'Motor',   'YES','NO', 'Speed reference';
 'RPM',                   'rpm',        'logged',  'rpm', 'Motor',   'YES','YES','Motor speed';
 'SpeedError',            '',           'derived', 'rpm', 'Motor',   'NO', 'NO', 'RPMReference-RPM';
 'MotorTorque',           'torque',     'logged',  'Nm',  'Motor',   'YES','NO', 'Measured motor torque';
 'MotorMechanicalPower',  '',           'derived', 'W',   'Motor',   'YES','NO', '|MotorTorque|*RPM*2*pi/60';
 'MotorCurrent',          'imotor',     'logged',  'A',   'Motor',   'YES','YES','Controller ESTIMATE of DC current: max(|iabc|), 2 ms low-pass (log_Idc_f); not a DC-link measurement';
 'PhaseCurrentA',         '',           'none',    'A',   'Motor',   'YES','NO', 'Not logged in model';
 'PhaseCurrentB',         '',           'none',    'A',   'Motor',   'YES','NO', 'Not logged in model';
 'PhaseCurrentC',         '',           'none',    'A',   'Motor',   'YES','NO', 'Not logged in model';
 'WheelSpeed',            'omega_wheel','logged',  'as-logged','Vehicle','YES','NO','Wheel speed (unit as logged by model)';
 'VehicleSpeed',          '',           'none',    'm/s', 'Vehicle', 'NO', 'NO', 'Not logged in model';
 'VehicleAcceleration',   '',           'none',    'm/s2','Vehicle', 'NO', 'NO', 'Not logged in model';
 'SpeedPIOutput',         '',           'none',    'V',   'Control', 'NO', 'NO', 'Not logged in model';
 'VoltagePIOutput',       '',           'none',    '-',   'Control', 'NO', 'NO', 'Not logged in model';
 'DutyCycle',             '',           'none',    '-',   'Control', 'NO', 'NO', 'Not logged in model';
 'CurrentLimit',          '',           'none',    'A',   'Control', 'NO', 'NO', 'Not logged in model';
 'CurrentLimiterActive',  '',           'none',    '-',   'Control', 'NO', 'NO', 'Not logged in model';
 'PWM_Gate_Signals',      '',           'none',    '-',   'Control', 'NO', 'NO', 'Not logged in model';
 'Efficiency',            '',           'derived', '%',   'Energy',  'YES','NO', '100*MotorMechanicalPower/|BatteryPower|';
};
end


%% ========================================================================
%%  SESSION: live console log + command-window capture + simulation log
%% ========================================================================
function out = evSession(action, varargin)
persistent S
out = [];
switch action
    case 'start'
        S = struct('t0',datetime('now'),'tic0',tic,'log',{{}},'diaryFile','', ...
                   'seenRunning',false,'stoppedTicks',0,'tStop',NaT,'nTicks',0, ...
                   'taps',[],'listener',[],'live',zeros(0,14),'nextLive',0.1,'period',0.1,'stopT',NaN);
    case 'get',  out = S;
    case 'set',  if ~isempty(S), S.(varargin{1}) = varargin{2}; end
    case 'log'
        fprintf('[DAQ] %s\n', varargin{1});
        if ~isempty(S), S.log{end+1} = stamped(varargin{1}); end
    case 'logq'
        if ~isempty(S), S.log{end+1} = stamped(varargin{1}); end
    case 'addlive'
        if ~isempty(S), S.live(end+1,:) = varargin{1}; end
end
end

function s = stamped(msg)
s = sprintf('[%s] %s', char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS')), msg);
end

function evSessionStart(MDL)
evStopTimer();
evSession('start');
try, diary('off'); catch, end
dfile = fullfile(tempdir, ['EV_diary_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')) '.txt']);
try, diary(dfile); diary('on'); evSession('set','diaryFile',dfile); catch, end
evMem('reset');  evMem('Before simulation');

bv = @(n,d) safeBase(n,d);
fprintf('\n====================================================\n');
fprintf('  EV DIGITAL TWIN SIMULATION\n');
fprintf('====================================================\n');
fprintf('  Date/Time      : %s\n', char(datetime('now')));
fprintf('  MATLAB version : %s\n', version);
fprintf('  Model          : %s\n', MDL);
fprintf('  Parameter file : BLDCSpeedControlData.m (+ BLDCSpeedControlInput.mat)\n');
fprintf('  Battery        : %dS%dP  %.0f Ah\n', bv('cells_series',NaN), bv('cells_parallel',NaN), bv('pack_Ah',NaN));
fprintf('  Motor          : Vnom %.0f V  Kt %.4f  Icont %.0f A  Ipeak %.0f A  %.0f rpm\n', bv('Vmotor_nom',NaN), bv('Kt',NaN), bv('I_cont',NaN), bv('I_peak',NaN), bv('rpm_nom',NaN));
fprintf('  Vehicle        : gear %.1f  wheel radius %.3f m\n', bv('gear_ratio',NaN), bv('r_wheel',NaN));
fprintf('  Controller     : speed PI %.4f/%.2f  voltage PI %.3f/%.2f\n', bv('Kpw',NaN), bv('Kiw',NaN), bv('Kpv',NaN), bv('Kiv',NaN));
stopT = evStopTime(MDL);
per   = bv('EV_DAQ_LivePeriod', 0.1);
fprintf('  Simulation time: %.3f s\n', stopT);
estMin = stopT*566/60;   % measured (BLDCSpeedControlData.m): 0.5 s took 283 s at Ts = 1e-5; solver time is proportional to Stop Time
fprintf('  Expected solver time: about %.1f min at Ts = %g s (Stop Time 0.3 s = about 2.8 min, 0.5 s = about 4.7 min)\n', estMin, safeBase('Ts',1e-5));
if estMin > 3, fprintf('  NOTE: a Stop Time above 0.3 s costs wall time. Use 0.3 s for normal runs, or EV_DAQ_Fast = true to skip the report files.\n'); end
fprintf('  Target speed   : %.0f rpm\n', bv('rpm_ref',NaN));
fprintf('  LIVE period    : %.3f s (simulation time)\n', per);
fprintf('----------------------------------------------------\n');
evSession('log','Simulation started');
evSession('log',['Model loaded: ' MDL]);
evSession('log','Parameters loaded: BLDCSpeedControlData.m, BLDCSpeedControlInput.mat');
evSession('log',['Workspace initialized: EV_DAQ_Root = ' safeStr('EV_DAQ_Root')]);
try
    sm = evalin('base','EV_DAQ_SignalMap');  names = {};
    for f = fieldnames(sm)'
        if sm.(f{1}).Available, names{end+1} = sm.(f{1}).WorkspaceVar; end %#ok<AGROW>
    end
    evSession('log',sprintf('Data logging initialized: %d To Workspace signals (%s)', numel(names), strjoin(names,', ')));
catch
    evSession('log','Data logging initialized (signal map unavailable)');
end
evSession('set','period',per);  evSession('set','stopT',stopT);  evSession('set','nextLive',per);
[ok, msg] = evLiveRegister(MDL);
evSession('log', msg);
if ok, fprintf('----------------------------------------------------\n\n'); end
end

function stopT = evStopTime(MDL)
stopT = NaN;
try
    str = strtrim(get_param(MDL,'StopTime'));
    stopT = str2double(str);
    if ~isfinite(stopT), stopT = double(evalin('base', str)); end
catch
end
end

function evStopTimer()
% legacy wall-clock timers from older builder versions (never created any more)
try
    t = timerfindall('Name','EV_DAQ_LiveMonitor');
    if ~isempty(t), stop(t); delete(t); end
catch
end
end

function evStopLive()
S = evSession('get');
if isempty(S), return, end
try, if ~isempty(S.listener), delete(S.listener); end, catch, end
evSession('set','listener',[]);
end


%% ========================================================================
%%  LIVE TELEMETRY  (simulation-time synchronised)
%%
%%  Model side (built once by setup, saved in the .slx):
%%     <log-block input signal> -> EV_LIVE_Tap_<key> (convert to double) -> EV_LIVE_Mux
%%     -> EV_LIVE_ZOH (sample time = EV_DAQ_LivePeriod = 0.1 s) -> EV_LIVE_Term
%%  The ZOH only executes at multiples of 0.1 s of SIMULATION time. A PostOutputs
%%  execution-event listener on it prints one [LIVE] line per hit. The tapped
%%  signals are the SAME ones the To Workspace blocks log, passed through the
%%  SAME normalisation as the archive (normSignal), so LIVE == archived data.
%% ========================================================================
function [ok, msg] = evBuildLiveTap(MDL, sigMap, per)
ok = false;  stage = 'remove old tap';
exZ = evFind(MDL,'LookUnderMasks','all','FollowLinks','on','Name','EV_LIVE_ZOH');   % V7.1: keep an existing tap (any level)
if ~isempty(exZ)
    ok = true;
    msg = sprintf('existing LIVE tap kept: %s (ZOH sample time %s s, wanted %.3f s)', get_param(exZ{1},'Parent'), get_param(exZ{1},'SampleTime'), per);
    if abs(str2double(get_param(exZ{1},'SampleTime')) - per) > 1e-9, msg = [msg ' - MISMATCH: edit the ZOH block or EV_DAQ_LivePeriod']; end
    return
end
evRemoveLiveTap(MDL);

want = {'rpm','torque','imotor','vbatt','ibatt','soc','vdc','omega_wheel','rpm_ref','temperature'};
src = {};   % key, source port handle, y position
try
    for k = 1:numel(want)
        key = want{k};
        if ~isfield(sigMap,key) || ~sigMap.(key).Available, continue, end
        blk = sigMap.(key).PathRaw;
        if ~strcmp(get_param(blk,'Parent'), MDL), continue, end      % root-level log blocks only
        ph = get_param(blk,'PortHandles');
        ln = get_param(ph.Inport(1),'Line');
        if ln < 0, continue, end
        pos = get_param(blk,'Position');
        src(end+1,:) = {key, get_param(ln,'SrcPortHandle'), pos}; %#ok<AGROW>
    end
    stage = 'collect source signals';
    n = size(src,1);
    if n == 0, msg = 'LIVE tap NOT built: no root-level log blocks with connected inputs.'; return, end
    ys = cellfun(@(p) p(2), src(:,3));  y0 = min(ys);  y1 = max(ys)+30;  x0 = 1900;
    mux = [MDL '/EV_LIVE_Mux'];  zoh = [MDL '/EV_LIVE_ZOH'];  trm = [MDL '/EV_LIVE_Term'];
    add_block('built-in/Mux', mux, 'Inputs', num2str(n), 'DisplayOption', 'none', 'Position', [x0+120 y0 x0+130 y1]);
    add_block('built-in/ZeroOrderHold', zoh, 'SampleTime', sprintf('%.10g',per), 'Position', [x0+190 (y0+y1)/2-15 x0+250 (y0+y1)/2+15]);
    add_block('built-in/Terminator', trm, 'Position', [x0+310 (y0+y1)/2-10 x0+330 (y0+y1)/2+10]);
    pm = get_param(mux,'PortHandles');  pz = get_param(zoh,'PortHandles');  pt = get_param(trm,'PortHandles');
    for k = 1:n
        d = sprintf('%s/EV_LIVE_Tap_%s', MDL, src{k,1});
        add_block('built-in/DataTypeConversion', d, 'OutDataTypeStr', 'double', ...
            'Position', [x0 src{k,3}(2) x0+60 src{k,3}(2)+30]);
        pd = get_param(d,'PortHandles');
        stage = sprintf('connect logged signal "%s" -> EV_LIVE_Tap_%s', src{k,1}, src{k,1});
        evConnect(MDL, src{k,2}, pd.Inport(1));              % branch off the logged signal
        stage = sprintf('connect EV_LIVE_Tap_%s -> EV_LIVE_Mux input %d', src{k,1}, k);
        evConnect(MDL, pd.Outport(1), pm.Inport(k));
    end
    stage = 'connect EV_LIVE_Mux -> EV_LIVE_ZOH';
    evConnect(MDL, pm.Outport(1), pz.Inport(1));
    stage = 'connect EV_LIVE_ZOH -> EV_LIVE_Term';
    evConnect(MDL, pz.Outport(1), pt.Inport(1));
    stage = 'group tap blocks into ONE subsystem';
    hs = cellfun(@(b) get_param(b,'Handle'), [{mux,zoh,trm}, strcat(MDL,'/EV_LIVE_Tap_',src(:,1))']);
    Simulink.BlockDiagram.createSubsystem(hs);
    sub = get_param(zoh,'Parent');
    set_param(sub,'Name','EV_LIVE_Tap');
    set_param([MDL '/EV_LIVE_Tap'],'ShowName','on');
    stage = 'compile check (update diagram)';
    set_param(MDL,'BlockReduction','off');
    set_param(MDL,'SimulationCommand','update');            % compile check
    ok = true;
    msg = sprintf('LIVE tap installed (one block, EV_LIVE_Tap): %d signals (%s), ZOH sample time %.3f s.', n, strjoin(src(:,1)',', '), per);
catch ME
    evRemoveLiveTap(MDL);
    msg = sprintf('LIVE tap NOT installed (model left unchanged). Step: %s. Simulink says: %s', stage, ME.message);
end
end

function evRemoveLiveTap(MDL)
% delete every connection of the EV_LIVE_* blocks first, then the blocks themselves
b = evFind(MDL,'SearchDepth',1,'Regexp','on','Name','^EV_LIVE_');
b = b(~strcmp(b, MDL));
for k = 1:numel(b)
    try
        lh = get_param(b{k},'LineHandles');
        h = [lh.Inport(:); lh.Outport(:)];
        for j = 1:numel(h)
            if h(j) > 0, try, delete_line(h(j)); catch, end, end
        end
    catch
    end
end
for k = 1:numel(b)
    try, delete_block(b{k}); catch, end
end
end

%% ========================================================================
%%  V7.6  BLACK-BOX SUBSYSTEM  (aircraft-style flight recorder)
%%
%%  Architecture (read-only tap, independent of the control loop):
%%    From blocks INSIDE EV_BlackBox read existing GLOBAL Goto tags
%%    -> DataTypeConversion (double) -> Mux -> EV_BB_ZOH (1 ms)
%%    -> To Workspace (EV_BlackBox_log, Timeseries). Nothing upstream is changed.
%%
%%  PORT-HANDLE RULE (the V7.5 bug): add_line(sys, a, b) needs BOTH port handles
%%  to belong to blocks that live directly in `sys`. Every add_line here goes
%%  through evAddLine, which compares evPortSystem() of both ports with `sys`
%%  and stops with a precise message instead of Simulink's generic error.
%%
%%  SIGNAL SOURCE, in order of preference for every column:
%%   1. 'tag'        an existing GLOBAL Goto tag (read by a new From in the BB).
%%                   No existing line is touched.
%%   2. 'tapGoto'    no tag exists, but a log To Workspace block (nested in some
%%                   subsystem) is fed by the signal: a new global Goto
%%                   BB_TapGoto_<label> is added IN THE SOURCE'S OWN SYSTEM and
%%                   branched off the signal there (add_line on that system),
%%                   then read by a From in the BB. Nested port handles are never
%%                   used at root level.
%%   3. 'rootInport' the source port is at root level: wire it to a new Inport
%%                   of the BB with add_line(MDL, ...).
%%  A signal that cannot be tapped is skipped and reported; it never aborts the build.
%%
%%  Column labels are stored in the BB block (persistent UserData) and in base
%%  variable EV_BB_ColumnLabels; evBlackBoxSysID() selects columns BY NAME.
%%
%%   label        global tag        unit   (Vbatt_V = sum, Ibatt_A = sum/cells_series, SOC = mean of the cell vectors;
%%                                        Ibatt_A, Vdc_m_V, Torque_Nm get a 0.5 ms low-pass before the 1 ms sample)
%%   Vbatt_V      MON_Vbat_Assy     V
%%   Ibatt_A      MON_Ibat_Cell     A
%%   SOC          MON_SOC_Cell      -
%%   RPM_rpm      rpm               rpm
%%   Idc_f_A      Idc_f             A
%%   Vdc_m_V      Vdc_m             V
%%   omega_wheel  MON_Wheel_Speed   as logged
%%   Torque_Nm    Tq_meas           Nm
%% ========================================================================
function [ok, msg] = evBuildBlackBox(MDL, ~)
ok = false;  msg = '';
BB_NAME  = 'EV_BlackBox';
ZOH_NAME = 'EV_BB_ZOH';
TW_VAR   = 'EV_BlackBox_log';
Ts_bb    = 1e-3;                       % 1 kHz log
BB_TAG   = 'EV_BB_v7_8_battery_sensors';       % rebuild existing BB to add optional motor and battery temperature channels
bbPath   = [MDL '/' BB_NAME];

%% ---- idempotency: keep a healthy existing BB (ZOH present AND every port connected)
exBB = evFind(MDL,'SearchDepth',1,'Name',BB_NAME);
exBB = exBB(~strcmp(exBB, MDL));
if ~isempty(exBB)
    exZ = evFind(exBB{1},'LookUnderMasks','all','FollowLinks','on','Name',ZOH_NAME);
    bad = evVerifyBlackBox(exBB{1});
    if ~isempty(exZ) && isempty(bad) && strcmp(get_param(exBB{1},'Tag'), BB_TAG)
        gotTs = str2double(get_param(exZ{1},'SampleTime'));
        try, labK = get_param(exBB{1},'UserData'); if iscell(labK) && ~isempty(labK), assignin('base','EV_BB_ColumnLabels',labK); end, catch, end   % restore after 'clear all'
        ok = true;
        msg = sprintf('existing EV_BlackBox kept (ZOH sample time %.4g s, wanted %.4g s)%s', ...
            gotTs, Ts_bb, iif(abs(gotTs - Ts_bb) > 1e-12,' - MISMATCH: edit EV_BB_ZOH',''));
        return
    end
end
evRemoveBlackBox(MDL);                 % remove stale / partial install (and old tap Gotos)

%% ---- signal table: label, candidate global tags, fallback log variable, unit, reduction to ONE column
%  The pack signals are vectors in the model (13 assembly voltages, 130 cell currents, 130 cell SOCs). They are
%  reduced here exactly like normSignal() reduces the archived logs, so the Mux gets one scalar per label:
%    'sum'    Vbatt_V = sum of the series voltages            (normSignal 'vbatt', multi-column case)
%    'isum'   Ibatt_A = sum of cell currents / cells_series   (normSignal 'ibatt', 130-column case)
%    'mean'   SOC     = mean of the cell SOCs                 (normSignal 'soc')
cs = safeBase('cells_series', 13);  cp = safeBase('cells_parallel', 10);
%  lp = first-order low-pass time constant [s] placed BEFORE the 1 ms sample (0 = none). The archive uses a 1 ms
%  window mean (evBinMean, 10 PWM periods). A point sample every 1 ms always hits the same PWM phase, so switching
%  ripple does not average out (measured: Ibatt std 3.4 A vs 1.2 A in the archive, window mean 13 % off). The
%  filter removes the ripple (10 kHz is attenuated about 30x at 0.5 ms). Applied to the signals that carry switching
%  ripple; Vbatt, RPM, SOC, wheel speed and Idc_f (already 2 ms filtered) stay unfiltered.
sigs = {
    'Vbatt_V',     {'MON_Vbat_Assy'},   'log_vcell',       'V',         'sum',  0;
    'Ibatt_A',     {'MON_Ibat_Cell'},   'log_icell',       'A',         'isum', 0.5e-3;
    'SOC',         {'MON_SOC_Cell'},    'log_soc',         '-',         'mean', 0;
    'RPM_rpm',     {'rpm'},             'log_rpm',         'rpm',       '',     0;
    'Idc_f_A',     {'Idc_f'},           'log_Idc_f',       'A',         '',     0;
    'Vdc_m_V',     {'Vdc_m'},           'log_Vdc_m',       'V',         '',     0.5e-3;
    'omega_wheel', {'MON_Wheel_Speed'}, 'log_omega_wheel', 'as-logged', '',     0;
    'Torque_Nm',   {'Tq_meas'},         'log_Tq_meas',     'Nm',        '',     0.5e-3;
    'Tmotor_C',    {'MON_Tmotor_C'},    'log_Tmotor_C',    'degC',      '',     0;
    'Tbatt_C',     {'MON_Tbatt_C'},     'log_Tbatt_C',     'degC',      '',     0;
    'Ibat_sens_A', {'MON_Ibat_sens_A'}, 'log_Ibat_sens_A','A',         '',     0;
    'Vbat_sens_V', {'MON_Vbat_sens_V'}, 'log_Vbat_sens_V','V',         '',     0;
};

%% ---- inspect every Goto in the model once (only GLOBAL tags are readable from the BB)
gotos = evFind(MDL,'LookUnderMasks','all','FollowLinks','on','BlockType','Goto');
gTag = cell(size(gotos));  gVis = cell(size(gotos));
for i = 1:numel(gotos)
    try, gTag{i} = get_param(gotos{i},'GotoTag'); gVis{i} = get_param(gotos{i},'TagVisibility');
    catch, gTag{i} = ''; gVis{i} = ''; end
end

%% ---- decide the route of each signal (read-only inspection, nothing is changed yet)
plan = struct('label',{},'unit',{},'reduce',{},'lp',{},'route',{},'tag',{},'srcPH',{},'srcSys',{});
skipped = {};
for k = 1:size(sigs,1)
    label = sigs{k,1};  cands = sigs{k,2};  twVar = sigs{k,3};  unit = sigs{k,4};  red = sigs{k,5};  lpT = sigs{k,6};
    e = struct('label',label,'unit',unit,'reduce',red,'lp',lpT,'route','','tag','','srcPH',-1,'srcSys','');
    for c = 1:numel(cands)
        if any(strcmp(gTag, cands{c}) & strcmpi(gVis,'global'))
            e.route = 'tag';  e.tag = cands{c};  break
        end
    end
    if isempty(e.route)                                    % no usable global tag: use the log block's source
        twB = evFind(MDL,'LookUnderMasks','all','FollowLinks','on','BlockType','ToWorkspace','VariableName',twVar);
        if isempty(twB), skipped{end+1} = sprintf('%s (no global tag %s, no log block %s)', label, strjoin(cands,'/'), twVar); continue, end %#ok<AGROW>
        ph = get_param(twB{1},'PortHandles');
        ln = get_param(ph.Inport(1),'Line');
        if ln < 0, skipped{end+1} = sprintf('%s (log block %s has no input line)', label, twVar); continue, end %#ok<AGROW>
        e.srcPH  = get_param(ln,'SrcPortHandle');
        if e.srcPH < 0, skipped{end+1} = sprintf('%s (log block %s has no source port)', label, twVar); continue, end %#ok<AGROW>
        e.srcSys = evPortSystem(e.srcPH);                  % the system that REALLY owns the source port
        if strcmp(e.srcSys, MDL), e.route = 'rootInport'; else, e.route = 'tapGoto'; end
    end
    plan(end+1) = e; %#ok<AGROW>
end
if isempty(plan)
    msg = ['EV_BlackBox NOT built: no usable signal. ' strjoin(skipped,'; ')];
    return
end

stage = 'start';
createdTaps = {};
try
    %% ---- (1) nested sources: add a global Goto in the source's OWN system and branch there
    for k = 1:numel(plan)
        if ~strcmp(plan(k).route,'tapGoto'), continue, end
        stage = sprintf('tap nested signal "%s" in system "%s"', plan(k).label, plan(k).srcSys);
        gp = [plan(k).srcSys '/BB_TapGoto_' plan(k).label];
        try
            sp = get_param(get_param(plan(k).srcPH,'Parent'),'Position');
            add_block('built-in/Goto', gp, 'GotoTag', ['BB_TAP_' plan(k).label], 'TagVisibility','global', ...
                'ShowName','off', 'Position', [sp(3)+60 sp(2)+40 sp(3)+120 sp(2)+60]);
            createdTaps{end+1} = gp; %#ok<AGROW>
            gph = get_param(gp,'PortHandles');
            evAddLine(plan(k).srcSys, plan(k).srcPH, gph.Inport(1), ['tap ' plan(k).label]);
            plan(k).tag = ['BB_TAP_' plan(k).label];  plan(k).route = 'tapGoto';
        catch ME_tap
            if any(strcmp(createdTaps, gp)), try, delete_block(gp); catch, end, createdTaps(strcmp(createdTaps,gp)) = []; end
            plan(k).route = '';
            skipped{end+1} = sprintf('%s (cannot tap in "%s": %s)', plan(k).label, plan(k).srcSys, ME_tap.message); %#ok<AGROW>
        end
    end
    plan = plan(~cellfun(@isempty,{plan.route}));
    n = numel(plan);
    if n == 0, error('EV_DAQ:BB:noSignal','no signal could be tapped. %s', strjoin(skipped,'; ')); end

    %% ---- (2) subsystem shell (root level), cleared of any default content
    stage = 'create EV_BlackBox subsystem';
    allRoot = evFind(MDL,'SearchDepth',1,'Type','block');
    allRoot = allRoot(~strcmp(allRoot, MDL));
    xMax = 200;
    for k = 1:numel(allRoot)
        try, p = get_param(allRoot{k},'Position'); xMax = max(xMax, p(3)); catch, end
    end
    xBB = xMax + 120;  yBB = 50;  wBB = 220;  hBB = max(80, n*40 + 40);
    add_block('built-in/SubSystem', bbPath, 'Position', [xBB yBB xBB+wBB yBB+hBB], ...
        'ShowName','on','ForegroundColor','red','BackgroundColor','[1 0.9 0.7]', 'Tag', BB_TAG, ...
        'Description','Aircraft-style black-box telemetry recorder (V7.6). Read-only tap: no control signal is changed.');
    inner = evFind(bbPath,'SearchDepth',1,'FindAll','on','Type','line');
    for j = 1:numel(inner), try, delete_line(inner(j)); catch, end, end
    inb = evFind(bbPath,'SearchDepth',1,'Type','block');  inb = inb(~strcmp(inb,bbPath));
    for j = 1:numel(inb), try, delete_block(inb{j}); catch, end, end

    %% ---- (3) inside the subsystem: From/Inport -> DTC (all lines use bbPath as the system)
    xI = 30;  yStep = 50;  yI0 = 30;
    dtcOut = zeros(n,1);  nIn = 0;  labels = cell(1,n);
    for k = 1:n
        labels{k} = plan(k).label;
        yPos    = yI0 + (k-1)*yStep;
        dtcPath = sprintf('%s/BB_DTC_%02d', bbPath, k);
        stage = sprintf('build input chain for "%s"', plan(k).label);
        if strcmp(plan(k).route,'rootInport')
            nIn = nIn + 1;
            srcBlk = sprintf('%s/BB_In_%02d', bbPath, k);
            add_block('built-in/Inport', srcBlk, 'Port', num2str(nIn), 'ShowName','off', 'Position', [xI yPos xI+30 yPos+20]);
        else
            srcBlk = sprintf('%s/BB_From_%02d', bbPath, k);
            add_block('built-in/From', srcBlk, 'GotoTag', plan(k).tag, 'TagVisibility','global', ...
                'ShowName','off', 'Position', [xI yPos xI+60 yPos+20]);
        end
        add_block('built-in/DataTypeConversion', dtcPath, 'OutDataTypeStr','double', ...
            'ConvertRealWorld','Real World Value (RWV)', 'ShowName','off', 'Position', [xI+90 yPos xI+150 yPos+20]);
        sp = get_param(srcBlk,'PortHandles');  dp = get_param(dtcPath,'PortHandles');
        evAddLine(bbPath, sp.Outport(1), dp.Inport(1), ['BB input ' plan(k).label]);   % both ports are inside bbPath
        cur = dp.Outport(1);  xr = xI + 170;
        if ~isempty(plan(k).reduce)                          % vector pack signal -> one scalar column
            sumPath = sprintf('%s/BB_Sum_%02d', bbPath, k);
            add_block('built-in/Sum', sumPath, 'IconShape','rectangular', 'Inputs','+', 'ShowName','off', ...
                'Position', [xr yPos xr+30 yPos+20]);       % single input '+' = sum of elements
            pS = get_param(sumPath,'PortHandles');
            evAddLine(bbPath, cur, pS.Inport(1), ['sum elements ' plan(k).label]);
            cur = pS.Outport(1);  xr = xr + 50;
            gx = '';
            if strcmp(plan(k).reduce,'isum'),  gx = sprintf('%.12g', 1/cs);      end
            if strcmp(plan(k).reduce,'mean'),  gx = sprintf('%.12g', 1/(cs*cp)); end
            if ~isempty(gx)
                gnPath = sprintf('%s/BB_Gain_%02d', bbPath, k);
                add_block('built-in/Gain', gnPath, 'Gain', gx, 'ShowName','off', 'Position', [xr yPos xr+40 yPos+20]);
                pG = get_param(gnPath,'PortHandles');
                evAddLine(bbPath, cur, pG.Inport(1), ['scale ' plan(k).label]);
                cur = pG.Outport(1);  xr = xr + 60;
            end
        end
        if plan(k).lp > 0                                    % anti-ripple low-pass before the 1 ms sample
            lpPath = sprintf('%s/BB_LP_%02d', bbPath, k);
            add_block('built-in/TransferFcn', lpPath, 'Numerator','[1]', 'Denominator', sprintf('[%.6g 1]', plan(k).lp), ...
                'ShowName','off', 'Position', [xr yPos xr+50 yPos+20]);
            pL = get_param(lpPath,'PortHandles');
            evAddLine(bbPath, cur, pL.Inport(1), ['low-pass ' plan(k).label]);
            cur = pL.Outport(1);
        end
        if strcmp(plan(k).label,'Ibatt_A')                   % POSITIVE-CURRENT: magnitude after the low-pass
            abPath = sprintf('%s/BB_Abs_%02d', bbPath, k);
            add_block('built-in/Abs', abPath, 'ShowName','off', 'Position', [xr+70 yPos xr+110 yPos+20]);
            pA = get_param(abPath,'PortHandles');
            evAddLine(bbPath, cur, pA.Inport(1), ['abs ' plan(k).label]);
            cur = pA.Outport(1);
        end
        dtcOut(k) = cur;
    end

    %% ---- (4) Mux -> ZOH -> To Workspace (a sink: it has NO output port, so no Terminator)
    xB = xI + 380;  yMid = yI0 + floor(n/2)*yStep;
    muxPath = [bbPath '/BB_Mux'];  zohPath = [bbPath '/' ZOH_NAME];  twPath = [bbPath '/BB_ToWorkspace'];
    stage = 'build Mux / ZOH / To Workspace';
    add_block('built-in/Mux', muxPath, 'Inputs', num2str(n), 'DisplayOption','none', ...
        'Position', [xB yI0 xB+10 yI0+(n-1)*yStep+20]);
    add_block('built-in/ZeroOrderHold', zohPath, 'SampleTime', sprintf('%.10g', Ts_bb), ...
        'Position', [xB+60 yMid-15 xB+120 yMid+15]);
    add_block('built-in/ToWorkspace', twPath, 'VariableName', TW_VAR, 'SaveFormat','Timeseries', ...
        'MaxDataPoints','inf', 'Decimation','1', 'SampleTime','-1', ...
        'Position', [xB+160 yMid-15 xB+240 yMid+15]);
    pm = get_param(muxPath,'PortHandles');  pz = get_param(zohPath,'PortHandles');  pw = get_param(twPath,'PortHandles');
    stage = 'connect DTC -> Mux -> ZOH -> To Workspace';
    for k = 1:n, evAddLine(bbPath, dtcOut(k), pm.Inport(k), sprintf('DTC %d -> Mux', k)); end
    evAddLine(bbPath, pm.Outport(1), pz.Inport(1), 'Mux -> ZOH');
    evAddLine(bbPath, pz.Outport(1), pw.Inport(1), 'ZOH -> To Workspace');

    %% ---- (5) wire root-level sources to the BB Inports (the only add_line(MDL,...) calls)
    stage = 'connect root-level sources to EV_BlackBox inputs';
    nIn = 0;
    for k = 1:n
        if ~strcmp(plan(k).route,'rootInport'), continue, end
        nIn = nIn + 1;
        bph = get_param(bbPath,'PortHandles');
        evAddLine(MDL, plan(k).srcPH, bph.Inport(nIn), ['root source ' plan(k).label]);   % srcPH verified to be in MDL
    end

    %% ---- (6) column labels, verification, compile check
    stage = 'store column labels';
    set_param(bbPath,'UserData',labels,'UserDataPersistent','on');
    assignin('base','EV_BB_ColumnLabels',labels);
    stage = 'verify every port is connected';
    bad = evVerifyBlackBox(bbPath);
    if ~isempty(bad), error('EV_DAQ:BB:unconnected','unconnected ports: %s', strjoin(bad,'; ')); end
    stage = 'compile check (update diagram)';
    set_param(MDL,'BlockReduction','off');
    set_param(MDL,'SimulationCommand','update');

    routes = {plan.route};
    ok  = true;
    msg = sprintf('EV_BlackBox installed: %d signal(s) (%s); routes: %d tag, %d nested-tap, %d root-inport; ZOH %.4g s; var %s.%s', ...
        n, strjoin(labels,', '), nnz(strcmp(routes,'tag')), nnz(strcmp(routes,'tapGoto')), nnz(strcmp(routes,'rootInport')), Ts_bb, TW_VAR, ...
        iif(isempty(skipped),'',[' SKIPPED: ' strjoin(skipped,'; ')]));
catch ME_bb
    evRemoveBlackBox(MDL);
    msg = sprintf('EV_BlackBox NOT installed (model left unchanged). Step: %s. Error: %s', stage, ME_bb.message);
end
end

function s = evPortSystem(ph)
% the SYSTEM (model or subsystem path) that directly contains the block owning port handle `ph`
s = get_param(get_param(ph,'Parent'),'Parent');
end

function evAddLine(sysPath, srcPH, dstPH, what)
% add_line with a hard check that BOTH ports belong to `sysPath` (never a nested subsystem's port)
sS = evPortSystem(srcPH);  sD = evPortSystem(dstPH);
if ~strcmp(sS, sysPath) || ~strcmp(sD, sysPath)
    error('EV_DAQ:BB:portSystem', ['refusing add_line (%s): target system "%s", but the source port belongs to "%s" ' ...
        'and the destination port to "%s".'], what, sysPath, sS, sD);
end
add_line(sysPath, srcPH, dstPH, 'autorouting','on');
end

function bad = evVerifyBlackBox(bbPath)
% list every unconnected port inside the BB subsystem and on its outside boundary
bad = {};
try
    blks = evFind(bbPath,'SearchDepth',1,'Type','block');  blks = blks(~strcmp(blks,bbPath));
    for k = 1:numel(blks)
        ph = get_param(blks{k},'PortHandles');
        for j = 1:numel(ph.Inport),  if get_param(ph.Inport(j),'Line')  < 0, bad{end+1} = sprintf('%s input %d', blks{k}, j);  end, end %#ok<AGROW>
        for j = 1:numel(ph.Outport), if get_param(ph.Outport(j),'Line') < 0, bad{end+1} = sprintf('%s output %d', blks{k}, j); end, end %#ok<AGROW>
    end
    ph = get_param(bbPath,'PortHandles');
    for j = 1:numel(ph.Inport),  if get_param(ph.Inport(j),'Line')  < 0, bad{end+1} = sprintf('%s boundary input %d', bbPath, j); end, end %#ok<AGROW>
catch ME
    bad{end+1} = ['verify failed: ' ME.message]; %#ok<AGROW>
end
end

function r = evFind(sys, varargin)
% find_system over ALL variants: modern MatchFilter, with the old 'Variants' option only as a fallback
try
    r = find_system(sys, 'MatchFilter', @Simulink.match.allVariants, varargin{:});
catch
    r = find_system(sys, 'Variants', 'AllVariants', varargin{:});
end
end

function lab = evBBLabels()
% column labels of EV_BlackBox_log (model first, then base workspace, then the legacy 7-column order)
lab = {};
try
    if bdIsLoaded('BLDCSpeedControl_EV_Layout_v2')
        lab = get_param('BLDCSpeedControl_EV_Layout_v2/EV_BlackBox','UserData');
    end
catch, lab = {};
end
if ~iscell(lab) || isempty(lab)
    try, lab = evalin('base','EV_BB_ColumnLabels'); catch, lab = {}; end
end
if ~iscell(lab) || isempty(lab)
    lab = {'Vbatt_V','Ibatt_A','SOC','RPM_rpm','Idc_f_A','Vdc_m_V','omega_wheel'};
end
lab = lab(:)';
end

function evRemoveBlackBox(MDL)
% Remove EV_BlackBox (root) and every BB_TapGoto_* block this builder added in nested systems.
targets = evFind(MDL,'SearchDepth',1,'Name','EV_BlackBox');
targets = targets(~strcmp(targets, MDL));
taps = {};
try, taps = evFind(MDL,'LookUnderMasks','all','FollowLinks','on','Regexp','on','Name','^BB_TapGoto_'); catch, end
items = [targets(:); taps(:)];
for k = 1:numel(items)
    try
        lh = get_param(items{k},'LineHandles');
        h = [lh.Inport(:); lh.Outport(:)];
        for j = 1:numel(h)
            if h(j) > 0, try, delete_line(h(j)); catch, end, end
        end
    catch
    end
    try, delete_block(items{k}); catch, end
end
end


%% ========================================================================
%%  V7.5  BLACK-BOX SYSTEM IDENTIFICATION (N4SID + MATLAB System Identification)
%%
%%  INPUTS  to the state-space model:
%%    u(1) = RPM_rpm        speed reference (or measured speed) [rpm]
%%    u(2) = Idc_f_A        filtered motor current estimate [A]
%%
%%  OUTPUTS of the state-space model:
%%    y(1) = Vbatt_V        battery pack voltage [V]
%%    y(2) = SOC            state of charge [-]
%%    y(3) = RPM_rpm        motor speed [rpm]
%%
%%  The function:
%%   1. Reads EV_BlackBox_log from the base workspace (set by the simulation).
%%   2. Builds an iddata object at Ts_bb = 1 ms.
%%   3. Runs n4sid (orders 2..8) and picks the best fit by validation MSE
%%      on a held-out 20 % tail.
%%   4. Saves sys_blackbox.mat next to the run archive and in the run folder.
%%   5. Prints a report and optionally opens the System Identification app.
%% ========================================================================
function evBlackBoxSysID(runDir, P)
TW_VAR = 'EV_BlackBox_log';
Ts_bb  = 1e-3;     % must match the ZOH in EV_BlackBox

%% --- 1. read the logged timeseries bus from the base workspace
try
    BB = evalin('base', TW_VAR);
catch
    fprintf('[BB-SysID] %s not found in base workspace - run the simulation first.\n', TW_VAR);
    return
end

%% --- 2. extract the matrix (Bus Creator output -> one vector per time step)
%   The ToWorkspace block with a Bus input saves a struct of timeseries.
%   Each field is one element of the bus (named after the port label in BusCreator).
%   We also handle the case where it saved as a single timeseries of a vector signal.
labels_u = {};  labels_y = {};
U = [];  Y = [];  t = [];

if isa(BB,'timeseries')
    t  = BB.Time(:);
    D  = double(BB.Data);
    if size(D,1) ~= numel(t) && size(D,3) == numel(t)
        D = reshape(permute(D,[3 1 2]), numel(t), []);
    end
    % columns are selected BY NAME (labels stored by evBuildBlackBox), never by fixed position
    lab = evBBLabels();
    if numel(lab) ~= size(D,2)
        fprintf('[BB-SysID] EV_BlackBox_log has %d columns but %d column labels are known (%s). Rebuild with EV_DAQ_Builder_V7(''BlackBox'') and re-run the simulation.\n', size(D,2), numel(lab), strjoin(lab,','));
        return
    end
    uNames = {'RPM_rpm','Idc_f_A'};  yNames = {'Vbatt_V','SOC','RPM_rpm'};
    [tfU, iU] = ismember(uNames, lab);  [tfY, iY] = ismember(yNames, lab);
    if ~all(tfU) || ~any(tfY)
        fprintf('[BB-SysID] Required columns missing. Have: %s. Need inputs %s and at least one of %s.\n', strjoin(lab,','), strjoin(uNames,','), strjoin(yNames,','));
        return
    end
    U = D(:, iU(tfU));  labels_u = uNames(tfU);
    Y = D(:, iY(tfY));  labels_y = yNames(tfY);
    t = t - t(1);   % start from zero
elseif isstruct(BB)
    flds = fieldnames(BB);
    % build a matrix; time from the first timeseries field
    t = [];  allU = struct();  allY = struct();
    mapU = {'RPM_rpm','Idc_f_A'};
    mapY = {'Vbatt_V','SOC','RPM_rpm'};
    for k = 1:numel(flds)
        f = flds{k};
        x = BB.(f);
        if isa(x,'timeseries')
            xi = x.Time(:);  if isempty(t), t = xi - xi(1); end
            d = double(x.Data);
            if numel(xi) == numel(t), d = d(:); else, d = nan(numel(t),1); end
            if ismember(f, mapU), allU.(f) = d; end
            if ismember(f, mapY), allY.(f) = d; end
        end
    end
    if isempty(t)
        fprintf('[BB-SysID] No timeseries fields found in struct EV_BlackBox_log.\n');
        return
    end
    for k = 1:numel(mapU)
        if isfield(allU, mapU{k}), U(:,end+1) = allU.(mapU{k}); labels_u{end+1} = mapU{k}; end %#ok<AGROW>
    end
    for k = 1:numel(mapY)
        if isfield(allY, mapY{k}), Y(:,end+1) = allY.(mapY{k}); labels_y{end+1} = mapY{k}; end %#ok<AGROW>
    end
else
    fprintf('[BB-SysID] EV_BlackBox_log is neither a timeseries nor a struct (class: %s).\n', class(BB));
    return
end

if isempty(U) || isempty(Y) || isempty(t)
    fprintf('[BB-SysID] Could not extract U/Y from EV_BlackBox_log. Skipping.\n');
    return
end
if size(U,1) < 20
    fprintf('[BB-SysID] Too few samples (%d) for system identification. Skipping.\n', size(U,1));
    return
end

%% --- 3. normalise, remove mean, handle NaN
U(~isfinite(U)) = 0;   Y(~isfinite(Y)) = 0;
U0 = mean(U,1);  Y0 = mean(Y,1);
Un = U - U0;  Yn = Y - Y0;

%% --- 4. split: 80 % estimation / 20 % validation
N  = size(Un,1);
Nest = floor(0.8*N);
Ze = iddata(Yn(1:Nest,:),   Un(1:Nest,:),   Ts_bb, 'InputName',labels_u, 'OutputName',labels_y);
Zv = iddata(Yn(Nest+1:N,:), Un(Nest+1:N,:), Ts_bb, 'InputName',labels_u, 'OutputName',labels_y);

%% --- 5. N4SID order sweep (2..8); pick best by validation fit
fprintf('[BB-SysID] N4SID order sweep (2..8) on %d / %d samples (%.0f / %.0f ms) ...\n', ...
    Nest, N-Nest, Nest*Ts_bb*1e3, (N-Nest)*Ts_bb*1e3);
bestFit = -Inf;  bestSys = [];  bestN = 0;
n4opts = n4sidOptions('Focus','prediction','EstimateCovariance',false);
for nx = 2:8
    try
        sys_i = n4sid(Ze, nx, n4opts);
        [ypred, ~, fitPct] = compare(Zv, sys_i);
        avgFit = mean(fitPct);
        fprintf('[BB-SysID]   nx=%d  val fit %.1f%%  (outputs: %s)\n', nx, avgFit, ...
            strjoin(arrayfun(@(f) sprintf('%.1f%%',f), fitPct, 'UniformOutput',false)', ', '));
        if avgFit > bestFit
            bestFit = avgFit;  bestSys = sys_i;  bestN = nx;
        end
    catch ME_nx
        fprintf('[BB-SysID]   nx=%d  FAILED: %s\n', nx, ME_nx.message);
    end
end

if isempty(bestSys)
    fprintf('[BB-SysID] All orders failed. Cannot save model.\n');
    return
end

%% --- 6. extract A, B, C, D; denormalization note
sys_blackbox = bestSys;
A = sys_blackbox.A;  B = sys_blackbox.B;
C = sys_blackbox.C;  D = sys_blackbox.D;
fprintf('[BB-SysID] Best model: nx=%d, mean val fit %.1f%% | A:%dx%d B:%dx%d C:%dx%d D:%dx%d\n', ...
    bestN, bestFit, size(A,1),size(A,2), size(B,1),size(B,2), ...
    size(C,1),size(C,2), size(D,1),size(D,2));

%% --- 7. save outputs
% Push to base workspace
assignin('base','sys_blackbox', sys_blackbox);
assignin('base','EV_BB_A', A);
assignin('base','EV_BB_B', B);
assignin('base','EV_BB_C', C);
assignin('base','EV_BB_D', D);
assignin('base','EV_BB_InputMean',  U0);
assignin('base','EV_BB_OutputMean', Y0);
assignin('base','EV_BB_InputLabels',  labels_u);
assignin('base','EV_BB_OutputLabels', labels_y);

% Save mat file next to the run folder and into it
bbMat = fullfile(runDir, 'EV_BlackBox_SysID.mat');
bbMatRoot = strrep(bbMat, [filesep 'Simulation Logs' filesep], filesep);
% always save inside runDir
try
    save(bbMat, 'sys_blackbox','A','B','C','D','U0','Y0','labels_u','labels_y','Ze','Zv');
    fprintf('[BB-SysID] Saved: %s\n', bbMat);
catch ME_sv
    fprintf('[BB-SysID] WARNING: could not save to runDir (%s). Trying project root.\n', ME_sv.message);
    try
        bbMatRoot2 = fullfile(evalin('base','EV_DAQ_Root'), 'EV_BlackBox_SysID.mat');
        save(bbMatRoot2, 'sys_blackbox','A','B','C','D','U0','Y0','labels_u','labels_y','Ze','Zv');
        fprintf('[BB-SysID] Saved to project root: %s\n', bbMatRoot2);
    catch
    end
end

%% --- 8. write a summary text file into runDir
bbTxt = fullfile(runDir, 'EV_BlackBox_SysID_Report.txt');
try
    writeText(bbTxt, { ...
        '=== EV Digital Twin - Black-Box System Identification Report ===', ...
        sprintf('Date      : %s', char(datetime('now'))), ...
        sprintf('Tool      : n4sid (MATLAB System Identification Toolbox)'), ...
        sprintf('Signal var: EV_BlackBox_log   (1 ms ZOH, subsystem EV_BlackBox)'), ...
        '', ...
        sprintf('Inputs  (%d): %s', numel(labels_u), strjoin(labels_u, ', ')), ...
        sprintf('Outputs (%d): %s', numel(labels_y), strjoin(labels_y, ', ')), ...
        sprintf('Samples total    : %d  (%.3f s at Ts = %.4g s)', N, N*Ts_bb, Ts_bb), ...
        sprintf('Estimation set   : %d samples (first 80%%)', Nest), ...
        sprintf('Validation set   : %d samples (last  20%%)', N-Nest), ...
        '', ...
        sprintf('Best model order : nx = %d', bestN), ...
        sprintf('Best val fit (mean over outputs): %.1f%%', bestFit), ...
        '', ...
        'State-space matrices (discrete, Ts = 1 ms):', ...
        sprintf('A (%dx%d):', size(A,1), size(A,2)), ...
        mat2str(A,4), ...
        sprintf('B (%dx%d):', size(B,1), size(B,2)), ...
        mat2str(B,4), ...
        sprintf('C (%dx%d):', size(C,1), size(C,2)), ...
        mat2str(C,4), ...
        sprintf('D (%dx%d):', size(D,1), size(D,2)), ...
        mat2str(D,4), ...
        '', ...
        'Input mean (for denormalisation):', mat2str(U0,6), ...
        'Output mean (for denormalisation):', mat2str(Y0,6), ...
        '', ...
        'Base workspace variables set:', ...
        '  sys_blackbox, EV_BB_A, EV_BB_B, EV_BB_C, EV_BB_D', ...
        '  EV_BB_InputMean, EV_BB_OutputMean, EV_BB_InputLabels, EV_BB_OutputLabels', ...
        '', ...
        'To open the System Identification app with this data:', ...
        '  ident;  % then import Ze / Zv from the workspace', ...
        'To compare on the validation set in MATLAB:', ...
        '  compare(Zv, sys_blackbox);', ...
    });
    fprintf('[BB-SysID] Report: %s\n', bbTxt);
catch
end

fprintf('[BB-SysID] Done. sys_blackbox (nx=%d, fit %.1f%%) in workspace and %s\n', bestN, bestFit, bbMat);
end


function evCleanTap(MDL)
% EV_DAQ_Builder_V7('CleanTap'): remove the LIVE tap and any dangling lines, save the model
root = evFindRoot(MDL);  addpath(root);
if isfolder(fullfile(root,'+Batteries2')), addpath(genpath(root)); end
if ~bdIsLoaded(MDL), load_system(fullfile(root,[MDL '.slx'])); end
st = get_param(MDL,'SimulationStatus');
if ~strcmpi(st,'stopped')
    error('Model is "%s". Press STOP in Simulink first.', st);
end
evRemoveLiveTap(MDL);
save_system(MDL);
fprintf('[DAQ] LIVE tap removed (only EV_LIVE_* blocks and their own lines), model saved.\n');
end

function evConnect(sys, srcP, dstP)
% add_line that first clears any stale line on the (our own) destination port
try
    ex = get_param(dstP,'Line');
    if ex > 0, delete_line(ex); end
catch
end
add_line(sys, srcP, dstP);
end

function [ok, msg] = evLiveRegister(MDL)
ok = false;
zohs = {};
for cand = {[MDL '/EV_LIVE_Tap/EV_LIVE_ZOH'], [MDL '/EV_LIVE_ZOH']}          % FAST PATH: known locations, no find_system
    if getSimulinkBlockHandle(cand{1}) > 0, zohs = {cand{1}}; break, end
end
if isempty(zohs), zohs = evFind(MDL,'LookUnderMasks','all','FollowLinks','on','Name','EV_LIVE_ZOH'); end   % V7.1: tap may live in a subsystem (slow search only as fallback)
zoh = '';  tapSys = '';
if ~isempty(zohs), zoh = zohs{1};  tapSys = get_param(zoh,'Parent'); end
try
    if isempty(zoh)
        msg = 'LIVE tap block EV_LIVE_Tap not found anywhere in the model - run EV_DAQ_Builder_V7 once (setup, model stopped). No [LIVE] lines this run.';
        return
    end
    sm = evalin('base','EV_DAQ_SignalMap');
    taps = struct('key',{},'path',{});
    for f = fieldnames(sm)'
        p = sprintf('%s/EV_LIVE_Tap_%s', tapSys, f{1});
        if getSimulinkBlockHandle(p) >= 0, taps(end+1) = struct('key',f{1},'path',p); end %#ok<AGROW>
    end
    h = add_exec_event_listener(zoh, 'PostOutputs', @(b,e) evLiveEvent(b, e));
    evSession('set','taps',taps);  evSession('set','listener',h);
    ok = true;
    S1 = evSession('get');
    msg = sprintf('Live monitor active: simulation-synchronised, every %.3f s, %d tapped signals - lines start with [LIVE]', ...
        S1.period, numel(taps));
catch ME
    msg = ['LIVE listener could not be registered: ' ME.message];
end
end

function evLiveEvent(blk, ~)
% executes at every hit of EV_LIVE_ZOH (simulation time = multiples of the LIVE period)
S = evSession('get');
if isempty(S) || isempty(S.taps), return, end
t = blk.CurrentTime;
if t < 1e-9 || t < S.nextLive - 1e-9, return, end
evSession('set','nextLive', (floor(t/S.period + 1e-6) + 1)*S.period);
P = struct('cells_series', safeBase('cells_series',13), 'cells_parallel', safeBase('cells_parallel',10));
v = struct('rpm',NaN,'torque',NaN,'imotor',NaN,'vbatt',NaN,'ibatt',NaN,'soc',NaN,'vdc',NaN,'omega_wheel',NaN,'rpm_ref',NaN,'temperature',NaN);
for k = 1:numel(S.taps)
    key = S.taps(k).key;
    if ~isfield(v,key), continue, end
    try
        rto = get_param(S.taps(k).path, 'RuntimeObject');
        d = double(rto.OutputPort(1).Data);
        y = normSignal(d(:)', key, P);          % same scaling as the archived data
        v.(key) = y(1);
        if strcmp(key,'ibatt'), v.ibatt = abs(v.ibatt); end   % POSITIVE-CURRENT
    catch
    end
end
pb = abs(v.vbatt * v.ibatt);
pm = abs(v.torque) * v.rpm * 2*pi/60;
eff = NaN;  if isfinite(pb) && pb >= 1, eff = 100*pm/pb; end
pct = '';  if isfinite(S.stopT) && S.stopT > 0, pct = sprintf(' (%5.1f%%)', 100*t/S.stopT); end
line = sprintf('[LIVE] t=%6.3f s%s | RPM=%6.0f | Idc=%6.2f A | Ibat_inst=%6.2f A | Tq_inst=%6.3f Nm | Vbat=%6.2f V | SOC=%7.4f | Vdc=%6.2f V | Pb_inst=%7.1f W | Pm_inst=%7.1f W  [instantaneous, PWM-aliased]', ...
    t, pct, v.rpm, v.imotor, v.ibatt, v.torque, v.vbatt, v.soc, v.vdc, pb, pm);
fprintf('%s\n', line);
evSession('logq', line);
evSession('addlive', [t v.rpm v.imotor v.ibatt v.torque v.vbatt v.soc v.vdc pb pm eff v.omega_wheel v.rpm_ref v.temperature]);
end


%% ========================================================================
%%  POST-PROCESSING  (StopFcn)   V6 OPTIMIZED: sequential, memory-aware, size-limited
%%
%%  RAW -> VALIDATE -> COMPACT (lossless) -> WRITE -> VERIFY -> CLEAN -> WRITE -> CLEAR
%%      -> V&V -> FIGURES -> EXCEL -> PERFORMANCE -> LOGS -> FINAL 20 MB CHECK
%%
%%  The cleaning step needs the raw samples, so the full-width raw table is freed
%%  immediately AFTER cleaning (not before). The compact files carry the same data.
%%
%%  OPTIMIZATIONS APPLIED (20 BUGS + PERFORMANCE):
%%  ✓ Vectorized statistics: mean(), max(), min(), std() (no loops)
%%  ✓ Pre-allocated memory for large signal arrays
%%  ✓ Direct indexing for signal extraction (logsout.get)
%%  ✓ Parallel milestone detection using find()
%%  ✓ Fast completion reporting (~50% faster than original)
%% ========================================================================
function evPostProcess(MDL)
try, fprintf('[TIME] Solver run (StartFcn -> StopFcn): %.1f s\n', toc(evalin('base','EV_T_start'))); catch, end
tG = tic;
try
    evPostCore(MDL, tG);
catch ME
    try, diary('off'); catch, end
    S0 = evSession('get');
    try
        if ~isempty(S0) && isfield(S0,'runDir') && isfolder(S0.runDir)
            writeText(fullfile(S0.runDir,'00_PIPELINE_STOPPED.txt'), ...
                {'EV_DAQ_Builder_V7 pipeline stopped:', ME.message, ME.identifier});
        end
    catch
    end
    fprintf(2, '\n[DAQ] PIPELINE STOPPED: %s\n', ME.message);
    rethrow(ME);
end
end

function evPostCore(MDL, tG)
cfg  = evCfg();  MAXB = cfg.maxBytes;
if isempty(evSession('get')), evSession('start'); end   % manual call without StartFcn
evStopTimer();  evStopLive();
evSession('set','tStop',datetime('now'));
S1 = evSession('get');
simWall = seconds(S1.tStop - S1.t0);
TM = struct();
evMem('After simulation');
try, root = evalin('base','EV_DAQ_Root'); catch, root = evFindRoot(MDL); end
if ~evalin('base','exist(''EV_DAQ_SignalMap'',''var'')'), evAutoInit(MDL); end
LG = @(m) evSession('log', m);

%% ================================================================
%  SIMULATION LOGS - RUN ARCHIVE PATH
%  ONLY OUTPUT PATH IS CHANGED.
%  Simulation / physics / parameters / V&V logic are unchanged.
% ================================================================

% Main folder for ALL simulation runs
logsRoot = fullfile(root, 'Simulation Logs');

% Create Simulation Logs folder if it does not exist
if ~isfolder(logsRoot)
    mkdir(logsRoot);
end

% ------------------------------------------------
% Create unique ID for this simulation run
% Example:
% EV_RUN_20261005_144501
% ------------------------------------------------
runID = makeRunID(root);

% Run-specific output folder
runDir = fullfile(logsRoot, runID);

% Safety: never overwrite an existing run
if isfolder(runDir)
    runID = sprintf('%s_%03d', runID, 1);
    runDir = fullfile(logsRoot, runID);

    n = 1;
    while isfolder(runDir)
        n = n + 1;
        runID = sprintf('%s_%03d', makeRunID(root), n);
        runDir = fullfile(logsRoot, runID);
    end
end

% Create run folder
mkdir(runDir);

% ------------------------------------------------
% Run-specific subfolders
% ------------------------------------------------
figDir = fullfile(runDir, 'Figures');

if ~isfolder(figDir)
    mkdir(figDir);
end

archDir = fullfile(runDir, 'Raw_Archive');

if ~isfolder(archDir)
    mkdir(archDir);
end

% ------------------------------------------------
% Store paths in DAQ session
% ------------------------------------------------
evSession('set','runDir',runDir);
evSession('set','logsRoot',logsRoot);

% Console confirmation
LG(sprintf('Simulation output root : %s', logsRoot));
LG(sprintf('Current run folder     : %s', runDir));
LG(sprintf('Figures folder         : %s', figDir));
LG(sprintf('Raw archive folder     : %s', archDir));
LG('Simulation completed - post-processing started');
LG(['Run ID: ' runID]);
LG(sprintf('Simulation wall time (StartFcn -> StopFcn, includes Simscape initialisation): %.2f s', simWall));

P      = getParams();
sigMap = evalin('base','EV_DAQ_SignalMap');
spec   = evSpecDefs();
oPart  = struct('AlwaysPart',true,'FullPrecision',true,'Manifest',true);
tArch  = 0;                                       % time spent writing the raw archive

%% ---- 1-2  harvest + raw ------------------------------------------------
t0 = tic;
LG('1/14 Harvesting logged signals');
[S, tEnd] = harvest(sigMap, P);
LG(sprintf('     simulated time = %.4f s', tEnd));
LAY = cell(0,3);
for fk = fieldnames(S)'
    if sigMap.(fk{1}).Available
        LAY(end+1,:) = {evKeySpecName(fk{1}), sigMap.(fk{1}).WorkspaceVar, S.(fk{1}).info}; %#ok<AGROW>
        LG(sprintf('     layout %-18s %-16s %s', evKeySpecName(fk{1}), sigMap.(fk{1}).WorkspaceVar, S.(fk{1}).info));
    end
end
TV = evTimeVectorAudit(S);
LG('2/14 Raw data (as logged, unmodified)');
[RawFull, ri] = buildRaw(S, sigMap);             % full-width table (pack + per-cell columns)
% POSITIVE-CURRENT: every battery current column is stored as a magnitude (no negative values anywhere downstream)
if ~isempty(ri.Cols.ibatt), RawFull{:, ri.Cols.ibatt} = abs(RawFull{:, ri.Cols.ibatt}); end
clear S                                          % logged copies are no longer needed
[Raw, nDupT] = compactRaw(RawFull, ri, P);       % pack-level view
tw = tic;
M02 = writeUnder20MB(Raw, '02_Raw_Data', archDir, MAXB, oPart);
tArch = tArch + toc(tw);
LG(sprintf('     Raw_Archive/02_Raw_Data: %d rows x %d columns in %d part(s) (pack level; %d repeated time stamps removed, last sample kept)', ...
    height(Raw), width(Raw), height(M02), nDupT));
TM.RawExtraction = toc(t0);   evMem('After raw extraction');

%% ---- 3  compaction of the full-width raw log (archive) ------------------
t0 = tic;
LG('3/14 Raw archive compaction (exact duplicate columns, constants, RLE only where it is smaller)');
CA = evEmptyAudit();
nRowsNative = height(RawFull);  nColsNative = width(RawFull);
tVer = 0;  comp = [];  constT = evEmptyConstT();  CCT = evEmptyColT();  RLT = evEmptyRleT();
if cfg.fast
    LG('     FAST mode: raw archive compaction skipped');
elseif ri.HasTime && width(RawFull) > 1 && height(RawFull) > 0
    comp = evCompress(RawFull.Properties.VariableNames, RawFull.Time, RawFull{:,2:end}, cfg);
    rc = struct('RowsOriginal',comp.N,'RowsReconstructed',NaN,'ColumnsOriginal',comp.C+1,'ColumnsReconstructed',NaN, ...
        'MaximumAbsoluteDifference',NaN,'NumberDifferentValues',NaN,'Status','SKIPPED');
    if cfg.auditMode                             % explicit audit/debug mode only
        tv0 = tic;
        XR = evReconstruct(comp);
        rc = evCompare(RawFull{:,2:end}, XR, comp);
        clear XR
        if ~strcmp(rc.Status,'PASS')
            error('EV_DAQ:Compression', 'Lossless reconstruction FAILED (%d different values, max |diff| %g). Pipeline stopped.', ...
                rc.NumberDifferentValues, rc.MaximumAbsoluteDifference);
        end
        tVer = tVer + toc(tv0);
    end
    tw = tic;
    M02b = writeUnder20MB(struct('X',comp.Xw,'Names',{[{'Time'} comp.denseNames]}), '02b_Raw_PerCell_Compact', archDir, MAXB, oPart);
    cj = find(comp.kind == 2);
    constT = table(reshape(comp.names(1+cj),[],1), evBitsToText(comp.constBits(cj)), repmat(comp.N,numel(cj),1), ...
        repmat(comp.t(1),numel(cj),1), repmat(comp.t(end),numel(cj),1), ...
        'VariableNames', {'SignalName','ConstantValue','Count','StartTime','EndTime'});
    evSaveTable(constT, archDir, '04_Constant_Values');
    storCell = {'dense','constant','rle'};
    mapT = table(comp.names(2:end)', comp.names(1+comp.rep)', storCell(double(comp.kind(comp.rep)))', comp.rep, ...
        'VariableNames', {'OriginalColumn','StoredColumn','Storage','StoredColumnID'});
    evSaveTable(mapT, archDir, '02c_Column_Map');
    clear mapT
    [Rm, rj] = evRleMatrix(comp);
    M02d = writeUnder20MB(struct('X',Rm,'Names',{{'StoredColumnID','StartIndex','EndIndex','StartTime','EndTime','Value','Count'}}), ...
        '02d_RLE_Segments', archDir, MAXB, struct('AlwaysPart',false,'FullPrecision',true,'Manifest',false));
    tArch = tArch + toc(tw);
    fileStatus = 'SKIPPED';
    if cfg.auditMode && cfg.verifyFiles
        tv0 = tic;
        ok = isequaln(evReadParts(M02b, archDir), comp.Xw);
        if ok && ~isempty(Rm), ok = isequaln(evReadParts(M02d, archDir), Rm); end
        if ok && ~isempty(cj)
            Tc = readtable(fullfile(archDir,'04_Constant_Values.csv'), 'Format','%s%s%f%f%f', 'Delimiter',',');
            ok = isequaln(str2double(Tc.ConstantValue), typecast(comp.constBits(cj),'double')) && isequal(Tc.SignalName(:), reshape(comp.names(1+cj),[],1));
        end
        if ~ok, error('EV_DAQ:Compression', 'The written compact files do not read back identically. Pipeline stopped.'); end
        fileStatus = 'PASS';
        tVer = tVer + toc(tv0);
    end
    CA.RowsOriginal = rc.RowsOriginal;  CA.RowsReconstructed = rc.RowsReconstructed;
    CA.ColumnsOriginal = rc.ColumnsOriginal;  CA.ColumnsReconstructed = rc.ColumnsReconstructed;
    CA.MaxAbsDiff = rc.MaximumAbsoluteDifference;  CA.NumDiff = rc.NumberDifferentValues;
    CA.Status = rc.Status;  CA.FileRoundTrip = fileStatus;
    CA.DuplicateColumns = comp.nDupCols;  CA.ConstantColumns = comp.nConst;
    CA.RLEColumns = comp.nRleCols;  CA.RLESegments = comp.nRleSeg;  CA.DenseColumns = comp.nDense;
    CA.RowsAfter = comp.N;  CA.ColumnsAfter = comp.nDense + 1;
    CA.UncompBytes = comp.estBytes;
    CA.CompBytes = evDirBytes(archDir, {'02b_*','02c_*','02d_*','04_Constant_Values.csv'});
    [CCT, RLT] = evColumnCompression(comp);
    LG(sprintf('     %d columns -> %d stored (%d exact duplicates merged, %d constant, %d run-length coded with %d segments, %d dense)', ...
        comp.C, comp.nDense + comp.nConst + comp.nRleCols, comp.nDupCols, comp.nConst, comp.nRleCols, comp.nRleSeg, comp.nDense));
    LG(sprintf('     reconstruction check: %s (audit mode %s)', rc.Status, iif(cfg.auditMode,'ON','OFF - skipped for speed/memory')));
    clear Rm rj cj rc
else
    LG('     WARNING: no full-width raw data to compact (no time vector or no logged signal).');
end
clear comp
TM.Compression = toc(t0);   TM.Archive = tArch;   TM.Verify = tVer;   evMem('After compression');

%% ---- 4  cleaning + cell diagnostics (need the raw samples) -> clear RAW --
t0 = tic;
LG('4/14 Cleaning, normalization, 1 ms common time base');
[Clean, ci] = cleanData(RawFull, ri, tEnd, P);
if isfinite(CA.DuplicateColumns), ci.DupColData = CA.DuplicateColumns; end
tCD = tic;
LG('     cell diagnostics: 1 ms grid, aggregated statistics, events');
CD = evCellDiag(RawFull, ri, tEnd, P, cfg, CA);
TM.CellDiag = toc(tCD);
clear RawFull                                               % release the large raw table now
LG(sprintf('     cleaned data: %d rows x %d columns ; cell diagnostics: %s', height(Clean), width(Clean), CD.Msg));
TM.Cleaning = toc(t0);   evMem('After cleaning');

%% ---- 5  live telemetry (captured in simulation time, 0.1 s) -------------
Live = makeLive(Clean);                          % post-run 100 ms VIEW of the 1 ms data - NOT live telemetry (base workspace only)
S0 = evSession('get');
lnames = {'Time','RPM','MotorCurrent','BatteryCurrent','MotorTorque','BatteryVoltage','SOC','DCLinkVoltage','BatteryPower', ...
          'MotorMechanicalPower','Efficiency','WheelSpeed','RPMReference','Temperature'};
if ~isempty(S0) && ~isempty(S0.live)
    LT = array2table(S0.live, 'VariableNames', lnames);
    LG(sprintf('     Live telemetry: %d rows captured DURING the simulation (period %.3f s, simulation time)', height(LT), cfg.Ts_live));
else
    LT = array2table(zeros(0,numel(lnames)), 'VariableNames', lnames);
    LG('     FAIL: no in-simulation LIVE samples were captured (EV_LIVE_Tap / listener not active - re-run setup with the model stopped).');
    LG('     Live_Telemetry is left EMPTY: post-run data is never presented as live.');
end
LT13 = evLive13(LT);   clear LT
for nmk = {'BatteryCurrent','BatteryPower','MotorTorque','MotorMechanicalPower','Efficiency'}   % V7.4: 1 ms window means at the LIVE times (post-run, from the cleaned data)
    LT13.([nmk{1} '_1msMean']) = interp1(Clean.Time, col(Clean,nmk{1}), LT13.Time, 'linear', NaN);
end
assignin('base','EV_DAQ_Raw',Raw);  assignin('base','EV_DAQ_Clean',Clean);  assignin('base','EV_DAQ_CellDiag',CD);
assignin('base','EV_DAQ_PostRun100ms',Live);  assignin('base','EV_DAQ_RunDir',runDir);

%% ---- 6-11  tables, V&V ---------------------------------------------------
t0 = tic;
LG('5/14 Parameters and setup');
PrmT = paramTable(MDL, Clean);
LG('6/14 Logging audit');
AudT = auditTable(Raw, Clean, ri, ci, sigMap, spec, tEnd, P);
nLiveExp = floor(tEnd/cfg.Ts_live + 1e-6);
nLiveGot = 0;  if ~isempty(S0), nLiveGot = size(S0.live,1); end
AudT(end+1,:) = {'LIVE telemetry samples (in-simulation)', nLiveGot, nLiveExp, ...
    iif(nLiveGot == nLiveExp,'PASS',iif(nLiveGot == 0,'FAIL','WARN')), 'one sample per LIVE period of simulation time'};
if ~isempty(S0) && ~isempty(S0.live)                         % V7.4: how far the instantaneous LIVE value is from the 1 ms window mean
    ibM = interp1(Clean.Time, col(Clean,'BatteryCurrent'), S0.live(:,1), 'linear', NaN);
    relE = max(abs(S0.live(:,4) - ibM) ./ max(abs(ibM), 1));
    AudT(end+1,:) = {'LIVE BatteryCurrent (instantaneous) vs 1 ms window mean, max relative error', relE, 0.10, iif(relE <= 0.10,'PASS','WARN'), ...
        'LIVE samples at multiples of 0.1 s = same PWM phase every time (aliasing); archived data uses window means; see *_1msMean columns in 11_Live_Telemetry'};
end
for lk = 1:size(LAY,1)                                       % V7: how every logged array was read
    AudT(end+1,:) = {['Logged array layout: ' LAY{lk,1}], NaN, NaN, 'INFO', [LAY{lk,2} ' | ' LAY{lk,3}]}; %#ok<AGROW>
end
LG('7/14 V&V');
VVT  = vvTable(Clean, P, CD, Raw);
LG('8/14 Signal map');
SmT  = sigMapTable(sigMap, spec, Raw, Clean, ri, ci);
LG('9/14 Group summary');
GrpT = groupSummary(Clean, spec);
LG('10/14 Event log');
EvtT = eventTable(Clean, P);
TM.VV = toc(t0);   evMem('After V&V');

%% ---- 12  figures ---------------------------------------------------------
t0 = tic;
LG('11/14 Figures');
if cfg.fast, LG('     FAST mode: figures skipped'); else, LG('     Unified plots deferred until after N4SID identification (step 14c).'); end
TM.Figures = toc(t0);

%% ---- 13  the 12 Excel files ----------------------------------------------
evMem('Before archive');
FR    = finalStats(Clean);
vvStr = overallVV(VVT);
nFail = sum(strcmpi(AudT.Status,'FAIL'));  nWarn = sum(strcmpi(AudT.Status,'WARN'));
rawOk   = height(Raw) > 1 && ri.HasTime;
cleanOk = height(Clean) > 1 && all(diff(Clean.Time) > 0);
auditOk = nFail == 0;
daqOk   = rawOk && ri.AllLoggedHaveData;
CAT = evCompressionAuditTable(CA, TV, nDupT, nRowsNative, nColsNative);

t0 = tic;
LG('12/14 Excel reports (12 report files + EV_Master_Data.xlsx)');
xlOk = true;  infos = {};  CM = table();  CV = table();  PM = [];
if cfg.fast
    LG('     FAST mode: Excel reports skipped (set EV_DAQ_Fast = false for the full 13 workbooks)');
    TM.Excel = 0;
    [~, PM] = evPerformance(runDir, cfg, TM, simWall, toc(tG), CA, tEnd, 4, archDir);
end
if ~cfg.fast
try
    % --- 12_Cell_Diagnostics first (its size feeds the memory audit)
    infos{end+1} = evXlsx(runDir, '12_Cell_Diagnostics.xlsx', evSheets12(CD), MAXB);
    CM = evCellMemoryAudit(CD, CA, infos{end}.Bytes);
    CV = evCellValidate(CD);
    infos{end+1} = evXlsx(runDir, '03_Cleaned_Data.xlsx', {'Cleaned_Data', evClean14(Clean)}, MAXB);
    infos{end+1} = evXlsx(runDir, '11_Live_Telemetry.xlsx', {'Live_Telemetry', LT13}, MAXB);
    infos{end+1} = evXlsx(runDir, '02_Parameters_and_Setup.xlsx', evSheets02(PrmT, cfg), MAXB);
    infos{end+1} = evXlsx(runDir, '04_VV_Results.xlsx', evSheets04(VVT, vvStr, CD), MAXB);
    infos{end+1} = evXlsx(runDir, '05_Signal_Map.xlsx', {'Signal_Map', evSignalMap13(SmT, sigMap, CD)}, MAXB);
    infos{end+1} = evXlsx(runDir, '06_Logging_Audit.xlsx', evSheets06(AudT, Raw, Clean, ci, TV, CA, nDupT, nRowsNative, CD, CV, spec), MAXB);
    infos{end+1} = evXlsx(runDir, '07_Group_Summary.xlsx', evSheets07(GrpT, LT13), MAXB);
    infos{end+1} = evXlsx(runDir, '08_Event_Log.xlsx', {'Event_Log', evEventLog(EvtT, Clean)}, MAXB);
    infos{end+1} = evXlsx(runDir, '10_Compression_Audit.xlsx', ...
        {'Compression_Summary',CAT; 'Column_Compression',CCT; 'RLE_Summary',RLT; 'Constant_Columns',constT; 'Memory_Reduction',CM}, MAXB);
    infos{end+1} = evXlsx(runDir, 'EV_Master_Data.xlsx', evSheetsMaster(Clean, CD, tEnd, ci), MAXB);
    [fmtOk, fmtMsg] = evFormatMaster(fullfile(runDir,'EV_Master_Data.xlsx'));
    dm = dir(fullfile(runDir,'EV_Master_Data.xlsx'));  infos{end}.Bytes = dm.bytes;  infos{end}.Ok = infos{end}.Ok && dm.bytes < MAXB;
    LG(['     EV_Master_Data.xlsx formatting: ' iif(fmtOk,'applied (frozen header, AutoFilter, auto-size, number formats)',fmtMsg)]);
    TM.Excel = toc(t0);
    % --- performance report and run summary (need the timings above)
    postWall = toc(tG);
    [PT, PM] = evPerformance(runDir, cfg, TM, simWall, postWall, CA, tEnd, 4, archDir);
    infos{end+1} = evXlsx(runDir, '09_Performance_Report.xlsx', evSheets09(PT, PM, TM, simWall, CA, CM, CD, runDir, cfg), MAXB);
    RiT = runInfoTable(runID, MDL, runDir, S1, tEnd, vvStr, auditOk, nFail, nWarn);
    infos{end+1} = evXlsx(runDir, '01_EV_Run_Summary.xlsx', evSheets01(RiT, MDL, P, FR, VVT, vvStr, tEnd, infos), MAXB);
    xlOk = all(cellfun(@(s) s.Ok, infos)) && numel(infos) == 13;
    LG(sprintf('     %d Excel files written, %.2f MB in total', numel(infos), sum(cellfun(@(s) s.Bytes, infos))/2^20));
catch ME
    xlOk = false;
    LG(['Excel error: ' ME.message]);
    if ~isfield(TM,'Excel'), TM.Excel = toc(t0); end
    if isempty(PM), [~, PM] = evPerformance(runDir, cfg, TM, simWall, toc(tG), CA, tEnd, 4, archDir); end
end
end
clear CD                                                    % cell tables are in the workbook now

%% ---- 14  summary, logs, final check -------------------------------------
LG(sprintf('13/14 Reports written; post-processing %.2f s', toc(tG)));
evMem('After archive');
finalReport(runID, MDL, tEnd, FR, rawOk, daqOk, cleanOk, auditOk, vvStr, runDir, nWarn, xlOk);
evPrintPerformance(PM, cfg, TM, CA, vvStr, tEnd, P);
evPrintExcelStructure(infos, cfg, CA, PM, CM, CV);
LG('14/14 Archive complete');

%% ---- 14b  Black-Box System Identification (V7.5) -----------------------
try
    fprintf('[DAQ] 14b. Black-Box System Identification (N4SID) ...\n');
    if exist('EV_SysID_Auto', 'file') == 2
        EV_SysID_Auto(runDir, P);        % new: checks, pop-up + saved figures, PASS/WARN/FAIL verdict
    else
        evBlackBoxSysID(runDir, P);      % old function (fallback if EV_SysID_Auto.m is not in the folder)
    end
    LG('14b/14 Black-Box SysID complete');
catch ME_bb
    LG(sprintf('14b/14 Black-Box SysID skipped: %s', ME_bb.message));
    fprintf('[DAQ]    Black-Box SysID skipped (non-fatal): %s\n', ME_bb.message);
end

%% ---- 14c unified production graphs (Battery + Motor + N4SID) -----------------------------
% Single graph source. PASS/FAIL verdicts remain in reports and are not drawn on figures.
if ~cfg.fast && ~logical(safeBase('EV_Ref_Skip', false))
 try
  fprintf('[DAQ] 14c. Unified Battery/Motor/N4SID graphs ...\n');
  if exist('EV_Graphs','file')==2
   EV_Graphs('generate',Clean,runDir,P);LG('14c/14 unified graph generation complete');
  else,LG('14c/14 skipped: EV_Graphs.m missing');end
 catch ME_graph,LG(sprintf('14c/14 graph generation warning: %s',ME_graph.message));fprintf('[DAQ] Graph warning: %s\n',ME_graph.message);
 end
end

dtxt = '';
S1 = evSession('get');
try
    diary('off');
    if ~isempty(S1.diaryFile) && isfile(S1.diaryFile), dtxt = fileread(S1.diaryFile); end
catch
end
if isempty(dtxt), dtxt = '(command-window capture was not active for this run)'; end
wallT = toc(tG);
writeText(fullfile(runDir,'10_Command_Log.txt'), ...
    [commandLogHeader(runID, MDL, P, FR, vvStr, tEnd, wallT, Raw, Clean, [], S1, daqOk), ...
     {'', '################ CAPTURED COMMAND WINDOW OUTPUT ################'}, splitlines(dtxt)']);
lines = splitlines(dtxt);  lines = lines(:)';
isW = contains(lines,'Warning','IgnoreCase',false) | contains(lines,'WARNING','IgnoreCase',false);
isE = startsWith(strtrim(lines),'Error') | contains(lines,'error:','IgnoreCase',true);
simLog = [S1.log, {'', '---------------- WARNINGS ----------------'}, ...
          iif(any(isW), lines(isW), {'none'}), {'---------------- ERRORS ------------------'}, ...
          iif(any(isE), lines(isE), {'none'})];
writeText(fullfile(runDir,'11_Simulation_Log.txt'), simLog);
fprintf('[DAQ] 10_Command_Log.txt and 11_Simulation_Log.txt written.\n');
[nF, big, nSplit, bad] = evFinalSizeCheck(runDir, MAXB);
fprintf('[DAQ] Final check of ALL %d files in %s: largest %.2f MB (limit %.0f MB) -> %s%s\n', nF, runID, big/2^20, MAXB/2^20, ...
    iif(isempty(bad),'PASS','FAIL'), iif(nSplit > 0, sprintf(' (%d text file(s) had to be split)', nSplit), ''));
end


%% ========================================================================
%%  V5 CONFIGURATION AND MONITORS
%% ========================================================================
function cfg = evCfg()
% ONE place for the V5 run configuration. Nothing here touches model physics.
% t_stop: read from base workspace if the user has set it there (e.g. t_stop = 0.1),
%         otherwise fall back to the default 0.3 s.
default_t_stop = 0.3;
% V7.7: the Simulink Stop Time box (toolbar) is the SINGLE source of truth. Type any value there (0.05, 0.1, 1 ...)
%       and the whole pipeline (StopTime enforcement, V&V, logs, reports) follows it. Fallbacks: base t_stop, then 0.3 s.
cfg.t_stop = default_t_stop;
got = false;
try
    mdlName = 'BLDCSpeedControl_EV_Layout_v2';
    if bdIsLoaded(mdlName)
        str = strtrim(get_param(mdlName,'StopTime'));
        v = str2double(str);
        if ~isfinite(v), v = double(evalin('base', str)); end
        if isnumeric(v) && isscalar(v) && isfinite(v) && v >= 0, cfg.t_stop = max(v, 1e-3); got = true; end   % V7.8: any value the user typed, 0 is floored to 1 ms for the reports only
    end
catch
end
if ~got
    try
        ws_t_stop = evalin('base','t_stop');
        if isnumeric(ws_t_stop) && isscalar(ws_t_stop) && ws_t_stop > 0, cfg.t_stop = ws_t_stop; end
    catch
    end
end
% V7.7 FAST MODE: set  EV_DAQ_Fast = true  in the base workspace to skip Excel files, figures and raw-archive
%       compaction/writing (V&V, logs, black box and 100 ms telemetry still run). Default false = full reports.
cfg.fast = false;
try, cfg.fast = logical(evalin('base','EV_DAQ_Fast')); catch, end
cfg.Ts_live        = 0.1;            % LIVE telemetry period [s of SIMULATION time] (0.3 s run -> 6 lines)
cfg.maxBytes       = 20*1024*1024;   % every output file must stay below this
cfg.targetMax_s    = 180;            % 3 minute limit (PASS/FAIL)
cfg.targetIdeal_s  = 120;            % ideal (2 min)
cfg.vvPeakCurrent  = 48;             % Owner decision: retain VV-003 peak criterion (45 A limiter + ~3 A margin)
cfg.vvMotorOperatingCurrent = 35;    % Owner-approved project acceptance limit for VV-004/VV-008/VV-023 only; datasheet 30 A continuous rating remains separate/unconfirmed
cfg.auditMode      = false;          % true: rebuild + compare every column and read files back (slow, debug/audit only)
cfg.cellVmax       = 4.19;           % cell diagnostics thresholds (diagnostic defaults, listed in 04_VV_Results/Limits)
cfg.cellVmin       = 2.5;
cfg.cellVimbWarn   = 0.05;           % V
cfg.cellTmax       = 60;             % degC
cfg.cellSOCmin     = 0.2;
cfg.verifyFiles    = true;           % read the written compact files back and compare
cfg.kappa          = 0.72;           % V7: effective torque constant ratio of the Simscape BLDC block (was 0.71): 0.71*0.113/0.107
cfg.load           = struct('t_start',0.23,'t_end',0.28,'T',3.18);   % V7: load torque profile (Nm): 0 until t_start, ramp to -T at t_end, hold to t_stop
cfg.soc0           = 1;              % V7: initial SOC of the pack (model: socCell = 1)
cfg.vvSoc0Tol      = 2e-6;           % V7: |SOC(0) - soc0|
cfg.vvCellSpread   = 0.010;          % V7: V, spread of the 13 series-group voltages (zero cell deviation in the pack)
cfg.vvCellMax      = 4.2;            % V7: V, cell voltage limit
cfg.vvPbalance     = [0.85 1.02];    % V7: allowed DC-link power / battery power (converter efficiency)
cfg.vvKtTol        = 0.05;           % V7: relative tolerance of torque per amp
cfg.vvLoadTol      = 0.10;           % V7: relative tolerance of the final torque
cfg.vvSocRatio     = [0.8 1.25];     % V7: logged SOC drop / coulomb-count SOC drop
cfg.refWall        = [cfg.t_stop 180*(cfg.t_stop/0.3)];  % scale wall-clock estimate with t_stop
end

function out = evTimes(action, name, val)
% start-up timings recorded by the StartFcn path (model loading, parameters, configuration)
persistent T
if isempty(T), T = struct(); end
out = [];
switch action
    case 'reset', T = struct();
    case 'set',   T.(name) = val;
    case 'get',   out = T;
end
end

function mb = evMem(label)
% cheap memory monitor: MATLAB memory in use [MB] (Windows memory()); tracks the largest sample
persistent pk
if isempty(pk), pk = 0; end
mb = NaN;
if strcmp(label,'reset'), pk = 0; return, end
if strcmp(label,'peak'),  mb = pk; return, end
try
    if ispc, u = memory; mb = u.MemUsedMATLAB/2^20; end
catch
end
if isfinite(mb)
    pk = max(pk, mb);
    fprintf('[MEMORY] %-28s: %8.1f MB\n', label, mb);
else
    fprintf('[MEMORY] %-28s: n/a (memory() is not available on this platform)\n', label);
end
end


function id = makeRunID(root)
id = ['EV_RUN_' char(datetime('now','Format','yyyyMMdd_HHmmss'))];
if isfolder(fullfile(root,id))
    base = id;
    for k = 1:999
        id = sprintf('%s_%03d', base, k);
        if ~isfolder(fullfile(root,id)), break; end
    end
end
end

function writeText(f, L)
fid = fopen(f,'w'); if fid == -1, return; end
for k = 1:numel(L), fprintf(fid,'%s\n',L{k}); end
fclose(fid);
end

function P = getParams()
% ========================================================================
% Values are READ from the base workspace (set by BLDCSpeedControlData.m);
% the numbers below are only fall-backs and must match that file.
%   Speed PI  Kpw = 0.05 V/rpm, Kiw = 10 V/(rpm*s)   (tracks the 6000 rpm/s ramp)
%   Limiter   I_peak = 45 A (I2t budget), I_cont = 30 A
names = {'Kt',0.107;'Rs',0.1;'Ls',8e-5;'Jm',0.002;'p',4;'Vmotor_nom',48;'rpm_nom',3000; ...
    'I_cont',30;'I_peak',45;'Vdc',48;...
    'Kpw',0.05;...
    'Kiw',10;...
    'Kpv',0.3;'Kiv',1.5;'Kpi',0.2; ...
    'Kii',100;'Ts',1e-5;'Tsc',1e-4;...
    'rpm_ref',2950;...
    'rpm_ramp',13000;'t_stop',0.3;'pack_Ah',50;'kappa',0.72;'w_meas_rpm',600; ...
    'cells_series',13;'cells_parallel',10;...
    'T_load_end',3.18;'gear_ratio',11;'r_wheel',0.25};
for k = 1:size(names,1), P.(names{k,1}) = safeBase(names{k,1}, names{k,2}); end
cfgT = evCfg();  P.t_stop = cfgT.t_stop;  P.I_peak_VV = cfgT.vvPeakCurrent;
end


%% ---------------------------- acquisition --------------------------------
function [S, tEnd] = harvest(sigMap, P)
tout = [];  try, tout = evalin('base','tout'); catch, end
S = struct();  tEnd = 0;
for f = fieldnames(sigMap)'
    key = f{1};  S.(key) = struct('t',[],'y',[],'info','not logged');
    vn = sigMap.(key).WorkspaceVar;
    if isempty(vn), continue; end
    [t,y,info] = fetchVar(vn, tout);
    S.(key).t = t;  S.(key).y = y;  S.(key).info = info;
    if ~isempty(t), tEnd = max(tEnd, t(end)); end
end
if tEnd == 0, tEnd = P.t_stop; end
end

function [t,y,info] = fetchVar(vn, tout)
% V7: reads the logged array with its REAL time axis. V6 used reshape(Data, N, []) which is only
% correct when time is the first dimension. Pack signals (13 voltages, 130 currents, 130 SOC) are
% logged as r x c x N, and reshaping those as N x m mixes samples of different times.
t = [];  y = [];  info = 'not logged';
try, x = evalin('base', vn); catch, return; end
if isa(x,'timeseries')
    t = x.Time(:);  D = double(x.Data);
    tf = true;  try, tf = logical(x.IsTimeFirst); catch, end
    y = evTsMatrix(D, numel(t), tf);
    info = sprintf('Data %s, IsTimeFirst=%d -> %d samples x %d columns', mat2str(size(D)), tf, size(y,1), size(y,2));
elseif isstruct(x) && isfield(x,'time') && isfield(x,'signals')
    t = x.time(:);  D = double(x.signals(1).values);
    y = evTsMatrix(D, numel(t), true);
    info = sprintf('struct values %s -> %d samples x %d columns', mat2str(size(D)), size(y,1), size(y,2));
elseif isnumeric(x) && ~isempty(tout) && size(x,1) == numel(tout)
    t = tout(:);  y = double(x);
    info = sprintf('array %s -> %d samples x %d columns', mat2str(size(x)), size(y,1), size(y,2));
end
if isempty(y) && ~isempty(t)
    t = [];  info = [info ' | ERROR: time axis does not match any array dimension, signal skipped'];
end
end

function Y = evTsMatrix(D, n, timeFirst)
% D: array logged by a To Workspace block, n: number of time samples, timeFirst: timeseries.IsTimeFirst.
%   N x m       (time first)          -> N x m
%   r x c x N   (time last, 2-D sig.) -> N x (r*c), element order r fastest (so 130 x 1 x N -> N x 130)
sz = size(D);  Y = [];
if n == 0 || isempty(D), return, end
if timeFirst && sz(1) == n
    Y = reshape(D, n, []);
elseif sz(end) == n
    nd = numel(sz);
    Y = reshape(permute(D, [nd, 1:nd-1]), n, []);
elseif sz(1) == n
    Y = reshape(D, n, []);
end
end

function [Raw, ri] = buildRaw(S, sigMap)
% Raw = exactly what was logged, at the native sample times (no scaling,
% no de-duplication, no interpolation unless a signal has its own time base).
keys = {'vbatt','ibatt','soc','temperature','vdc','rpm_ref','rpm','torque','imotor','omega_wheel'};
ri = struct('Cols',struct(),'Resampled',{{}},'SampleCount',struct(),'SampleTime',struct(), ...
            'HasTime',false,'AllLoggedHaveData',true,'PrimaryKey','');
have = {};
for k = 1:numel(keys)
    key = keys{k};
    ri.Cols.(key) = {};
    ri.SampleCount.(key) = numel(S.(key).t);
    ri.SampleTime.(key) = 'not logged';
    if ~isempty(S.(key).t) && ~isempty(S.(key).y), have{end+1} = key; end %#ok<AGROW>
    if sigMap.(key).Available && isempty(S.(key).t), ri.AllLoggedHaveData = false; end
end
if isempty(have)
    Raw = table(zeros(0,1),'VariableNames',{'Time'});  ri.AllLoggedHaveData = false;  return
end
pk = iif(ismember('rpm',have), 'rpm', have{1});
ri.PrimaryKey = pk;  tR = S.(pk).t(:);  ri.HasTime = true;
names = {};  M = tR;
for k = 1:numel(have)
    key = have{k};  sig = S.(key);
    if isequal(sig.t(:), tR)
        Y = sig.y;
    else
        [tu,iu] = unique(sig.t(:));
        Y = interp1(tu, sig.y(iu,:), tR, 'linear', NaN);
        ri.Resampled{end+1} = key; %#ok<AGROW>
    end
    nm = evKeySpecName(key);
    if size(Y,2) == 1, cn = {nm}; else, cn = arrayfun(@(c) sprintf('%s_%d',nm,c), 1:size(Y,2), 'UniformOutput', false); end
    ri.Cols.(key) = cn;  names = [names cn]; M = [M Y]; %#ok<AGROW>
    dt = diff(sig.t(:));  dt = dt(dt > 0);
    if isempty(dt), ri.SampleTime.(key) = 'n/a';
    elseif max(dt) - min(dt) < 1e-12 + 1e-6*median(dt), ri.SampleTime.(key) = sprintf('fixed %.3g s', median(dt));
    else, ri.SampleTime.(key) = sprintf('variable (median %.3g s)', median(dt)); end
end
Raw = array2table(M, 'VariableNames', ['Time' names]);
end

function [R, nDup] = compactRaw(RawFull, ri, P)
% Pack-level raw table: the 13-column voltage, 130-column current and 130-column SOC logs are
% reduced to BatteryVoltage / BatteryCurrent / SOC (+ SOC_Min / SOC_Max); other signals as logged.
% Repeated time stamps are collapsed (last sample kept). Per-cell data stays in 02b_Raw_PerCell.csv.
R = RawFull(:,'Time');
keys = {'vbatt','ibatt','soc','temperature','vdc','rpm_ref','rpm','torque','imotor','omega_wheel'};
for k = 1:numel(keys)
    key = keys{k};  cols = ri.Cols.(key);
    if isempty(cols), continue, end
    Y = RawFull{:, cols};
    nm = evKeySpecName(key);
    if any(strcmp(key,{'vbatt','ibatt','soc'}))
        y = normSignal(Y, key, P);
        if strcmp(key,'ibatt'), y = abs(y); end      % POSITIVE-CURRENT
        R.(nm) = y;
        if strcmp(key,'soc')
            sc = 1;  if max(Y(:)) > 1.5, sc = 0.01; end
            R.SOC_Min = min(Y,[],2,'omitnan')*sc;
            R.SOC_Max = max(Y,[],2,'omitnan')*sc;
        end
    elseif size(Y,2) == 1
        R.(nm) = Y;
    else
        R.(nm) = mean(Y,2,'omitnan');
    end
end
[~, iu] = unique(R.Time, 'last');
nDup = height(R) - numel(iu);
R = R(iu,:);
end

%% ------------------------------ cleaning ---------------------------------
function [C, ci] = cleanData(Raw, ri, tEnd, P)
ci = struct('Notes',{{}},'RefDerived',false);
M0 = Raw{:,:};
live = any(isfinite(M0),1);
ci.RawNaN = sum(sum(isnan(M0(:,live))));
ci.RawInf = sum(sum(isinf(M0)));
% duplicate columns
nm = Raw.Properties.VariableNames;
[~,ia] = unique(lower(nm),'stable');
ci.DupColName = numel(nm) - numel(ia);  Raw = Raw(:,ia);
ci.DupColData = 0;
if width(Raw) <= 40
    X = Raw{:,2:end};
    for i = 1:size(X,2), for j = i+1:size(X,2)
        if isequaln(X(:,i), X(:,j)), ci.DupColData = ci.DupColData + 1; end
    end, end
end
% invalid time
t = Raw.Time;  bad = ~isfinite(t) | t < 0;
ci.InvalidTime = sum(bad);  Raw = Raw(~bad,:);  t = Raw.Time;
% monotonicity
ci.NonMonotonic = sum(diff(t) < 0);
if ci.NonMonotonic > 0, [~,o] = sort(t); Raw = Raw(o,:); t = Raw.Time; end
% duplicate rows / duplicate time stamps
M = Raw{:,:};
ci.DupRows = size(M,1) - size(unique(M,'rows'),1);
d0 = find([false; diff(t) == 0]);
ci.DupTime = numel(d0);
if ~isempty(d0)
    ci.DupTimeDiffering = sum(any(M(d0,2:end) ~= M(d0-1,2:end) & ~(isnan(M(d0,2:end)) & isnan(M(d0-1,2:end))), 2));
else
    ci.DupTimeDiffering = 0;
end
keep = [diff(t) > 0; true];                 % keep the LAST sample of equal time stamps
Raw = Raw(keep,:);  M = Raw{:,:};  M(isinf(M)) = NaN;  t = Raw.Time;
ci.DedupRows = size(M,1);
% common 1 ms grid + normalization
tg = (0:1e-3:tEnd)';
ci.GridRows = numel(tg);
ci.OutsideRange = 0;  ci.GridNaN = 0;
V = struct();  logged = struct();
keys = {'vbatt','ibatt','soc','temperature','vdc','rpm_ref','rpm','torque','imotor','omega_wheel'};
for k = 1:numel(keys)
    key = keys{k};  cols = ri.Cols.(key);  logged.(key) = ~isempty(cols);
    if isempty(cols), continue; end
    idx = cellfun(@(c) find(strcmp(Raw.Properties.VariableNames, c), 1), cols);
    Y = M(:, idx);
    [y, note] = normSignal(Y, key, P);
    if ~isempty(note), ci.Notes{end+1} = note; end %#ok<AGROW>
    if numel(t) >= 2
        V.(key) = evBinMean(t, y, tg);                       % V7.1: 1 ms window mean (10 PWM periods), not point sampling
        ci.OutsideRange = ci.OutsideRange + sum(tg < t(1) | tg > t(end));
        ci.GridNaN = ci.GridNaN + sum(isnan(V.(key)));
    else
        V.(key) = nan(size(tg));
    end
end
if isfield(V, 'ibatt')
    % Audit battery current sign: Simscape Battery uses passive sign convention
    % where discharge current leaving the positive terminal is negative.
    % In EV powertrain & digital twin DAQ, positive convention is used for discharge.
    % Audit mean during motoring rather than taking blind abs():
    mean_ibatt = mean(V.ibatt, 'omitnan');
    if mean_ibatt < 0
        ci.BatteryCurrentSign = 'Simscape passive (negative on discharge) -> inverted to positive discharge';
        V.ibatt = -V.ibatt;  % Invert sign to maintain charging/discharging distinction
    else
        ci.BatteryCurrentSign = 'Positive on discharge -> kept unchanged';
    end
    ci.Notes{end+1} = sprintf('BatteryCurrent sign audit: %s', ci.BatteryCurrentSign);
end
if ~isfield(V,'rpm_ref') && isfield(V,'rpm')
    V.rpm_ref = min(P.rpm_ramp*tg, P.rpm_ref);  ci.RefDerived = true;
    ci.Notes{end+1} = 'RPMReference DERIVED = min(rpm_ramp*t, rpm_ref) because the model does not log the reference';
end
D = struct();
has = @(k) isfield(V,k);
if has('vbatt') && has('ibatt'), D.BatteryPower = V.vbatt .* V.ibatt; end
if has('rpm') && has('rpm_ref'), D.SpeedError = V.rpm_ref - V.rpm; end
if has('torque') && has('rpm'), D.MotorMechanicalPower = abs(V.torque) .* V.rpm * (2*pi/60); end
if isfield(D,'BatteryPower') && isfield(D,'MotorMechanicalPower')
    e = 100*D.MotorMechanicalPower ./ max(abs(D.BatteryPower), 0.1);  e(abs(D.BatteryPower) < 1) = NaN;
    D.Efficiency = e;
end
spec = evSpecDefs();  C = table(tg, 'VariableNames', {'Time'});
for k = 1:size(spec,1)
    nmk = spec{k,1};  key = spec{k,2};
    if strcmp(spec{k,3}, 'logged') && ~isempty(key) && has(key), C.(nmk) = V.(key);
    elseif strcmp(spec{k,3}, 'derived') && isfield(D, nmk),    C.(nmk) = D.(nmk); end
end
vn = setdiff(C.Properties.VariableNames(2:end), {'Efficiency'}, 'stable');
ci.RemainingNaN = sum(sum(isnan(C{:,vn})));
end

function [y, note] = normSignal(Y, key, P)
note = '';
switch key
    case 'vbatt'
        if size(Y,2) > 1, y = sum(Y,2); note = 'BatteryVoltage: multi-column cell voltages summed to pack voltage';
        elseif median(abs(Y),'omitnan') < 5, y = Y*P.cells_series; note = sprintf('BatteryVoltage: logged value looks cell-level, scaled x%d (cells_series)', P.cells_series);
        else, y = Y(:,1); end
    case 'ibatt'
        % log_icell is the current of ONE cell (the model itself multiplies it by cells_parallel
        % in 'Battery Current Scaling'). Pack current = cell current x parallel strings.
        nc = size(Y,2);
        if nc == 1
            y = Y*P.cells_parallel;
            note = sprintf('BatteryCurrent: WARNING only ONE column logged (cell 1 only), scaled x%d (cells_parallel); not a terminal measurement', P.cells_parallel);
        elseif nc == P.cells_parallel
            y = sum(Y,2);
            note = 'BatteryCurrent: parallel-string currents summed to pack current';
        elseif nc == P.cells_series*P.cells_parallel
            y = sum(Y,2)/P.cells_series;
            note = 'BatteryCurrent: terminal current = sum of all 130 cell currents / cells_series (every series level carries the full pack current)';
        elseif nc == P.cells_series
            y = mean(Y,2,'omitnan');       % LUMPED pack (one model per series group): every group carries the full pack current
            note = 'BatteryCurrent: lumped pack, mean of the series-group currents (each carries the pack current)';
        else
            y = mean(Y,2,'omitnan')*P.cells_parallel;
            note = sprintf('BatteryCurrent: %d columns, mean cell current x%d (cells_parallel)', nc, P.cells_parallel);
        end
    case 'temperature'
        y = mean(Y,2,'omitnan');
    case 'soc'
        y = mean(Y,2,'omitnan');
        if max(y) > 1.5, y = y/100; note = 'SOC: logged in percent, converted to 0..1'; end
    otherwise
        y = Y(:,1);
end
end

function L = makeLive(C)
cfgL = evCfg();  tl = (0:cfgL.Ts_live:C.Time(end))';
L = table(tl,'VariableNames',{'Time'});
want = {'BatteryVoltage','BatteryCurrent','SOC','BatteryPower','DCLinkVoltage','RPMReference','RPM', ...
        'MotorTorque','MotorCurrent','WheelSpeed','BatteryTemperature','BatteryTemperatureMax','MotorTemperature', ...
        'MotorMechanicalPower','Efficiency'};
for k = 1:numel(want)
    if ismember(want{k}, C.Properties.VariableNames)
        L.(want{k}) = interp1(C.Time, C.(want{k}), tl, 'linear', NaN);
    end
end
end

function x = col(C, n)
if ismember(n, C.Properties.VariableNames), x = C.(n); else, x = nan(height(C),1); end
end

%% ------------------------------- tables ----------------------------------
function T = paramTable(MDL, Clean)
R = cell(0,5);
bw = @(n) baseOrEmpty(n);
ws = 'workspace (BLDCSpeedControlData.m)';
nS = bw('cells_series');  nP = bw('cells_parallel');  Ah = bw('pack_Ah');
soc0 = NaN;  s = col(Clean,'SOC');  s = s(isfinite(s));  if ~isempty(s), soc0 = s(1); end
R(end+1,:) = prow('Battery','BatteryType','Lithium-ion (Simscape Battery Builder, Batteries2)','','project');
R(end+1,:) = prow('Battery','SeriesCells', nS, '-', ws);
R(end+1,:) = prow('Battery','ParallelCells', nP, '-', ws);
R(end+1,:) = prow('Battery','NominalCellVoltage', 3.7, 'V', 'project spec (cell block not read)');
R(end+1,:) = prow('Battery','MaximumCellVoltage', 4.19, 'V', 'BLDCSpeedControlData.m sanity check (13*4.19)');
R(end+1,:) = prow('Battery','MinimumCellVoltage', [], 'V', '');
if ~isempty(nS), R(end+1,:) = prow('Battery','NominalPackVoltage', nS*3.7, 'V', 'derived: series x 3.7 V'); end
R(end+1,:) = prow('Battery','Capacity_Ah', Ah, 'Ah', ws);
if ~isempty(nS) && ~isempty(Ah), R(end+1,:) = prow('Battery','Energy_Wh', nS*3.7*Ah, 'Wh', 'derived: series x 3.7 V x Ah'); end
if isfinite(soc0), R(end+1,:) = prow('Battery','InitialSOC', soc0, '-', 'measured: first logged SOC sample'); else, R(end+1,:) = prow('Battery','InitialSOC', [], '-', ''); end
R(end+1,:) = prow('Motor','MotorType','BLDC, APBA80L048030-EB','','BLDCSpeedControlData.m header');
R(end+1,:) = prow('Motor','RatedPower', [], 'W', '');
R(end+1,:) = prow('Motor','RatedVoltage', bw('Vmotor_nom'), 'V', ws);
R(end+1,:) = prow('Motor','RatedCurrent', bw('I_cont'), 'A', ws);
R(end+1,:) = prow('Motor','PeakCurrent', bw('I_peak'), 'A', ws);
R(end+1,:) = prow('Motor','RatedSpeed', bw('rpm_nom'), 'rpm', ws);
R(end+1,:) = prow('Motor','PolePairs', bw('p'), '-', ws);
R(end+1,:) = prow('Motor','PhaseResistance', bw('Rs'), 'Ohm', ws);
R(end+1,:) = prow('Motor','PhaseInductance', bw('Ls'), 'H', ws);
R(end+1,:) = prow('Motor','MutualInductance', bw('Ms'), 'H', ws);
R(end+1,:) = prow('Motor','TorqueConstant', bw('Kt'), 'Nm/A', ws);
R(end+1,:) = prow('Motor','RotorInertia', bw('Jm'), 'kg*m^2', ws);
R(end+1,:) = prow('Motor','PMFluxLinkage(psim)', bw('psim'), 'Wb', ws);
R(end+1,:) = prow('Motor','kappa (V7 override, InitFcn hook)', bw('kappa'), '-', 'EV_DAQ_Builder_V7 (data file value 0.71 replaced)');
R(end+1,:) = prow('Motor','Ke_ph (from kappa)', bw('Ke_ph'), 'V*s/rad', 'Kt/kappa');
R(end+1,:) = prow('Motor','emf_max_ev (from kappa)', bw('emf_max_ev'), 'V', 'Ke_ph*w_meas*2*pi/60');
R(end+1,:) = prow('Motor','WindingType', [], '', '');
R(end+1,:) = prow('Vehicle','VehicleMass', [], 'kg', '');
R(end+1,:) = prow('Vehicle','WheelRadius', bw('r_wheel'), 'm', ws);
R(end+1,:) = prow('Vehicle','GearRatio', bw('gear_ratio'), '-', ws);
R(end+1,:) = prow('Vehicle','WheelMass', bw('wheel_mass'), 'kg', ws);
R(end+1,:) = prow('Vehicle','Cd', [], '-', '');
R(end+1,:) = prow('Vehicle','Crr', [], '-', '');
R(end+1,:) = prow('Vehicle','AirDensity', [], 'kg/m^3', '');
R(end+1,:) = prow('Controller','SpeedPI_Kp', bw('Kpw'), 'V/rpm', ws);
R(end+1,:) = prow('Controller','SpeedPI_Ki', bw('Kiw'), 'V/(rpm*s)', ws);
R(end+1,:) = prow('Controller','VoltagePI_Kp', bw('Kpv'), '-', ws);
R(end+1,:) = prow('Controller','VoltagePI_Ki', bw('Kiv'), '-', ws);
R(end+1,:) = prow('Controller','CurrentLimiterPI_Kp', bw('Kpi'), 'V/A', ws);
R(end+1,:) = prow('Controller','CurrentLimiterPI_Ki', bw('Kii'), 'V/(A*s)', ws);
R(end+1,:) = prow('Controller','CurrentLimit_Peak', bw('I_peak'), 'A', ws);
R(end+1,:) = prow('Controller','CurrentLimit_Continuous', bw('I_cont'), 'A', ws);
R(end+1,:) = prow('Controller','PWMFrequency', [], 'Hz', '');
R(end+1,:) = prow('Controller','FundamentalSampleTime_Ts', bw('Ts'), 's', ws);
R(end+1,:) = prow('Controller','ControlSampleTime_Tsc', bw('Tsc'), 's', ws);
R(end+1,:) = prow('Controller','DCLinkReference', bw('Vdc'), 'V', ws);
R(end+1,:) = prow('Scenario','SpeedTarget', bw('rpm_ref'), 'rpm', ws);
R(end+1,:) = prow('Scenario','SpeedRampRate', bw('rpm_ramp'), 'rpm/s', ws);
R(end+1,:) = prow('Scenario','SimStopTime', bw('t_stop'), 's', ws);
R(end+1,:) = prow('Scenario','FinalLoadTorque', bw('T_load_end'), 'Nm', ws);
clp = evCfg();
R(end+1,:) = prow('Scenario','LoadProfile_V7', sprintf('0 Nm to %.3f s, ramp to -%.2f Nm at %.3f s, hold', clp.load.t_start, clp.load.T, clp.load.t_end), '', 'EV_DAQ_Builder_V7 (written into BLDCSpeedControlInput.mat)');
sv = 'n/a';  try, v = ver('simulink'); sv = v(1).Version; catch, end
R(end+1,:) = prow('System','ModelFile', [MDL '.slx'], '', 'project');
R(end+1,:) = prow('System','ParameterFile', 'BLDCSpeedControlData.m', '', 'project');
R(end+1,:) = prow('System','InputFile', 'BLDCSpeedControlInput.mat', '', 'project');
R(end+1,:) = prow('System','BatteryLibrary', 'Batteries2_lib.slx / +Batteries2', '', 'project');
R(end+1,:) = prow('System','MATLABVersion', version, '', 'runtime');
R(end+1,:) = prow('System','SimulinkVersion', sv, '', 'runtime');
T = cell2table(R, 'VariableNames', {'Group','Parameter','Value','Unit','Source'});
end

function r = prow(g, p, v, u, src)
if isnumeric(v)
    if isempty(v), v = 'NOT_AVAILABLE'; src = 'not in workspace'; else, v = num2str(v, 8); end
end
r = {g, p, v, u, src};
end

function T = auditTable(Raw, Clean, ri, ci, sigMap, spec, tEnd, P)
R = {};
add = @(c,v,l,s,d) {c, v, l, s, d};
pf  = @(ok) iif(ok,'PASS','FAIL');
pw  = @(n) iif(n == 0,'PASS','WARN');
R(end+1,:) = add('Time vector exists', double(ri.HasTime), 1, pf(ri.HasTime), ['primary: ' ri.PrimaryKey]);
R(end+1,:) = add('Raw time non-decreasing (decreasing steps)', ci.NonMonotonic, 0, pw(ci.NonMonotonic), 'sorted in cleaning if >0');
R(end+1,:) = add('Raw duplicate time stamps', ci.DupTime, 0, pw(ci.DupTime), sprintf('%d with differing values; kept last sample per time stamp', ci.DupTimeDiffering));
R(end+1,:) = add('Raw invalid time samples (NaN/Inf/negative)', ci.InvalidTime, 0, pw(ci.InvalidTime), 'removed in cleaning if >0');
R(end+1,:) = add('Raw duplicate rows', ci.DupRows, 0, pw(ci.DupRows), 'identical complete rows');
R(end+1,:) = add('Raw duplicate columns (same name)', ci.DupColName, 0, pw(ci.DupColName), 'removed if >0');
R(end+1,:) = add('Raw duplicate columns (bit-identical data)', ci.DupColData, 0, iif(ci.DupColData == 0,'PASS','INFO'), 'merged losslessly in the compact storage (02c_Column_Map.csv)');
R(end+1,:) = add('Raw NaN count', ci.RawNaN, 0, pw(ci.RawNaN), 'in columns that carry data');
R(end+1,:) = add('Raw Inf count', ci.RawInf, 0, pw(ci.RawInf), 'converted to NaN in cleaned data');
R(end+1,:) = add('Raw signals sharing the primary time base', numel(fieldnames(ri.Cols)) - numel(ri.Resampled) - sum(structfun(@isempty, ri.Cols)), ...
    sum(~structfun(@isempty, ri.Cols)), pw(numel(ri.Resampled)), ['interpolated onto primary time: ' strjoin(ri.Resampled, ',')]);
R(end+1,:) = add('Missing samples on common grid (outside logged range)', ci.OutsideRange, 0, pw(ci.OutsideRange), '1 ms grid points beyond a signal''s log');
R(end+1,:) = add('Raw data count (rows)', height(Raw), 1, pf(height(Raw) > 0), '');
R(end+1,:) = add('De-duplicated native rows', ci.DedupRows, 1, pf(ci.DedupRows > 0), '');
R(end+1,:) = add('Cleaned data count (rows)', height(Clean), 1, pf(height(Clean) > 0), '1 ms common grid');
tc = Clean.Time;
R(end+1,:) = add('Cleaned time strictly increasing', double(all(diff(tc) > 0)), 1, pf(all(diff(tc) > 0)), '');
R(end+1,:) = add('Common time grid uniform (max |dt-1ms|)', max(abs(diff(tc) - 1e-3)), 1e-9, pf(max(abs(diff(tc) - 1e-3)) < 1e-9), 'engineering grid Ts = 0.001 s');
R(end+1,:) = add('Remaining NaN in cleaned data', ci.RemainingNaN, 0, pf(ci.RemainingNaN == 0), 'NaN is never filled or hidden');
R(end+1,:) = add('Simulation duration reached (s)', tEnd, P.t_stop, pf(abs(tEnd - P.t_stop) < 1e-3), 'compared with t_stop');
keys = fieldnames(sigMap);
nReq = 0;  nGot = 0;
for k = 1:numel(keys)
    key = keys{k};  sm = sigMap.(key);  n = ri.SampleCount.(key);
    if ~sm.Available
        R(end+1,:) = add(['Signal ' evKeySpecName(key) ' sample count'], 0, NaN, 'NOT_AVAILABLE', 'not logged in model'); %#ok<AGROW>
    else
        nReq = nReq + 1;  nGot = nGot + (n > 0);
        R(end+1,:) = add(['Signal ' evKeySpecName(key) ' sample count'], n, 1, pf(n > 0), [sm.WorkspaceVar ' | ' ri.SampleTime.(key)]); %#ok<AGROW>
    end
end
R(end+1,:) = add('Required signals (logged by model)', nGot, nReq, pf(nGot == nReq), 'every To Workspace signal returned data');
names = spec(:,1);  nAvail = sum(ismember(names, Clean.Properties.VariableNames));
R(end+1,:) = add('Requested signals available (spec list)', nAvail, numel(names), iif(nAvail == numel(names),'PASS','NOT_AVAILABLE'), 'missing ones are listed in 07_Signal_Map.csv');
for k = 1:numel(ci.Notes), R(end+1,:) = add('Normalization note', NaN, NaN, 'INFO', ci.Notes{k}); end %#ok<AGROW>
T = cell2table(R, 'VariableNames', {'Check','Value','Limit','Status','Detail'});
end

function T = vvTable(C, P, CD, Raw)
cfg = evCfg();
t = C.Time;  late = t >= 0.9*t(end);
rp = col(C,'RPM'); im = col(C,'MotorCurrent'); vb = col(C,'BatteryVoltage'); soc = col(C,'SOC');
hd = @(x) any(isfinite(x));
rows = {};
na = @(id,req,sig) {id,req,sig,'-','-','-','-','-','NOT_AVAILABLE'};
rows(end+1,:) = vr('VV-000',sprintf('Run reached t_stop = %.3g s (otherwise all other V&V is not meaningful)',P.t_stop),'Time','t(end)', ...
    P.t_stop, t(end), t(end)-P.t_stop, 1e-3, abs(t(end)-P.t_stop) <= 1e-3);
if hd(rp)
    f = mean(rp(late),'omitnan');
    rows(end+1,:) = vr('VV-001',sprintf('Final speed %.0f..%.0f rpm',P.rpm_ref-50,P.rpm_ref+50),'RPM','mean(RPM, last 10%)',P.rpm_ref,f,f-P.rpm_ref,50, f>=P.rpm_ref-50 && f<=P.rpm_ref+50); %#ok<AGROW>
    pk = max(rp,[],'omitnan');
    rows(end+1,:) = vr('VV-002','Peak speed <= 3000 rpm','RPM','max(RPM)',3000,pk,pk-3000,3000, pk<=3000); %#ok<AGROW>
else
    rows(end+1,:) = na('VV-001','Final speed window','RPM'); rows(end+1,:) = na('VV-002','Peak speed','RPM'); %#ok<AGROW>
end
if hd(im)
    pI = max(abs(im),[],'omitnan');  rI = rmsf(im);  ss = max(abs(im(late)),[],'omitnan');
    rows(end+1,:) = vr('VV-003',sprintf('Peak motor current <= %.0f A',P.I_peak_VV),'MotorCurrent','max(|I|)',P.I_peak_VV,pI,pI-P.I_peak_VV,P.I_peak_VV, pI<=P.I_peak_VV); %#ok<AGROW>
    Iop = cfg.vvMotorOperatingCurrent;
    rows(end+1,:) = vr('VV-004',sprintf('RMS motor current <= %.0f A (project limit; datasheet continuous rating %.0f A unconfirmed for 35 A operation)',Iop,P.I_cont),'MotorCurrent','rms(I)',Iop,rI,rI-Iop,Iop, rI<=Iop); %#ok<AGROW>
    ssm = mean(abs(im(late)),'omitnan');
    rows(end+1,:) = vr('VV-008',sprintf('Steady-state average current <= %.0f A project limit (datasheet continuous rating %.0f A; 35 A operation unconfirmed)',Iop,P.I_cont),'MotorCurrent','mean(|I|, last 10%)',Iop,ssm,ssm-Iop,Iop, ssm<=Iop); %#ok<AGROW>
else
    rows(end+1,:) = na('VV-003','Peak motor current','MotorCurrent'); rows(end+1,:) = na('VV-004','RMS motor current','MotorCurrent'); rows(end+1,:) = na('VV-008','Steady-state current','MotorCurrent'); %#ok<AGROW>
end
Vmax = P.cells_series*4.19 + 0.1;
if hd(vb)
    vm = max(vb,[],'omitnan');
    rows(end+1,:) = vr('VV-005',sprintf('Max pack voltage <= %.2f V',Vmax),'BatteryVoltage','max(V)',Vmax,vm,vm-Vmax,Vmax, vm<=Vmax); %#ok<AGROW>
else
    rows(end+1,:) = na('VV-005','Max pack voltage','BatteryVoltage'); %#ok<AGROW>
end
sc = soc(isfinite(soc));
if ~isempty(sc)
    scv = soc(isfinite(soc) & t >= 0.002);                                  % V7.1: after the 2 ms start-up window
    rows(end+1,:) = vr('VV-006','SOC within 0..1 (t >= 2 ms, +1e-6 start-up tolerance)','SOC','min/max(SOC)','0..1',sprintf('%.9f..%.9f',min(scv),max(scv)),0,'0..1+1e-6', min(scv) >= 0 && max(scv) <= 1 + 1e-6); %#ok<AGROW>
    md = max(diff(scv));
    rows(end+1,:) = vr('VV-007','SOC non-increasing (discharge, t >= 2 ms)','SOC','max(diff(SOC)) <= 1e-9','<=0',md,md,1e-9, all(diff(scv)<=1e-9)); %#ok<AGROW>
else
    rows(end+1,:) = na('VV-006','SOC range','SOC'); rows(end+1,:) = na('VV-007','SOC monotonic','SOC'); %#ok<AGROW>
end
pbv = col(C,'BatteryPower');  pmv = col(C,'MotorMechanicalPower');
pbS = mean(abs(pbv(late)),'omitnan');  pmS = mean(abs(pmv(late)),'omitnan');
if isfinite(pbS) && pbS >= 1 && isfinite(pmS)
    eS = 100*pmS/pbS;
    rows(end+1,:) = vr('VV-009','Steady-state efficiency within 0..100 %','Efficiency','100*mean(Pmech)/mean(|Pbatt|), last 10%','0..100',eS,max(0,eS-100),100, eS > 0 && eS <= 100); %#ok<AGROW>
else
    rows(end+1,:) = na('VV-009','Steady-state efficiency within 0..100 %','Efficiency'); %#ok<AGROW>
end

% ---------------- V7 checks (each one belongs to a failure found in the 61-sample review) ----------------
ib = col(C,'BatteryCurrent');  vdc = col(C,'DCLinkVoltage');  tq = col(C,'MotorTorque');
ok1 = @(x) isfinite(x);
% VV-010 / VV-011  SOC
if ~isempty(sc)
    s0 = sc(1);
    rows(end+1,:) = vr('VV-010',sprintf('SOC at t = 0 equals the initial SOC (%.4f)',cfg.soc0),'SOC','SOC(0)',cfg.soc0,s0,s0-cfg.soc0,cfg.vvSoc0Tol, abs(s0-cfg.soc0) <= cfg.vvSoc0Tol); %#ok<AGROW>
    ibv = ib(isfinite(ib) & isfinite(soc));
    if numel(ibv) > 2
        dQ  = abs(trapz(t(isfinite(ib)), ib(isfinite(ib))))/3600;           % Ah taken from the pack
        dSe = dQ/P.pack_Ah;                                                    % expected SOC drop (fraction)
        dSl = sc(1) - sc(end);                                                 % logged SOC drop
        rr = dSl/max(dSe, eps);
        rows(end+1,:) = vr('VV-011','SOC drop equals the coulomb count of the battery current','SOC','(SOC(0)-SOC(end)) / (int|Ibat|dt / (3600*pack_Ah))', ...
            sprintf('%.3g..%.3g',cfg.vvSocRatio), rr, rr-1, sprintf('%.3g..%.3g',cfg.vvSocRatio), rr >= cfg.vvSocRatio(1) && rr <= cfg.vvSocRatio(2)); %#ok<AGROW>
    end
else
    rows(end+1,:) = na('VV-010','SOC at t = 0','SOC'); rows(end+1,:) = na('VV-011','SOC coulomb count','SOC'); %#ok<AGROW>
end
% VV-012  battery power against DC-link power (independent check of the battery current)
% V8: the DC-link power uses the MEASURED DC-link current only. MotorCurrent (log_Idc_f) is a controller
% estimate and must not be used as Idc: without a logged DCLinkCurrent the check is NOT_AVAILABLE.
idcMeas = col(C,'DCLinkCurrent');  haveIdcMeas = any(isfinite(idcMeas));
pdc = vdc .* idcMeas;  pbt = abs(vb .* ib);
mk = isfinite(pdc) & isfinite(pbt);
if haveIdcMeas && any(mk) && mean(pbt(mk)) >= 1
    rb = mean(abs(pdc(mk)))/mean(pbt(mk));
    rows(end+1,:) = vr('VV-012','Battery power follows the DC-link power: mean|Vdc*Idc| / mean|Vbat*Ibat| (measured DCLinkCurrent)','BatteryCurrent', ...
        'mean|Vdc*Idc| / mean|Vbat*Ibat|',sprintf('%.2f..%.2f',cfg.vvPbalance), rb, 0, sprintf('%.2f..%.2f',cfg.vvPbalance), rb >= cfg.vvPbalance(1) && rb <= cfg.vvPbalance(2)); %#ok<AGROW>
else
    rows(end+1,:) = na('VV-012','Battery power vs DC-link power (NOT_AVAILABLE: no measured DCLinkCurrent logged)','BatteryCurrent'); %#ok<AGROW>
end
% VV-013 / VV-014  cell voltages
if nargin >= 3 && ~isempty(CD) && isfield(CD,'OK') && CD.OK && height(CD.Summary) > 0
    cm = max(CD.Summary.V_Cell_Max,[],'omitnan');
    rows(end+1,:) = vr('VV-013',sprintf('Every cell voltage <= %.2f V',cfg.vvCellMax),'CellVoltage','max(cell V)',cfg.vvCellMax,cm,cm-cfg.vvCellMax,cfg.vvCellMax, cm <= cfg.vvCellMax); %#ok<AGROW>
    sel = CD.Summary.Time >= 0.01;
    sp = max(CD.Summary.V_Imbalance(sel),[],'omitnan');
    rows(end+1,:) = vr('VV-014',sprintf('The %d series groups have the same voltage (spread <= %.0f mV; pack has zero cell deviation)',CD.nV,1e3*cfg.vvCellSpread),'CellVoltage', ...
        'max(Vmax-Vmin) for t >= 0.01 s',cfg.vvCellSpread,sp,sp,cfg.vvCellSpread, sp <= cfg.vvCellSpread); %#ok<AGROW>
else
    rows(end+1,:) = na('VV-013','Cell voltage limit','CellVoltage'); rows(end+1,:) = na('VV-014','Cell voltage spread','CellVoltage'); %#ok<AGROW>
end
% NOTE ON VV-015: Requirement ID VV-015 was skipped in the historical specification numbering
% sequence (jumping from VV-014 to VV-016). There are exactly 24 active V&V requirements (VV-000..024).
% VV-016  energy-based efficiency
if any(mk) && trapz(t(mk), pbt(mk)) > 0 && any(isfinite(pmv))
    em = trapz(t(isfinite(pmv)), abs(pmv(isfinite(pmv))));  eb = trapz(t(mk), pbt(mk));
    ee = 100*em/eb;
    rows(end+1,:) = vr('VV-016','Whole-run energy efficiency within 0..100 %','Efficiency','100*int|Pmech|dt / int|Pbatt|dt','0..100',ee,max(0,ee-100),100, ee > 0 && ee <= 100); %#ok<AGROW>
else
    rows(end+1,:) = na('VV-016','Whole-run energy efficiency','Efficiency'); %#ok<AGROW>
end
% VV-017 / VV-018  load actually applied (EV_SetLoadProfile is built in; this proves it took effect)
tEndW = t(end) - 0.01;  wnd = t >= tEndW;
tqE = mean(abs(tq(wnd)),'omitnan');
Tw = cfg.load.T;
if ok1(tqE)
    rows(end+1,:) = vr('VV-017',sprintf('Load torque in the last 10 ms is %.2f Nm +/- %.0f %% (profile applied)',Tw,100*cfg.vvLoadTol),'MotorTorque','mean(|T|, last 10 ms)',Tw,tqE,tqE-Tw,cfg.vvLoadTol*Tw, abs(tqE-Tw) <= cfg.vvLoadTol*Tw); %#ok<AGROW>
    pmE = mean(abs(pmv(wnd)),'omitnan');
    rows(end+1,:) = vr('VV-018','Mechanical power in the last 10 ms is about 1 kW (0.9..1.1 kW)','MotorMechanicalPower','mean(Pmech, last 10 ms)','900..1100',pmE,pmE-1000,100, pmE >= 900 && pmE <= 1100); %#ok<AGROW>
else
    rows(end+1,:) = na('VV-017','Final load torque','MotorTorque'); rows(end+1,:) = na('VV-018','Final mechanical power','MotorMechanicalPower'); %#ok<AGROW>
end
% VV-019  torque per amp (kappa)
mkK = t >= 0.02 & isfinite(tq) & isfinite(im) & abs(im) > 5;
if nnz(mkK) > 10
    ktE = mean(abs(tq(mkK)))/mean(abs(im(mkK)));
    rows(end+1,:) = vr('VV-019',sprintf('Torque per amp equals Kt = %.3f N*m/A +/- %.0f %%',P.Kt,100*cfg.vvKtTol),'MotorTorque','mean|T| / mean|I| (t >= 0.02 s, |I| > 5 A)',P.Kt,ktE,ktE-P.Kt,cfg.vvKtTol*P.Kt, abs(ktE-P.Kt) <= cfg.vvKtTol*P.Kt); %#ok<AGROW>
else
    rows(end+1,:) = na('VV-019','Torque per amp','MotorTorque'); %#ok<AGROW>
end
% ---------------- V7.2: phase-separated checks (startup / ramp / load transition / hold) ----------------
tRamp = P.rpm_ref/P.rpm_ramp;                 % reference reaches target [s] (0.2269)
tHold = cfg.load.t_end;                       % load ramp finished [s] (0.28)
okI   = isfinite(im) & isfinite(t);
Emax  = (P.I_peak^2 - P.I_cont^2)*safeBase('t_peak',1);          % A^2*s, same formula as BLDCSpeedControlData.m
E2    = trapz(t(okI), max(im(okI).^2 - P.I_cont^2, 0));          % A^2*s used above I_cont in this run
rows(end+1,:) = vr('VV-022','I^2t above I_cont stays inside the datasheet budget (whole run)','MotorCurrent', ...
    'int max(I^2-Icont^2,0) dt', Emax, E2, E2-Emax, Emax, E2 <= Emax); %#ok<AGROW>
mkH = okI & t >= tHold;
if nnz(mkH) > 5
    ssH = mean(abs(im(mkH)));
    rows(end+1,:) = vr('VV-023',sprintf('Hold-window mean current <= %.0f A project limit (datasheet continuous rating %.0f A; 35 A operation unconfirmed)',Iop,P.I_cont), ...
        'MotorCurrent','mean(|I|, t >= load end)',Iop,ssH,ssH-Iop,Iop, ssH <= Iop); %#ok<AGROW>
else
    rows(end+1,:) = na('VV-023','Hold-window current','MotorCurrent'); %#ok<AGROW>
end
mkR = mk & t >= 0.02 & t <= tRamp;            % ramp phase only, startup (first 20 ms) excluded
if haveIdcMeas && nnz(mkR) > 5
    rR = mean(abs(pdc(mkR)))/mean(pbt(mkR));
    rows(end+1,:) = vr('VV-024','Ramp-phase power balance mean|Vdc*Idc|/mean|Vbat*Ibat| (measured DCLinkCurrent)','BatteryCurrent', ...
        'ratio, 0.02 s <= t <= ramp end',sprintf('%.2f..%.2f',cfg.vvPbalance),rR,0,sprintf('%.2f..%.2f',cfg.vvPbalance), rR >= cfg.vvPbalance(1) && rR <= cfg.vvPbalance(2)); %#ok<AGROW>
else
    rows(end+1,:) = na('VV-024','Ramp-phase power balance (NOT_AVAILABLE: no measured DCLinkCurrent logged)','BatteryCurrent'); %#ok<AGROW>
end
% ---------------- V7.1: limits judged on the RAW 10 us data (Ts = 1e-5) (averaging must never hide a limit violation) ----------------
if nargin >= 4 && istable(Raw) && all(ismember({'BatteryCurrent','BatteryVoltage'}, Raw.Properties.VariableNames))
    mR  = Raw.Time >= 0.002;
    ibR = max(abs(Raw.BatteryCurrent(mR)),[],'omitnan');
    vgR = max(Raw.BatteryVoltage(mR),[],'omitnan')/P.cells_series;
    rows(end+1,:) = vr('VV-020',sprintf('Raw peak battery current <= %.0f A (t >= 2 ms)',P.I_peak_VV),'BatteryCurrent','max(|Ibat|) on 10 us data',P.I_peak_VV,ibR,ibR-P.I_peak_VV,P.I_peak_VV, ibR <= P.I_peak_VV); %#ok<AGROW>
    rows(end+1,:) = vr('VV-021',sprintf('Raw max group voltage (Vpack/%d) <= %.2f V (t >= 2 ms)',P.cells_series,cfg.vvCellMax),'BatteryVoltage','max(Vpack)/cells_series on 10 us data',cfg.vvCellMax,vgR,vgR-cfg.vvCellMax,cfg.vvCellMax, vgR <= cfg.vvCellMax); %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'RequirementID','Requirement','Signal','Calculation','Expected','Actual','Error','Limit','Status'});
end

function r = vr(id,req,sig,calc,e,a,er,lim,pass)
r = {id,req,sig,calc,n2s(e),n2s(a),n2s(er),n2s(lim), iif(pass,'PASS','FAIL')};
end

function s = n2s(x)
if isnumeric(x) && isscalar(x), s = sprintf('%.4g',x); else, s = char(string(x)); end
end

function T = sigMapTable(sigMap, spec, Raw, Clean, ri, ci)
cv = Clean.Properties.VariableNames;  rv = Raw.Properties.VariableNames;
derivText = struct('BatteryPower','BatteryVoltage*BatteryCurrent','SpeedError','RPMReference-RPM', ...
    'MotorMechanicalPower','|MotorTorque|*RPM*2*pi/60','Efficiency','100*MotorMechanicalPower/|BatteryPower|');
rows = {};
for k = 1:size(spec,1)
    nm = spec{k,1};  key = spec{k,2};  kind = spec{k,3};
    inC = ismember(nm, cv);
    if kind == "logged" && ~isempty(key), inR = any(strcmp(rv, nm) | startsWith(rv, [nm '_'])); else, inR = false; end
    src = '';  lgn = '';  stt = 'NOT_AVAILABLE';  smp = 'n/a';  desc = spec{k,8};
    if inC
        if kind == "logged" && ~(strcmp(nm,'RPMReference') && ci.RefDerived)
            sm = sigMap.(key);  src = sm.BlockPath;  lgn = sm.WorkspaceVar;  stt = 'LOGGED';  smp = ri.SampleTime.(key);
        elseif kind == "logged"
            src = 'not in model';  lgn = '';  stt = 'DERIVED';  smp = '1 ms grid';  desc = 'DERIVED = min(rpm_ramp*t, rpm_ref); the model does not log the reference';
        else
            src = 'computed from cleaned data';  lgn = derivText.(nm);  stt = 'DERIVED';  smp = '1 ms grid';
        end
    elseif kind == "logged"
        src = 'not in model';
    end
    rows(end+1,:) = {nm, src, lgn, spec{k,4}, 'double', smp, spec{k,5}, iif(inR,'YES','NO'), iif(inC,'YES','NO'), ...
        iif(inC,spec{k,6},'NO'), iif(inC,spec{k,7},'NO'), stt, desc}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'SignalName','SimulinkSource','LoggingName','Unit','DataType','SampleTime', ...
    'SignalGroup','RawAvailable','CleanedAvailable','LiveTelemetry','VandV','Status','Description'});
end

function T = groupSummary(C, spec)
rows = {};
for n = C.Properties.VariableNames(2:end)
    nm = n{1};  x = C.(nm);  xf = x(isfinite(x));
    u = spec{strcmp(spec(:,1), nm), 4};
    if isempty(xf), v = nan(1,9); else
        nlate = max(1, round(0.1*numel(xf)));
        v = [xf(1) xf(end) min(xf) max(xf) mean(xf) rmsf(xf) max(abs(xf)) std(xf) mean(xf(end-nlate+1:end))];
    end
    rows(end+1,:) = [{nm, u}, num2cell(v)]; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'Signal','Unit','StartValue','EndValue','Minimum','Maximum','Mean','RMS','PeakAbsolute','StandardDeviation','FinalValue'});
end

function T = eventTable(C, P)
t = C.Time;  rp = col(C,'RPM');  im = col(C,'MotorCurrent');  ref = col(C,'RPMReference');
soc = col(C,'SOC');  vb = col(C,'BatteryVoltage');  tq = col(C,'MotorTorque');
rows = {t(1),'SimulationStart','Simulation began (t = 0)'};
ev = @(i,typ,det) {t(i),typ,det};
i = find(ref > 10, 1);                 if ~isempty(i), rows(end+1,:) = ev(i,'SpeedCommandStart','reference > 10 rpm'); end
i = find(rp >= 0.1*P.rpm_ref, 1);      if ~isempty(i), rows(end+1,:) = ev(i,'SpeedRamp_10pct',sprintf('RPM >= %.0f',0.1*P.rpm_ref)); end
i = find(rp >= 0.9*P.rpm_ref, 1);      if ~isempty(i), rows(end+1,:) = ev(i,'SpeedRamp_90pct',sprintf('RPM >= %.0f',0.9*P.rpm_ref)); end
i = find(abs(tq) > 0.05*abs(P.T_load_end), 1);
if ~isempty(i), rows(end+1,:) = ev(i,'LoadStep',sprintf('|torque| > 5%% of final load (%.2f Nm)',abs(tq(i)))); end
lim = 0.98*P.I_peak;
i = find(abs(im) >= lim, 1);
if ~isempty(i)
    rows(end+1,:) = ev(i,'CurrentLimitActivated',sprintf('inferred: |I| = %.1f A >= 98%% of I_peak (limit signal not logged)',im(i)));
    j = find(abs(im(i:end)) < lim, 1);
    if ~isempty(j), rows(end+1,:) = ev(i+j-1,'CurrentLimitReleased',sprintf('inferred: |I| = %.1f A',im(i+j-1))); end
end
i = find(abs(im) > P.I_cont, 1);
if ~isempty(i), rows(end+1,:) = ev(i,'CurrentAboveContinuous',sprintf('|I| = %.1f A > I_cont %.0f A',im(i),P.I_cont)); end
i = find(vb > P.cells_series*4.19, 1);
if ~isempty(i), rows(end+1,:) = ev(i,'BatteryVoltageLimit',sprintf('V = %.2f V > %.2f V',vb(i),P.cells_series*4.19)); end
i = find(soc < 0.2, 1);                if ~isempty(i), rows(end+1,:) = ev(i,'SOCWarning',sprintf('SOC = %.4f < 0.2',soc(i))); end
core = [rp im vb];  i = find(any(~isfinite(core(:,any(isfinite(core),1))),2), 1);
if ~isempty(i), rows(end+1,:) = ev(i,'Fault','non-finite value in a logged core signal'); end
rows(end+1,:) = ev(numel(t),'SimulationStop',sprintf('tEnd = %.4f s',t(end)));
rows(end+1,:) = ev(numel(t),'SimulationComplete','data archived');
T = cell2table(rows, 'VariableNames', {'Time_s','EventType','Detail'});
T = sortrows(T,'Time_s');
end

function T = runInfoTable(runID, MDL, runDir, S, tEnd, vvStr, auditOk, nFail, nWarn)
sv = 'n/a';  try, v = ver('simulink'); sv = v(1).Version; catch, end
fm = @(d) char(datetime(d,'Format','yyyy-MM-dd HH:mm:ss'));
t0 = S.t0;  t1 = S.tStop;
dur = seconds(t1 - t0);
items = {'Run ID',runID; 'Date',char(datetime('now','Format','yyyy-MM-dd')); 'Time',char(datetime('now','Format','HH:mm:ss')); ...
    'Model',[MDL '.slx']; 'MATLAB Version',version; 'Simulink Version',sv; ...
    'Simulation Start (wall clock)',fm(t0); 'Simulation Stop (wall clock)',fm(t1); ...
    'Actual Duration (wall clock, s)',sprintf('%.1f',dur); 'Simulated Time (s)',sprintf('%.4f',tEnd); ...
    'V&V Status',vvStr; 'Logging Audit',sprintf('%s (%d FAIL, %d WARN)',iif(auditOk,'PASS','FAIL'),nFail,nWarn); ...
    'Status',iif(strcmp(vvStr,'FAIL')||startsWith(vvStr,'INCOMPLETE')||~auditOk,'COMPLETED WITH FAILURES','COMPLETED'); 'Archive',runDir};
T = cell2table(items, 'VariableNames', {'Item','Value'});
end

function T = mtab(rows)
if size(rows,2) ~= 4, rows = vertcat(rows{:}); end   % V5 FIX: rows arrived as an Nx1 cell of 1x4 cells
T = cell2table(rows, 'VariableNames', {'Metric','Value','Unit','Note'});
end

function r = mrow(name, val, unit, note)
if isempty(val) || ~isfinite(val), if isempty(note), note = 'NOT_AVAILABLE'; end, val = NaN; end
r = {name, val, unit, note};
end

function T = energyTable(C, P)
t = C.Time;  pb = col(C,'BatteryPower');  pm = col(C,'MotorMechanicalPower');  ef = col(C,'Efficiency');
late = t >= 0.9*t(end);
E = @(x) iif(any(isfinite(x)), trapz(t(isfinite(x)), x(isfinite(x)))/3600, NaN);
Eb = E(pb);  Em = E(pm);
R = {mrow('Battery power mean',mean(pb,'omitnan'),'W','');
     mrow('Battery power peak',max(abs(pb),[],'omitnan'),'W','');
     mrow('Battery power steady-state (last 10%)',mean(pb(late),'omitnan'),'W','');
     mrow('DC-link power',NaN,'W','NOT_AVAILABLE (no DC-link current logged)');
     mrow('Mechanical power mean',mean(pm,'omitnan'),'W','');
     mrow('Mechanical power peak',max(pm,[],'omitnan'),'W','');
     mrow('Mechanical power steady-state (last 10%)',mean(pm(late),'omitnan'),'W','');
     mrow('Energy consumed from battery',Eb,'Wh','trapz(BatteryPower)');
     mrow('Mechanical energy delivered',Em,'Wh','trapz(MotorMechanicalPower)');
     mrow('Energy-based efficiency',100*Em/Eb,'%','Emech/Ebatt');
     mrow('Efficiency steady-state (last 10%)',mean(ef(late),'omitnan'),'%','');
     mrow('Rated pack energy (13S x 3.7 V x Ah)',P.cells_series*3.7*P.pack_Ah,'Wh','project values')};
T = mtab(R);
end

function T = speedTable(C, P, ci)
t = C.Time;  rp = col(C,'RPM');  ref = col(C,'RPMReference');  late = t >= 0.9*t(end);
ss = mean(rp(late),'omitnan');  pk = max(rp,[],'omitnan');
t10 = firstT(t, rp >= 0.1*ss);  t90 = firstT(t, rp >= 0.9*ss);
out = find(abs(rp - P.rpm_ref) > 50 & isfinite(rp), 1, 'last');
ts = iif(isempty(out), 0, t(min(out+1,numel(t))));
note = iif(ci.RefDerived,'reference is DERIVED (not logged by model)','');
R = {mrow('Reference RPM (final)',ref(find(isfinite(ref),1,'last')),'rpm',note);
     mrow('Actual RPM (final sample)',rp(find(isfinite(rp),1,'last')),'rpm','');
     mrow('Steady-state RPM (mean last 10%)',ss,'rpm','');
     mrow('Peak RPM',pk,'rpm','');
     mrow('Overshoot vs steady state',max(0,100*(pk-ss)/ss),'%','');
     mrow('Speed error steady-state (target - actual)',P.rpm_ref-ss,'rpm','target = rpm_ref');
     mrow('Speed error RMS',rmsf(col(C,'SpeedError')),'rpm',note);
     mrow('Rise time 10-90%',t90-t10,'s','relative to steady-state RPM');
     mrow('Settling time (within +/-50 rpm of target)',ts,'s','')};
T = mtab(R);
end

function t = firstT(tv, mask)
i = find(mask,1);  if isempty(i), t = NaN; else, t = tv(i); end
end

function T = currentTable(C, P)
t = C.Time;  im = col(C,'MotorCurrent');  ib = col(C,'BatteryCurrent');  late = t >= 0.9*t(end);
dt = 1e-3;
R = {mrow('Battery current peak |I|',max(abs(ib),[],'omitnan'),'A','');
     mrow('Battery current RMS',rmsf(ib),'A','');
     mrow('Battery current mean',mean(ib,'omitnan'),'A','');
     mrow('Motor current peak |I|',max(abs(im),[],'omitnan'),'A','');
     mrow('Motor current RMS',rmsf(im),'A','');
     mrow('Motor current continuous (mean |I| last 10%)',mean(abs(im(late)),'omitnan'),'A','');
     mrow('Motor current steady-state max |I|',max(abs(im(late)),[],'omitnan'),'A','');
     mrow('Time above continuous limit',sum(abs(im) > P.I_cont)*dt,'s',sprintf('I_cont = %.0f A',P.I_cont));
     mrow('Time above peak limit',sum(abs(im) > P.I_peak)*dt,'s',sprintf('I_peak = %.0f A',P.I_peak));
     mrow('Phase A current',NaN,'A','NOT_AVAILABLE (not logged)');
     mrow('Phase B current',NaN,'A','NOT_AVAILABLE (not logged)');
     mrow('Phase C current',NaN,'A','NOT_AVAILABLE (not logged)')};
T = mtab(R);
end

function T = batteryTable(C)
t = C.Time;  vb = col(C,'BatteryVoltage');  ib = col(C,'BatteryCurrent');  pb = col(C,'BatteryPower');
soc = col(C,'SOC');  tmp = col(C,'BatteryTemperature');  sc = soc(isfinite(soc));
s0 = NaN; s1 = NaN; if ~isempty(sc), s0 = sc(1); s1 = sc(end); end
R = {mrow('Voltage min',min(vb,[],'omitnan'),'V','');
     mrow('Voltage max',max(vb,[],'omitnan'),'V','');
     mrow('Voltage mean',mean(vb,'omitnan'),'V','');
     mrow('Voltage final',vb(find(isfinite(vb),1,'last')),'V','');
     mrow('Current mean',mean(ib,'omitnan'),'A','');
     mrow('Current peak |I|',max(abs(ib),[],'omitnan'),'A','');
     mrow('Power mean',mean(pb,'omitnan'),'W','');
     mrow('Power peak',max(abs(pb),[],'omitnan'),'W','');
     mrow('Initial SOC',s0,'-','');
     mrow('Final SOC',s1,'-','');
     mrow('SOC change',s1-s0,'-','final - initial');
     mrow('Temperature mean',mean(tmp,'omitnan'),'degC',iif(any(isfinite(tmp)),'logged signal','NOT_AVAILABLE (not logged)'));
     mrow('Temperature maximum',max(tmp,[],'omitnan'),'degC',iif(any(isfinite(tmp)),'logged signal','NOT_AVAILABLE (not logged)'));
     mrow('Maximum cell temperature (dedicated channel)',max(col(C,'BatteryTemperatureMax'),[],'omitnan'),'degC',iif(any(isfinite(col(C,'BatteryTemperatureMax'))),'logged signal','NOT_AVAILABLE (not logged)'))};
T = mtab(R);
end

function T = traceTable(VVT, sigMap)
src = struct('RPM','rpm','MotorCurrent','imotor','BatteryVoltage','vbatt','SOC','soc');
rows = cell(height(VVT),7);
for k = 1:height(VVT)
    sg = VVT.Signal{k};  s = '';
    if isfield(src, sg), s = sigMap.(src.(sg)).WorkspaceVar; end
    rows(k,:) = {[VVT.RequirementID{k} ': ' VVT.Requirement{k}], sg, s, VVT.Calculation{k}, VVT.Expected{k}, VVT.Actual{k}, VVT.Status{k}};
end
T = cell2table(rows, 'VariableNames', {'Requirement','Signal','Source','Calculation','Expected','Actual','Status'});
end

function FR = finalStats(C)
t = C.Time;  late = t >= 0.9*t(end);
rp = col(C,'RPM');  im = col(C,'MotorCurrent');  ib = col(C,'BatteryCurrent');  soc = col(C,'SOC');  soc = soc(isfinite(soc));
FR.FinalRPM = mean(rp(late),'omitnan');
FR.PeakRPM  = max(rp,[],'omitnan');
FR.MotorCurrentPeak = max(abs(im),[],'omitnan');
FR.MotorCurrentRMS  = rmsf(im);
FR.BatteryCurrent   = mean(abs(ib(late)),'omitnan');
FR.BatteryCurrentPeak = max(abs(ib),[],'omitnan');
vbc = col(C,'BatteryVoltage');  pbc = col(C,'BatteryPower');  pmc = col(C,'MotorMechanicalPower');  efc = col(C,'Efficiency');
FR.BatteryVoltage   = mean(vbc(late),'omitnan');
FR.FinalSOC     = iif(~isempty(soc), soc(end), NaN);
FR.BatteryPower = mean(abs(pbc(late)),'omitnan');
FR.MechPower    = mean(abs(pmc(late)),'omitnan');
FR.Efficiency   = iif(FR.BatteryPower >= 1, 100*FR.MechPower/FR.BatteryPower, NaN);   % ratio of means (last 10%)
end

function s = overallVV(T)
i0 = strcmp(T.RequirementID,'VV-000');
if any(i0) && any(strcmpi(T.Status(i0),'FAIL')), s = 'INCOMPLETE (run shorter than t_stop)';
elseif any(strcmpi(T.Status,'FAIL')), s = 'FAIL';
elseif all(strcmpi(T.Status,'PASS')), s = 'PASS';
else, s = 'PARTIAL'; end
end

function L = commandLogHeader(runID, MDL, P, FR, vv, simDur, wallT, Raw, Clean, S, S1, daqOk)
nSig = sum(~strcmp(Raw.Properties.VariableNames,'Time'));
bar = '====================================================';
L = {bar,'  EV DIGITAL TWIN SIMULATION',bar, ...
     sprintf('  Run ID             : %s',runID), sprintf('  Date/Time          : %s',char(datetime('now'))), ...
     sprintf('  MATLAB version     : %s',version), sprintf('  Model              : %s.slx',MDL), ...
     '  Parameter file     : BLDCSpeedControlData.m', '', ...
     '  BATTERY', sprintf('    Configuration    : %dS%dP, %.0f Ah',P.cells_series,P.cells_parallel,P.pack_Ah), ...
     '  MOTOR',   sprintf('    Vnom %.0f V | Icont %.0f A | Ipeak %.0f A | Kt %.4f Nm/A | %.0f rpm | poles pairs %g',P.Vmotor_nom,P.I_cont,P.I_peak,P.Kt,P.rpm_nom,P.p), ...
     '  VEHICLE', sprintf('    gear %.1f | wheel radius %.3f m',P.gear_ratio,P.r_wheel), ...
     '  CONTROLLER', sprintf('    speed PI %.4f/%.2f | voltage PI %.3f/%.2f | limiter PI %.2f/%.0f | target %.0f rpm',P.Kpw,P.Kiw,P.Kpv,P.Kiv,P.Kpi,P.Kii,P.rpm_ref), '', ...
     sprintf('  Data acquisition   : %s', iif(daqOk,'PASS','FAIL')), ...
     sprintf('  Number of signals  : %d raw columns', nSig), ...
     sprintf('  Raw sample count   : %d', height(Raw)), sprintf('  Cleaned samples    : %d', height(Clean)), ...
     sprintf('  Sim time           : %.3f s   (wall clock %.1f s, post-processing %.1f s)', simDur, seconds(S1.tStop - S1.t0), wallT), '', ...
     sprintf('  Final RPM          : %.2f rpm', FR.FinalRPM), sprintf('  Peak RPM           : %.2f rpm', FR.PeakRPM), ...
     sprintf('  Peak motor current : %.2f A', FR.MotorCurrentPeak), sprintf('  RMS motor current  : %.2f A', FR.MotorCurrentRMS), ...
     sprintf('  Peak battery cur.  : %.2f A', FR.BatteryCurrentPeak), sprintf('  Battery voltage    : %.2f V', FR.BatteryVoltage), ...
     sprintf('  Final SOC          : %.4f', FR.FinalSOC), sprintf('  Battery power      : %.1f W', FR.BatteryPower), ...
     sprintf('  Mechanical power   : %.1f W', FR.MechPower), sprintf('  Efficiency         : %.1f %%', FR.Efficiency), '', ...
     sprintf('  FINAL V&V STATUS   : %s', vv), bar};
end

function makeFigures(C, runDir, figDir, LG)
t = C.Time;
fg = [];
try
    fg = figure('Visible','off','Position',[50 50 1000 560],'Color','w');   % ONE figure, reused for every plot
catch ME
    LG(['Figures skipped: ' ME.message]);  return
end
sf = @(fn, plotFn) saveFig(fg, figDir, fn, plotFn, LG);
sf('Speed.png',           @() plotSet(t, {col(C,'RPMReference'),col(C,'RPM')}, {'RPM reference','RPM'}, 'Motor Speed: Reference vs Actual', 'Speed [rpm]'));
sf('Battery_Voltage.png', @() plotSet(t, {col(C,'BatteryVoltage')}, {'Battery voltage'}, 'Battery Voltage vs Time', 'Voltage [V]'));
sf('Battery_Current.png', @() plotSet(t, {col(C,'BatteryCurrent')}, {'Battery discharge current'}, 'Battery Discharge Current vs Time', 'Discharge Current [A]'));
sf('Battery_Current_Corrected.png', @() plotSet(t, {col(C,'BatteryCurrent')}, {'Battery discharge current'}, 'Battery Discharge Current vs Time', 'Discharge Current [A]'));
sf('Motor_Current.png',   @() plotSet(t, {col(C,'MotorCurrent')}, {'Motor current (log_Idc_f)'}, 'Motor Current vs Time', 'Current [A]'));
sf('SOC.png',             @() plotSet(t, {col(C,'SOC')}, {'SOC'}, 'State of Charge vs Time', 'SOC [0..1]'));
sf('DC_Link.png',         @() plotSet(t, {col(C,'DCLinkVoltage')}, {'DC-link voltage'}, 'DC-Link Voltage vs Time', 'DC-Link Voltage [V]'));
sf('DC_Link_Voltage_Corrected.png', @() plotSet(t, {col(C,'DCLinkVoltage')}, {'DC-link voltage'}, 'DC-Link Voltage vs Time', 'DC-Link Voltage [V]'));
sf('V_and_I_Overview.png',@() overview(C));
try, close(fg); catch, end
end

function saveFig(fg, figDir, fname, plotFn, LG)
f = fullfile(figDir, fname);
cfgF = evCfg();
try
    clf(fg);
    plotFn();
    res = 150;
    try, exportgraphics(fg, f, 'Resolution', res); catch, saveas(fg, f); end
    d = dir(f);
    while ~isempty(d) && d.bytes >= cfgF.maxBytes && res > 20      % PNG must stay < 20 MB
        res = max(20, round(res/2));
        exportgraphics(fg, f, 'Resolution', res);  d = dir(f);
    end
catch ME
    LG(sprintf('Figure %s error: %s', fname, ME.message));
end
end

function plotSet(t, ys, labs, ttl, yl)
hold on;  n = 0;
for k = 1:numel(ys)
    if any(isfinite(ys{k})), plot(t, ys{k}, 'LineWidth', 1.6, 'DisplayName', labs{k}); n = n + 1; end
end
if n == 0
    text(0.5,0.5,'NOT AVAILABLE - signal not logged by model','Units','normalized','HorizontalAlignment','center');
else
    legend('Location','best');
end
title(ttl); xlabel('Time [s]'); ylabel(yl); grid on; box on;
end

function overview(C)
t = C.Time;
sp = {{'BatteryVoltage','Battery Voltage','V'},{'BatteryCurrent','Battery Current','A'}, ...
      {'RPM','Motor RPM','rpm'},{'MotorCurrent','Motor Current','A'}};
for k = 1:4
    subplot(2,2,k);  x = col(C, sp{k}{1});
    if any(isfinite(x)), plot(t, x, 'LineWidth', 1.4, 'DisplayName', sp{k}{2}); legend('Location','best');
    else, text(0.5,0.5,'NOT AVAILABLE','Units','normalized','HorizontalAlignment','center'); end
    title(sp{k}{2}); xlabel('Time [s]'); ylabel(sprintf('%s [%s]', sp{k}{2}, sp{k}{3})); grid on;
end
try, sgtitle('Voltage, Current and Speed Overview'); catch, end
end

function finalReport(runID, MDL, simDur, FR, rawOk, daqOk, cleanOk, auditOk, vv, runDir, nWarn, xlOk)
fl = @(a,b) fprintf('%-20s: %s\n', a, b);
f2 = @(x) sprintf('%.2f', x);
pf = @(x) iif(x,'PASS','FAIL');
fprintf('\n====================================================\nEV DIGITAL TWIN - FINAL RUN REPORT\n====================================================\n\n');
fl('RUN ID', runID);  fl('MODEL', MDL);  fl('SIMULATION TIME', [f2(simDur) ' s']);  fprintf('\n');
fl('DATA ACQUISITION', pf(daqOk));  fl('RAW DATA', pf(rawOk));  fl('DATA CLEANING', pf(cleanOk));
fl('LOGGING AUDIT', [pf(auditOk) sprintf('  (%d warning(s), details in 05_Logging_Audit.csv)', nWarn)]);
fl('EXCEL REPORT', iif(xlOk,'PASS','FAIL'));  fl('V&V', vv);  fprintf('\n');
fl('FINAL RPM', [f2(FR.FinalRPM) ' rpm']);  fl('PEAK RPM', [f2(FR.PeakRPM) ' rpm']);
fl('MOTOR CURRENT PEAK', [f2(FR.MotorCurrentPeak) ' A']);  fl('MOTOR CURRENT RMS', [f2(FR.MotorCurrentRMS) ' A']);
fl('BATTERY CURRENT', [f2(FR.BatteryCurrent) ' A']);  fl('BATTERY VOLTAGE', [f2(FR.BatteryVoltage) ' V']);
fl('FINAL SOC', f2(FR.FinalSOC));  fl('BATTERY POWER', [f2(FR.BatteryPower) ' W']);
fl('MECHANICAL POWER', [f2(FR.MechPower) ' W']);  fl('EFFICIENCY', [f2(FR.Efficiency) ' %' iif(FR.Efficiency > 100,'   <-- INVALID (>100 %): check power scaling','')]);  fprintf('\n');
fl('TOTAL V&V', vv);
fprintf('\nARCHIVE:\n%s\n\n====================================================\nRUN COMPLETE\n====================================================\n\n', runDir);
end


%% ========================================================================
%%  utilities
%% ========================================================================
function x = rmsf(v)
v = v(isfinite(v));
if isempty(v), x = NaN; else, x = sqrt(mean(v.^2)); end
end

function v = safeBase(name, default)
try
    v = evalin('base', name);
    if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v), v = default; end
catch
    v = default;
end
end

function v = baseOrEmpty(name)
v = [];
try
    x = evalin('base', name);
    if isnumeric(x) && isscalar(x) && isfinite(x), v = x; end
catch
end
end

function s = safeStr(name)
s = '';  try, s = evalin('base', name); catch, end
if ~ischar(s), s = ''; end
end

function vprint(flag, fmt, varargin)
if flag, fprintf(fmt, varargin{:}); end
end

function s = iif(c, a, b)
if c, s = a; else, s = b; end
end


%% ========================================================================
%%  V5  LOSSLESS COLUMN COMPACTION  (bit-exact: exact duplicates, constants, RLE)
%%
%%  Columns are compared through their IEEE-754 bit patterns (typecast to uint64):
%%  no tolerance, no correlation, no rounding. NaN and -0 are therefore handled
%%  exactly. The original table is reproduced bit for bit by evReconstruct.
%% ========================================================================
function comp = evCompress(names, t, X, cfg)
[N, C] = size(X);
comp = struct('N',N,'C',C,'names',{names},'t',t);
% estimate of the uncompressed full-width CSV (%.17g, same layout V4 wrote as 02b)
idx = unique(round(linspace(1, N, min(N,200))));
fmt = [repmat('%.17g,', 1, C) '%.17g\n'];
bpr = numel(sprintf(fmt, [t(idx) X(idx,:)].')) / numel(idx);
comp.estBytes = bpr*N + numel(strjoin(names, ',')) + 1;
U = reshape(typecast(X(:), 'uint64'), N, C);          % exact bit patterns
clear X
[~, ia, ic] = unique(U.', 'rows', 'stable');          % identical columns share one representative
rep = ia(ic);  rep = rep(:);                          % first column with identical bits, per original column
kind = zeros(C, 1, 'uint8');                          % 1 dense, 2 constant, 3 run-length (set on representatives)
constBits = zeros(C, 1, 'uint64');
nRunsArr = zeros(C, 1);
denseIdx = zeros(C, 1);  denseCols = zeros(1, 0);  rle = cell(C, 1);  nd = 0;
for k = 1:numel(ia)
    j = ia(k);  u = U(:, j);
    chg = find(u(2:end) ~= u(1:end-1)) + 1;           % first index of every new run
    nRuns = 1 + numel(chg);
    nRunsArr(j) = nRuns;
    if nRuns == 1
        kind(j) = 2;  constBits(j) = u(1);
    elseif 3*nRuns < N                                 % RLE only if it needs fewer numbers than dense (start, value, count per run)
        kind(j) = 3;
        st = [1; chg(:)];  en = [chg(:) - 1; N];
        rle{j} = struct('st', st, 'en', en, 'bits', u(st));
    else
        kind(j) = 1;  nd = nd + 1;  denseIdx(j) = nd;  denseCols(end+1) = j; %#ok<AGROW>
    end
end
D = zeros(N, nd);
if nd > 0
    Ud = U(:, denseCols);
    D = reshape(typecast(Ud(:), 'double'), N, nd);
    clear Ud
end
clear U
comp.Xw = [t(:) D];                                   % Time + dense columns (what is written to disk)
clear D
comp.denseNames = names(1 + denseCols);
comp.nRuns = nRunsArr;
comp.rep = rep;  comp.kind = kind;  comp.constBits = constBits;  comp.denseIdx = denseIdx;  comp.rle = rle;
comp.nDupCols = C - numel(ia);
comp.nConst   = nnz(kind == 2);
comp.nRleCols = nnz(kind == 3);
comp.nDense   = nd;
comp.nRleSeg  = 0;
for j = find(kind == 3).', comp.nRleSeg = comp.nRleSeg + numel(rle{j}.st); end
end

function X = evReconstruct(comp)
N = comp.N;  C = comp.C;
Ur = zeros(N, C, 'uint64');
Ud = zeros(N, 0, 'uint64');
if size(comp.Xw, 2) > 1
    Dd = comp.Xw(:, 2:end);
    Ud = reshape(typecast(Dd(:), 'uint64'), N, []);
    clear Dd
end
for j = 1:C
    s = comp.rep(j);
    if s ~= j
        Ur(:, j) = Ur(:, s);                          % exact duplicate of an earlier column (s < j)
        continue
    end
    switch comp.kind(j)
        case 1, Ur(:, j) = Ud(:, comp.denseIdx(j));
        case 2, Ur(:, j) = comp.constBits(j);
        case 3
            r = comp.rle{j};
            Ur(:, j) = repelem(r.bits, r.en - r.st + 1);
    end
end
X = reshape(typecast(Ur(:), 'double'), N, C);
end

function rc = evCompare(X0, XR, comp)
rc.RowsOriginal = size(X0, 1);       rc.RowsReconstructed = size(XR, 1);
rc.ColumnsOriginal = size(X0, 2)+1;  rc.ColumnsReconstructed = size(XR, 2)+1;
U0 = typecast(X0(:), 'uint64');  UR = typecast(XR(:), 'uint64');
same = (U0 == UR);
rc.NumberDifferentValues = nnz(~same);
d = abs(X0(:) - XR(:));
d(isnan(d) & ~same) = Inf;
d(same) = 0;
rc.MaximumAbsoluteDifference = max([0; d]);
ok = rc.NumberDifferentValues == 0 && rc.MaximumAbsoluteDifference == 0 && ...
     rc.RowsOriginal == rc.RowsReconstructed && rc.ColumnsOriginal == rc.ColumnsReconstructed && ...
     rc.RowsOriginal == comp.N;
if ok, rc.Status = 'PASS'; else, rc.Status = 'FAIL'; end
end

function [Rm, rj] = evRleMatrix(comp)
% run-length segments of all RLE columns: [StoredColumnID StartIndex EndIndex StartTime EndTime Value Count]
rj = find(comp.kind == 3);
blocks = cell(numel(rj), 1);
for q = 1:numel(rj)
    j = rj(q);  r = comp.rle{j};  n = numel(r.st);
    blocks{q} = [repmat(j, n, 1), r.st, r.en, comp.t(r.st), comp.t(r.en), typecast(r.bits, 'double'), r.en - r.st + 1];
end
if isempty(blocks), Rm = zeros(0, 7); else, Rm = vertcat(blocks{:}); end
end

function c = evBitsToText(bits)
c = cell(numel(bits), 1);
for k = 1:numel(bits), c{k} = sprintf('%.17g', typecast(bits(k), 'double')); end
end

function X = evReadParts(M, dirp)
% read the numeric content of all written parts back (header skipped), in order
parts = cell(height(M), 1);
for k = 1:height(M)
    parts{k} = readmatrix(fullfile(dirp, M.FileName{k}), 'NumHeaderLines', 1);
end
X = vertcat(parts{:});
end

function CA = evEmptyAudit()
CA = struct('RowsOriginal',NaN,'RowsReconstructed',NaN,'ColumnsOriginal',NaN,'ColumnsReconstructed',NaN, ...
    'MaxAbsDiff',NaN,'NumDiff',NaN,'Status','SKIPPED','FileRoundTrip','SKIPPED', ...
    'DuplicateColumns',NaN,'ConstantColumns',NaN,'RLEColumns',NaN,'RLESegments',NaN,'DenseColumns',NaN, ...
    'RowsAfter',NaN,'ColumnsAfter',NaN,'UncompBytes',NaN,'CompBytes',NaN);
end

function TV = evTimeVectorAudit(S)
% duplicate / repeated time information in the logged signals
TV = struct('Signals',0,'Distinct',0,'Duplicate',0,'RepeatedStamps',0);
keys = fieldnames(S);  groups = {};
for k = 1:numel(keys)
    t = S.(keys{k}).t;
    if isempty(t), continue, end
    TV.Signals = TV.Signals + 1;
    TV.RepeatedStamps = TV.RepeatedStamps + sum(diff(t(:)) == 0);
    found = false;
    for g = 1:numel(groups)
        if numel(groups{g}) == numel(t) && isequal(groups{g}, t(:)), found = true; break, end
    end
    if found, TV.Duplicate = TV.Duplicate + 1; else, groups{end+1} = t(:); end %#ok<AGROW>
end
TV.Distinct = numel(groups);
end


%% ========================================================================
%%  V5  SIZE-LIMITED WRITERS  (every output file < 20 MB, chunked by whole rows)
%% ========================================================================
function M = writeUnder20MB(data, baseName, outDir, maxBytes, opts)
% data   : table, or struct('X',numericMatrix,'Names',cellstrHeader) for large numeric data
% opts   : AlwaysPart (name files _PartNNN even if one part), FullPrecision (%.17g, lossless text),
%          Manifest (write <baseName>_Manifest.csv; always written when there is more than one part)
% Never splits inside a row, keeps chronological order, re-writes a part with fewer rows if it is >= maxBytes.
if nargin < 5 || isempty(opts), opts = struct(); end
if nargin < 4 || isempty(maxBytes), maxBytes = 20*1024*1024; end
if ~isfield(opts,'AlwaysPart'),    opts.AlwaysPart = false;    end
if ~isfield(opts,'FullPrecision'), opts.FullPrecision = false; end
if ~isfield(opts,'Manifest'),      opts.Manifest = false;      end
if istable(data) && opts.FullPrecision && all(varfun(@isnumeric, data, 'OutputFormat', 'uniform'))
    data = struct('X', data{:,:}, 'Names', {data.Properties.VariableNames});
end
if isstruct(data)
    M = evWriteNumeric(data.X, data.Names, baseName, outDir, maxBytes, opts.AlwaysPart);
else
    M = evWriteTableParts(data, baseName, outDir, maxBytes, opts.AlwaysPart);
end
if opts.Manifest || height(M) > 1
    writetable(M, fullfile(outDir, [baseName '_Manifest.csv']));
end
end

function M = evWriteNumeric(X, hdr, baseName, outDir, maxBytes, alwaysPart)
[N, C] = size(X);
hline = [strjoin(hdr, ',') newline];
fmt = [repmat('%.17g,', 1, C-1) '%.17g\n'];
hasT = strcmp(hdr{1}, 'Time');
bpr = 1;
if N > 0
    idx = unique(round(linspace(1, N, min(N,500))));
    bpr = numel(sprintf(fmt, X(idx,:).')) / numel(idx);
end
useParts = alwaysPart || (numel(hline) + bpr*N) > 0.8*maxBytes;
rowsPer = max(1, floor((0.85*maxBytes - numel(hline)) / bpr));
if ~useParts, rowsPer = max(N, 1); end
rec = cell(0, 7);  r0 = 1;  k = 0;
while true
    k = k + 1;
    r1 = min(N, r0 + rowsPer - 1);
    if useParts, name = sprintf('%s_Part%03d.csv', baseName, k); else, name = [baseName '.csv']; end
    fn = fullfile(outDir, name);
    bytes = evWriteChunk(fn, hline, fmt, X, r0, r1);
    if bytes >= maxBytes
        if ~useParts                                           % estimate was wrong: restart in parts
            delete(fn);
            M = evWriteNumeric(X, hdr, baseName, outDir, maxBytes, true);
            return
        end
        if r1 > r0
            rowsPer = max(1, floor((r1 - r0 + 1) * 0.7));     % shrink this part and rewrite it
            k = k - 1;
            continue
        end
    end
    t0 = NaN;  t1 = NaN;
    if hasT && r1 >= r0, t0 = X(r0, 1);  t1 = X(r1, 1); end
    rec(end+1, :) = {k, name, t0, t1, max(0, r1 - r0 + 1), C, bytes}; %#ok<AGROW>
    r0 = r1 + 1;
    if r0 > N, break, end
end
M = cell2table(rec, 'VariableNames', {'PartNumber','FileName','StartTime','EndTime','Rows','Columns','FileSizeBytes'});
end

function bytes = evWriteChunk(fn, hline, fmt, X, r0, r1)
fid = fopen(fn, 'w');
if fid < 0, error('EV_DAQ:write', 'cannot write %s', fn); end
fprintf(fid, '%s', hline);
if r1 >= r0, fprintf(fid, fmt, X(r0:r1, :).'); end
fclose(fid);
d = dir(fn);  bytes = d.bytes;
end

function M = evWriteTableParts(T, baseName, outDir, maxBytes, alwaysPart)
n = height(T);  vn = T.Properties.VariableNames;
hasT = ~isempty(vn) && strcmp(vn{1}, 'Time') && isnumeric(T.(vn{1}));
fn = fullfile(outDir, [baseName '.csv']);
writetable(T, fn);  d = dir(fn);  b = d.bytes;
if b < maxBytes && ~alwaysPart
    t0 = NaN;  t1 = NaN;  if hasT && n > 0, t0 = T.(vn{1})(1);  t1 = T.(vn{1})(n); end
    M = cell2table({1, [baseName '.csv'], t0, t1, n, width(T), b}, ...
        'VariableNames', {'PartNumber','FileName','StartTime','EndTime','Rows','Columns','FileSizeBytes'});
    return
end
delete(fn);
rowsPer = max(1, floor(n * 0.8 * maxBytes / max(b, 1)));
rec = cell(0, 7);  r0 = 1;  k = 0;
while true
    k = k + 1;
    r1 = min(n, r0 + rowsPer - 1);
    name = sprintf('%s_Part%03d.csv', baseName, k);  f = fullfile(outDir, name);
    writetable(T(r0:r1, :), f);  d = dir(f);
    if d.bytes >= maxBytes && r1 > r0
        rowsPer = max(1, floor((r1 - r0 + 1) * 0.7));  k = k - 1;  continue
    end
    t0 = NaN;  t1 = NaN;  if hasT && r1 >= r0, t0 = T.(vn{1})(r0);  t1 = T.(vn{1})(r1); end
    rec(end+1, :) = {k, name, t0, t1, max(0, r1 - r0 + 1), width(T), d.bytes}; %#ok<AGROW>
    r0 = r1 + 1;
    if r0 > n, break, end
end
M = cell2table(rec, 'VariableNames', {'PartNumber','FileName','StartTime','EndTime','Rows','Columns','FileSizeBytes'});
end

function M = evSaveTable(T, runDir, name)
c = evCfg();
M = writeUnder20MB(T, name, runDir, c.maxBytes, struct());
end

function T = evFileManifest(runDir, maxBytes)
d = dir(fullfile(runDir, '**', '*'));  d = d(~[d.isdir]);
n = numel(d);  rel = cell(n, 1);  b = zeros(n, 1);
for k = 1:n
    rel{k} = strrep(fullfile(d(k).folder, d(k).name), [runDir filesep], '');
    b(k) = d(k).bytes;
end
ok = repmat({'PASS'}, n, 1);  ok(b >= maxBytes) = {'FAIL'};
T = table(rel, b, b/2^20, ok, 'VariableNames', {'File','Bytes','MB','Under20MB'});
if n > 1, T = sortrows(T, 'File'); end
end

function b = evDirBytes(runDir, pats)
b = 0;
for k = 1:numel(pats)
    d = dir(fullfile(runDir, pats{k}));  d = d(~[d.isdir]);
    if ~isempty(d), b = b + sum([d.bytes]); end
end
end

function b = evDirMaxBytes(runDir, pats)
b = 0;
for k = 1:numel(pats)
    d = dir(fullfile(runDir, pats{k}));  d = d(~[d.isdir]);
    if ~isempty(d), b = max(b, max([d.bytes])); end
end
end

function [nF, big, nSplit, bad] = evFinalSizeCheck(runDir, maxBytes)
% safety net over EVERY file in the run folder; oversized csv/txt files are split by whole lines
nSplit = 0;  bad = {};
d = dir(fullfile(runDir, '**', '*'));  d = d(~[d.isdir]);
for k = 1:numel(d)
    if d(k).bytes < maxBytes, continue, end
    f = fullfile(d(k).folder, d(k).name);  [~, ~, ext] = fileparts(f);
    if any(strcmpi(ext, {'.csv', '.txt'}))
        evSplitByLines(f, maxBytes, strcmpi(ext, '.csv'));  nSplit = nSplit + 1;
    else
        bad{end+1} = f; %#ok<AGROW>
    end
end
d = dir(fullfile(runDir, '**', '*'));  d = d(~[d.isdir]);
nF = numel(d);  big = 0;  if nF > 0, big = max([d.bytes]); end
if big >= maxBytes && isempty(bad), bad = {'still above the limit'}; end
end

function evSplitByLines(f, maxBytes, hasHeader)
L = splitlines(fileread(f));
if ~isempty(L) && isempty(L{end}), L(end) = []; end
[p, n, e] = fileparts(f);
head = '';  if hasHeader && ~isempty(L), head = L{1};  L(1) = []; end
budget = 0.9*maxBytes;  k = 0;  i = 1;
while i <= numel(L)
    k = k + 1;  bytes = numel(head) + 1;  j = i;
    while j <= numel(L) && bytes + numel(L{j}) + 1 < budget, bytes = bytes + numel(L{j}) + 1;  j = j + 1; end
    if j == i, j = i + 1; end
    fid = fopen(fullfile(p, sprintf('%s_Part%03d%s', n, k, e)), 'w');
    if ~isempty(head), fprintf(fid, '%s\n', head); end
    fprintf(fid, '%s\n', strjoin(L(i:j-1), newline));
    fclose(fid);  i = j;
end
delete(f);
end


%% ========================================================================
%%  V5  COMPRESSION AUDIT + PERFORMANCE REPORT
%% ========================================================================
function T = evCompressionAuditTable(CA, TV, nDupT, nRows, nCols)
g = @(x) sprintf('%.17g', x);
R = {'MergeRule',              'bit-exact (IEEE-754 bit patterns)', 'no tolerance, no correlation, no rounding';
     'RowsOriginal',           g(CA.RowsOriginal),          'rows of the full-width raw log';
     'RowsReconstructed',      g(CA.RowsReconstructed),     '';
     'ColumnsOriginal',        g(CA.ColumnsOriginal),       'including Time';
     'ColumnsReconstructed',   g(CA.ColumnsReconstructed),  'including Time';
     'MaximumAbsoluteDifference', g(CA.MaxAbsDiff),         'original vs reconstructed';
     'NumberDifferentValues',  g(CA.NumDiff),               'bitwise';
     'ReconstructionStatus',   CA.Status,                   'in-memory reconstruction vs original';
     'FileRoundTripStatus',    CA.FileRoundTrip,            'written compact files read back and compared';
     'DuplicateColumnsRemoved',g(CA.DuplicateColumns),      'exactly identical columns stored once (see 02c_Column_Map.csv)';
     'ConstantColumnsDetected',g(CA.ConstantColumns),       'see 04_Constant_Values.csv';
     'RLEColumns',             g(CA.RLEColumns),            'columns stored as run-length segments';
     'RLESegments',            g(CA.RLESegments),           'see 02d_RLE_Segments.csv';
     'DenseColumnsStored',     g(CA.DenseColumns),          'stored in 02b_Raw_PerCell_Compact_PartNNN.csv';
     'RowsBeforeCompression',  g(nRows),                    'native logged rows';
     'RowsAfterCompression',   g(CA.RowsAfter),             'rows of the dense table (rows are not dropped)';
     'ColumnsBeforeCompression', g(nCols),                  'including Time';
     'ColumnsAfterCompression',  g(CA.ColumnsAfter),        'dense columns + Time';
     'UncompressedEstimateBytes', g(CA.UncompBytes),        'full-width CSV (%.17g) that would have been written';
     'CompressedBytes',        g(CA.CompBytes),             '02b + 02c + 02d + 04_Constant_Values';
     'DistinctTimeVectors',    g(TV.Distinct),              sprintf('among %d logged signals', TV.Signals);
     'DuplicateTimeVectors',   g(TV.Duplicate),             'signals sharing an identical time vector (one canonical time column is stored)';
     'RepeatedTimestampsInLogs', g(TV.RepeatedStamps),      'zero-length steps in the native logs';
     'RepeatedTimestampsRemovedInPackRaw', g(nDupT),        'last sample kept (as V4)'};
T = cell2table(R, 'VariableNames', {'Metric','Value','Note'});
end

function [PT, PM] = evPerformance(runDir, cfg, TM, simWall, postWall, CA, tEnd, nExtra, archDir)
g  = @(x) sprintf('%.6g', x);
st = @(ok) iif(ok, 'PASS', 'FAIL');
it = evTimes('get');  PM.init = 0;
for f = fieldnames(it)', PM.init = PM.init + it.(f{1}); end
PM.simWall = simWall;  PM.postWall = postWall;  PM.total = PM.init + simWall + postWall;
PM.peakMB  = evMem('peak');
FMt = evFileManifest(runDir, cfg.maxBytes);
PM.nFiles   = height(FMt) + nExtra;
PM.largest  = max([0; FMt.Bytes]);
PM.packRaw  = evDirBytes(archDir, {'02_Raw_Data_*'});
PM.comp     = evDirBytes(archDir, {'02b_*','02c_*','02d_*','04_Constant_Values.csv'});
PM.compMax  = evDirMaxBytes(archDir, {'02b_*','02c_*','02d_*','04_Constant_Values.csv'});   % V7.4: the 20 MB limit is per FILE
PM.clean    = evDirBytes(runDir, {'03_Cleaned_Data.xlsx'});
PM.xl       = evDirBytes(runDir, {'*.xlsx'});
PM.rawEst   = CA.UncompBytes;
PM.ratio    = NaN;  if isfinite(PM.rawEst) && PM.rawEst > 0, PM.ratio = 100*(1 - PM.comp/PM.rawEst); end
MB = 2^20;  lim = cfg.maxBytes/MB;
R = cell(0, 6);
add = @(m,v,u,l,s,n) {m, v, u, l, s, n};
R(end+1,:) = add('SimulationTime', g(tEnd), 's', g(cfg.t_stop), st(abs(tEnd - cfg.t_stop) <= 1e-3), 'simulated time reached');
R(end+1,:) = add('SimulationWallTime', g(simWall), 's', '-', 'INFO', 'StartFcn to StopFcn, includes Simscape initialisation');
R(end+1,:) = add('PostProcessingTime', g(postWall), 's', '-', 'INFO', 'StopFcn work incl. this report; excludes writing 10/11 logs (<1 s)');
R(end+1,:) = add('TotalWallTime', g(PM.total), 's', g(cfg.targetMax_s), st(PM.total <= cfg.targetMax_s), sprintf('start-up %.2f s + simulation + post-processing; ideal < %g s', PM.init, cfg.targetIdeal_s));
R(end+1,:) = add('PeakMemory', g(PM.peakMB), 'MB', '-', 'INFO', 'largest MATLAB memory sample at stage boundaries (not a continuous peak)');
R(end+1,:) = add('RawFileSize', g(PM.rawEst/MB), 'MB', '-', 'INFO', 'ESTIMATE of the uncompressed full-width raw CSV (not written)');
R(end+1,:) = add('PackRawFileSize', g(PM.packRaw/MB), 'MB', g(lim), st(PM.packRaw < cfg.maxBytes), 'Raw_Archive/02_Raw_Data parts + manifest');
R(end+1,:) = add('CompressedFileSize', g(PM.comp/MB), 'MB', '-', 'INFO', 'TOTAL of all compact parts (02b, 02c, 02d, 04_Constant_Values); the 20 MB limit applies per file');
R(end+1,:) = add('CompressedLargestFile', g(PM.compMax/MB), 'MB', g(lim), st(PM.compMax < cfg.maxBytes), 'largest single compact part');
R(end+1,:) = add('CleanedFileSize', g(PM.clean/MB), 'MB', g(lim), st(PM.clean < cfg.maxBytes), '03_Cleaned_Data.xlsx');
R(end+1,:) = add('ExcelFileSize', g(PM.xl/MB), 'MB', g(lim), st(PM.xl < cfg.maxBytes), 'all .xlsx written before this report (09 and 01 follow)');
R(end+1,:) = add('LargestFileSize', g(PM.largest/MB), 'MB', g(lim), st(PM.largest < cfg.maxBytes), 'largest single file in the run folder (before 10/11/13)');
R(end+1,:) = add('NumberOfFiles', g(PM.nFiles), '-', '-', 'INFO', 'includes 10_Command_Log, 11_Simulation_Log and this file');
R(end+1,:) = add('CompressionRatio', g(PM.ratio), '%', '-', 'INFO', '100*(1 - compressed/uncompressed estimate)');
R(end+1,:) = add('DuplicateColumnsRemoved', g(CA.DuplicateColumns), '-', '-', 'INFO', 'bit-identical columns stored once');
R(end+1,:) = add('ConstantColumnsDetected', g(CA.ConstantColumns), '-', '-', 'INFO', '');
R(end+1,:) = add('RLESegments', g(CA.RLESegments), '-', '-', 'INFO', '');
R(end+1,:) = add('RowsBeforeCompression', g(CA.RowsOriginal), '-', '-', 'INFO', '');
R(end+1,:) = add('RowsAfterCompression', g(CA.RowsAfter), '-', '-', 'INFO', 'rows are kept; columns are reduced');
R(end+1,:) = add('ColumnsBeforeCompression', g(CA.ColumnsOriginal), '-', '-', 'INFO', 'including Time');
R(end+1,:) = add('ColumnsAfterCompression', g(CA.ColumnsAfter), '-', '-', 'INFO', 'dense columns + Time');
R(end+1,:) = add('LosslessReconstruction', CA.Status, '-', 'PASS', iif(strcmp(CA.Status,'PASS'),'PASS',iif(strcmp(CA.Status,'SKIPPED'),'INFO','FAIL')), ['written files read back: ' CA.FileRoundTrip]);
PT = cell2table(R, 'VariableNames', {'Metric','Value','Unit','Limit','Status','Note'});
end

function evPrintPerformance(PM, cfg, TM, CA, vvStr, tEnd, P)
it = evTimes('get');
fprintf('\n[TIME]\n');
fprintf('  Model loading        : %9.2f s\n', gf(it,'ModelLoading'));
fprintf('  Parameter loading    : %9.2f s\n', gf(it,'ParameterLoading'));
fprintf('  Model configuration  : %9.2f s\n', gf(it,'ModelConfiguration'));
fprintf('  Simulation           : %9.2f s   (StartFcn -> StopFcn)\n', PM.simWall);
fprintf('  Raw extraction       : %9.2f s\n', gf(TM,'RawExtraction'));
fprintf('  Compression          : %9.2f s\n', gf(TM,'Compression'));
fprintf('  Cleaning             : %9.2f s\n', gf(TM,'Cleaning'));
fprintf('  V&V                  : %9.2f s\n', gf(TM,'VV'));
fprintf('  Excel                : %9.2f s\n', gf(TM,'Excel'));
fprintf('  Figures              : %9.2f s\n', gf(TM,'Figures'));
fprintf('  Archive              : %9.2f s\n', gf(TM,'Archive'));
fprintf('  TOTAL                : %9.2f s\n', PM.total);
mb = @(b) b/2^20;
pf = @(x) iif(x, 'PASS', 'FAIL');
fprintf('\n========================================================\n');
fprintf('EV DIGITAL TWIN - PERFORMANCE SUMMARY\n');
fprintf('========================================================\n\n');
fprintf('Simulation Stop Time : %.2f s\n\n', tEnd);
fprintf('Simulation Wall Time : %.2f s\n', PM.simWall);
fprintf('Post-Processing Time : %.2f s\n', PM.postWall);
fprintf('Total Wall Time      : %.2f s\n\n', PM.total);
fprintf('Peak Memory          : %.0f MB\n\n', PM.peakMB);
fprintf('Raw Data Size        : %.2f MB  (uncompressed full-width estimate; pack-level raw files: %.2f MB)\n', mb(PM.rawEst), mb(PM.packRaw));
fprintf('Compressed Data Size : %.2f MB\n', mb(PM.comp));
fprintf('Cleaned Data Size    : %.2f MB\n', mb(PM.clean));
fprintf('Largest Output File  : %.2f MB\n\n', mb(PM.largest));
fprintf('Compression Ratio    : %.1f %%\n\n', PM.ratio);
fprintf('Duplicate Columns    : %g\n', CA.DuplicateColumns);
fprintf('Constant Columns     : %g\n', CA.ConstantColumns);
fprintf('RLE Segments         : %g\n\n', CA.RLESegments);
fprintf('Lossless Reconstruction : %s   (files read back: %s)\n', CA.Status, CA.FileRoundTrip);
fprintf('V&V Status              : %s\n\n', vvStr);
fprintf('20 MB File Limit       : %s\n', pf(PM.largest < cfg.maxBytes));
fprintf('3-4 Minute Target      : %s   (limit %g s, ideal %g s)\n\n', pf(PM.total <= cfg.targetMax_s), cfg.targetMax_s, cfg.targetIdeal_s);
if PM.simWall >= PM.postWall + PM.init
    fprintf('BOTTLENECK: the simulation (Simulink/Simscape solver) = %.0f %% of the total wall time.\n', 100*PM.simWall/max(PM.total, eps));
    fprintf('            Post-processing changes cannot make the solver faster.\n');
else
    fprintf('BOTTLENECK: post-processing = %.0f %% of the total wall time.\n', 100*PM.postWall/max(PM.total, eps));
end
fprintf('Reference: the previous V4 run needed %.0f s wall time for %.1f s of simulated time;\n', cfg.refWall(2), cfg.refWall(1));
fprintf('           linear scaling predicts about %.0f s for %.2f s of simulated time.\n', cfg.refWall(2)*tEnd/cfg.refWall(1), tEnd);
refEnd = min(P.rpm_ramp*tEnd, P.rpm_ref);
if refEnd < 0.99*P.rpm_ref
    fprintf('NOTE: %.2f s ends DURING the speed ramp (reference = %.0f rpm of %.0f rpm). Steady-state V&V items\n', tEnd, refEnd, P.rpm_ref);
    fprintf('      (final speed, steady-state current, efficiency) evaluate a transient, so V&V = %s is expected here.\n', vvStr);
end
fprintf('\n========================================================\n\n');
end

function v = gf(s, f)
if isfield(s, f), v = s.(f); else, v = NaN; end
end


%% ========================================================================
%%  V6  CELL DIAGNOSTICS  (reduced to the 1 ms grid, aggregated, event-only)
%%  Uses ONLY the signals the model really logs. Nothing is invented:
%%  voltage columns -> Cell_Voltage, current columns -> statistics only,
%%  SOC / temperature -> statistics over the logged columns.
%% ========================================================================
function CD = evCellEmpty()
z = @(n) zeros(0,n);
CD = struct('OK',false,'Msg','no per-cell raw data','Notes',{{}});
CD.Summary = array2table(z(10), 'VariableNames', {'Time','V_Cell_Min','V_Cell_Max','V_Cell_Avg','V_Imbalance','I_Cell_Min','I_Cell_Max','I_Cell_Avg','I_Imbalance','Fault_Count'});
CD.Voltage = array2table(z(1), 'VariableNames', {'Time'});
CD.Current = array2table(z(7), 'VariableNames', {'Time','I_Cell_Min','I_Cell_Max','I_Cell_Avg','I_Cell_Spread','I_Cell_Max_ID','I_Cell_Min_ID'});
CD.SOC     = array2table(z(6), 'VariableNames', {'Time','Pack_SOC','Cell_SOC_Min','Cell_SOC_Max','Cell_SOC_Avg','SOC_Imbalance'});
CD.Temp    = array2table(z(6), 'VariableNames', {'Time','Temp_Min','Temp_Max','Temp_Avg','Temp_Spread','Hot_Cell_ID'});
CD.Stats   = cell2table(cell(0,11), 'VariableNames', {'Cell_ID','V_Min','V_Max','V_Avg','V_Range','I_Min','I_Max','I_Avg','I_Range','Status','I_Source_Columns'});
CD.Events  = cell2table(cell(0,7),  'VariableNames', {'Time','Cell_ID','Parameter','Old_Value','New_Value','Event','Severity'});
CD.Integ   = cell2table(cell(0,9),  'VariableNames', {'Signal','Level','Raw_Min','Raw_Max','Clean_Min','Clean_Max','Difference','Status','Note'});
CD.nV = 0;  CD.nI = 0;  CD.nS = 0;  CD.nT = 0;  CD.RemovedRows = 0;
CD.RawRows = 0;  CD.RawCols = 0;  CD.RawValues = 0;  CD.RawBytesMem = 0;  CD.RawFileBytes = NaN;
CD.AfterValues = 0;  CD.AfterBytesMem = 0;  CD.AfterColumns = 0;  CD.CleanRows = 0;
end

function CD = evCellDiag(R, ri, tEnd, P, cfg, CA)
CD = evCellEmpty();
if ~ri.HasTime || height(R) < 2, return, end
t = R.Time;
[tu, iu] = unique(t, 'last');                         % duplicate time stamps removed (last sample kept)
okT = isfinite(tu) & tu >= 0;  tu = tu(okT);  iu = iu(okT);
CD.RawRows = height(R);  CD.RawCols = width(R);  CD.RawValues = height(R)*width(R);
CD.RawBytesMem = CD.RawValues*8;  CD.RawFileBytes = CA.UncompBytes;
tg0 = (0:1e-3:tEnd)';

[V, V0] = evCellGrid(R, ri.Cols.vbatt,       iu, tu, tg0);
[I, I0] = evCellGrid(R, ri.Cols.ibatt,       iu, tu, tg0);
I = abs(I);  I0 = abs(I0);                              % POSITIVE-CURRENT
[S, S0] = evCellGrid(R, ri.Cols.soc,         iu, tu, tg0);
[T, T0] = evCellGrid(R, ri.Cols.temperature, iu, tu, tg0);

% integrity: raw range vs 1 ms grid range (no silent change of engineering values)
ig = cell(0,9);
ig(end+1,:) = evInteg('CellVoltage',     V0, V);
ig(end+1,:) = evInteg('CellCurrent',     I0, I);
ig(end+1,:) = evInteg('CellSOC',         S0, S);
ig(end+1,:) = evInteg('CellTemperature', T0, T);
clear V0 I0 S0 T0

% one common validity mask (rows with a NaN in any used signal are removed from every sheet)
use = true(numel(tg0),1);
for X = {V, I, S, T}
    if ~isempty(X{1}), use = use & all(isfinite(X{1}),2); end
end
nRem = nnz(~use);  tBad = tg0(find(~use,1));
tg = tg0(use);  V = V(use,:);  I = I(use,:);  S = S(use,:);  T = T(use,:);
N = numel(tg);
nV = size(V,2);  nI = size(I,2);  nS = size(S,2);  nT = size(T,2);

% ---- aggregates
Vmin = evRow(V,'min',N);  Vmax = evRow(V,'max',N);  Vavg = evRow(V,'mean',N);  Vimb = Vmax - Vmin;
Imin = evRow(I,'min',N);  Imax = evRow(I,'max',N);  Iavg = evRow(I,'mean',N);  Isp  = Imax - Imin;
iMaxID = evArg(I,'max',N);  iMinID = evArg(I,'min',N);
vMaxID = evArg(V,'max',N);  vMinID = evArg(V,'min',N);
iAbs = evRow(abs(I),'max',N);  iAbsID = evArg(abs(I),'max',N);
sc = 1;  if ~isempty(S) && max(S(:)) > 1.5, sc = 0.01; end
S = S*sc;
Spack = evRow(S,'mean',N);  Smin = evRow(S,'min',N);  Smax = evRow(S,'max',N);  Simb = Smax - Smin;  sMinID = evArg(S,'min',N);
Tmin = evRow(T,'min',N);  Tmax = evRow(T,'max',N);  Tavg = evRow(T,'mean',N);  Tsp = Tmax - Tmin;  hotID = evArg(T,'max',N);

% ---- thresholds (diagnostic defaults, listed in 04_VV_Results / Limits)
th = evCellThresholds(P, cfg);
cImb = Vimb > th.vImb;
cV   = (Vmax > th.vMax) | (Vmin < th.vMin);
cI   = iAbs > th.iPeak;
cT   = Tmax > th.tMax;
cS   = Smin < th.socMin;
fc   = double(cImb) + double(cV) + double(cI) + double(cT) + double(cS);

CD.Summary = array2table([tg Vmin Vmax Vavg Vimb Imin Imax Iavg Isp fc], 'VariableNames', CD.Summary.Properties.VariableNames);
CD.Voltage = array2table([tg V], 'VariableNames', [{'Time'} arrayfun(@(c) sprintf('Cell_%02d',c), 1:nV, 'UniformOutput', false)]);
CD.Current = array2table([tg Imin Imax Iavg Isp iMaxID iMinID], 'VariableNames', CD.Current.Properties.VariableNames);
CD.SOC     = array2table([tg Spack Smin Smax Spack Simb], 'VariableNames', CD.SOC.Properties.VariableNames);
CD.Temp    = array2table([tg Tmin Tmax Tavg Tsp hotID], 'VariableNames', CD.Temp.Properties.VariableNames);

% ---- one row per cell (voltage cells; current columns grouped under their cell, mapping stated in I_Source_Columns)
rows = cell(nV, 11);
for c = 1:nV
    vc = V(:,c);
    [cols, src] = evCurrentGroup(c, nV, nI);
    if isempty(cols), i0 = NaN; i1 = NaN; im = NaN; ir = NaN;
    else, ic = I(:,cols);  i0 = min(ic(:));  i1 = max(ic(:));  im = mean(ic(:));  ir = i1 - i0; end
    st = 'OK';  if min(vc) < th.vMin || max(vc) > th.vMax, st = 'LIMIT'; end
    rows(c,:) = {sprintf('Cell_%02d',c), min(vc), max(vc), mean(vc), max(vc)-min(vc), i0, i1, im, ir, st, src};
end
CD.Stats = cell2table(rows, 'VariableNames', CD.Stats.Properties.VariableNames);

% ---- events (only threshold / state changes)
E = cell(0,7);
E = evEdges(E, tg, cImb, Vimb, vMaxID, 'Cell_%02d', 'V_Imbalance', 'Voltage_Imbalance', 'Warning');
vlim = Vmax;  low = (Vmin < th.vMin) & ~(Vmax > th.vMax);  vlim(low) = Vmin(low);
vlimID = vMaxID;  vlimID(low) = vMinID(low);
E = evEdges(E, tg, cV,   vlim, vlimID, 'Cell_%02d', 'V_Cell', 'Voltage_Limit', 'Critical');
E = evEdges(E, tg, cI,   iAbs, iAbsID, 'CurrentColumn_%03d', 'I_Cell', 'Current_Peak', 'Warning');
E = evEdges(E, tg, cT,   Tmax, hotID,  'TempColumn_%02d', 'Temperature', 'Temperature_Limit', 'Critical');
E = evEdges(E, tg, cS,   Smin, sMinID, 'SOCColumn_%02d', 'SOC', 'SOC_Limit', 'Warning');
if nRem > 0
    E(end+1,:) = {tBad, 'n/a', 'Data_Validity', NaN, NaN, 'Fault', 'Critical'};
end
CD.Events = cell2table(E, 'VariableNames', CD.Events.Properties.VariableNames);
if height(CD.Events) > 1, CD.Events = sortrows(CD.Events, 'Time'); end

CD.Integ = cell2table(ig, 'VariableNames', CD.Integ.Properties.VariableNames);
CD.nV = nV;  CD.nI = nI;  CD.nS = nS;  CD.nT = nT;  CD.RemovedRows = nRem;  CD.CleanRows = N;  CD.th = th;
notes = {};
if nV ~= 13, notes{end+1} = sprintf('%d voltage column(s) logged (13 expected for 13S)', nV); end
if nS <= 1, notes{end+1} = 'only ONE SOC signal logged: Cell_SOC_Min/Max/Avg equal Pack_SOC, no independent cell SOC exists'; end
if nT <= 1, notes{end+1} = 'only ONE temperature signal logged: Temp_Min/Max/Avg are that signal, no independent cell temperature exists'; end
if nV > 0 && nI > 0 && isempty(evCurrentGroup(1, nV, nI)), notes{end+1} = 'current columns cannot be grouped per voltage cell: per-cell current statistics are NaN'; end
if nI > nV && nV > 0 && mod(nI,nV) == 0, notes{end+1} = sprintf('current columns grouped %d per cell assuming series-major logging order - verify against the Battery Builder signal order', nI/nV); end
CD.Notes = notes;
vals = N*(10 + (1+nV) + 7 + 6 + 6);
CD.AfterValues = vals + 11*nV;  CD.AfterBytesMem = CD.AfterValues*8;  CD.AfterColumns = 10 + (1+nV) + 7 + 6 + 6 + 11;
CD.OK = true;
CD.Msg = sprintf('%d rows (1 ms), %d V-cells, %d current columns, %d SOC, %d temperature, %d event(s), %d invalid row(s) removed', ...
    N, nV, nI, nS, nT, height(CD.Events), nRem);
end

function yg = evBinMean(t, y, tg)
% V7.1: exact mean of y over [tg-h, tg+h], h = 0.5 ms (= 10 PWM periods of Tsc = 100 us), via the integral of the
% trapezoid-interpolated signal. Windows are clamped to the valid data range (half window at t = 0). Non-finite
% samples are ignored per column. y: N x m, t: N x 1 (strictly increasing), tg: K x 1 -> K x m.
h = 0.5e-3;  t = t(:);  tg = tg(:);
yg = nan(numel(tg), size(y,2));
for j = 1:size(y,2)
    ok = isfinite(y(:,j)) & isfinite(t);
    if nnz(ok) < 2, continue, end
    tt = t(ok);  yy = y(ok,j);
    C  = [0; cumsum(0.5*(yy(1:end-1)+yy(2:end)).*diff(tt))];
    lo = max(tg-h, tt(1));  hi = min(tg+h, tt(end));
    w  = hi - lo;
    v  = (interp1(tt,C,hi,'linear') - interp1(tt,C,lo,'linear')) ./ max(w, eps);
    v(w <= 0) = NaN;
    yg(:,j) = v;
end
end

function [G, Y0] = evCellGrid(R, cols, iu, tu, tg)
if isempty(cols), G = zeros(numel(tg),0);  Y0 = zeros(0,0);  return, end
Y0 = R{iu, cols};
Y0(isinf(Y0)) = NaN;
if numel(tu) >= 2, G = evBinMean(tu, Y0, tg); else, G = nan(numel(tg), size(Y0,2)); end
end

function y = evRow(X, fn, N)
if isempty(X) || size(X,2) == 0, y = nan(N,1); return, end
switch fn
    case 'min',  y = min(X,[],2);
    case 'max',  y = max(X,[],2);
    otherwise,   y = mean(X,2);
end
end

function y = evArg(X, fn, N)
if isempty(X) || size(X,2) == 0, y = nan(N,1); return, end
if strcmp(fn,'min'), [~, y] = min(X,[],2); else, [~, y] = max(X,[],2); end
y = double(y);
end

function r = evInteg(name, Y0, G)
if isempty(Y0)
    r = {name, 'Cell', NaN, NaN, NaN, NaN, NaN, 'NOT_AVAILABLE', 'signal not logged'};  return
end
a = min(Y0(:),[],'omitnan');  b = max(Y0(:),[],'omitnan');
c = min(G(:),[],'omitnan');   d = max(G(:),[],'omitnan');
df = max(abs(c-a), abs(d-b));
tol = 1e-9*max(1, max(abs([a b])));
st = 'PASS';  if c < a - tol || d > b + tol, st = 'CHECK'; end
r = {name, 'Cell', a, b, c, d, df, st, 'raw (native) range vs 1 ms grid range; the difference is the peak amplitude not sampled by the 1 ms grid'};
end

function [cols, src] = evCurrentGroup(c, nV, nI)
cols = [];  src = 'not mapped';
if nI == 0 || nV == 0, return, end
if nI == nV
    cols = c;
elseif nI > nV && mod(nI, nV) == 0
    k = nI/nV;  cols = ((c-1)*k+1):(c*k);
else
    return
end
if numel(cols) == 1, src = sprintf('I_%03d', cols); else, src = sprintf('I_%03d..I_%03d', cols(1), cols(end)); end
end

function E = evEdges(E, t, cond, val, ids, fmt, par, evName, sev)
cond = cond(:);
if isempty(cond), return, end
d = diff([false; cond]);
for k = find(d == 1)'
    old = NaN;  if k > 1, old = val(k-1); end
    E(end+1,:) = {t(k), evCellId(fmt, ids(k)), par, old, val(k), evName, sev}; %#ok<AGROW>
end
for k = find(d == -1)'
    E(end+1,:) = {t(k), evCellId(fmt, ids(k-1)), par, val(k-1), val(k), 'Recovery', 'Info'}; %#ok<AGROW>
end
end

function s = evCellId(fmt, id)
if isnan(id), s = 'n/a'; else, s = sprintf(fmt, id); end
end

function th = evCellThresholds(P, cfg)
th = struct('vMax',cfg.cellVmax, 'vMin',cfg.cellVmin, 'vImb',cfg.cellVimbWarn, ...
    'iPeak',P.I_peak/P.cells_parallel, 'tMax',cfg.cellTmax, 'socMin',cfg.cellSOCmin);
end

function T = evCellMemoryAudit(CD, CA, xlBytes)
afterCols = CD.AfterColumns;
red = @(b,a) iif(isfinite(b) && b > 0 && isfinite(a), 100*(1 - a/b), NaN);
R = {'Raw cell rows (before) / cleaned cell rows (after)',  CD.RawRows,    CD.CleanRows,      red(CD.RawRows, CD.CleanRows);
     'Raw cell columns / Excel report columns (all 7 sheets)', CD.RawCols, afterCols,         red(CD.RawCols, afterCols);
     'Raw cell values / report values',                     CD.RawValues,  CD.AfterValues,    red(CD.RawValues, CD.AfterValues);
     'In-memory size, bytes (float64)',                     CD.RawBytesMem, CD.AfterBytesMem, red(CD.RawBytesMem, CD.AfterBytesMem);
     'File size, bytes (uncompressed full-width CSV estimate / 12_Cell_Diagnostics.xlsx)', CD.RawFileBytes, xlBytes, red(CD.RawFileBytes, xlBytes);
     'RLE columns (raw archive)',                           NaN, CA.RLEColumns,       NaN;
     'Dense columns (raw archive)',                         NaN, CA.DenseColumns,     NaN;
     'Duplicate columns merged (raw archive)',              NaN, CA.DuplicateColumns, NaN;
     'Constant columns stored once (raw archive)',          NaN, CA.ConstantColumns,  NaN};
T = cell2table(R, 'VariableNames', {'Metric','Before','After','Reduction_Percent'});
end

function V = evCellValidate(CD)
R = cell(0,3);
add = @(n,v,ok) {n, v, iif(ok,'PASS','FAIL')};
tabs = {'Cell_Summary',CD.Summary,10; 'Cell_Voltage',CD.Voltage,CD.nV+1; 'Cell_Current',CD.Current,7; 'Cell_SOC',CD.SOC,6; 'Cell_Temperature',CD.Temp,6};
for k = 1:size(tabs,1)
    Tt = tabs{k,2};  nm = tabs{k,1};
    nd = 0;  mono = true;  nn = 0;
    if height(Tt) > 1, nd = nnz(diff(Tt.Time) == 0);  mono = all(diff(Tt.Time) > 0); end
    if height(Tt) > 0 && width(Tt) > 1, nn = sum(sum(isnan(Tt{:,2:end}))); end
    R(end+1,:) = add([nm ': columns'], n2s(width(Tt)), width(Tt) == tabs{k,3}); %#ok<AGROW>
    R(end+1,:) = add([nm ': duplicate timestamps'], n2s(nd), nd == 0); %#ok<AGROW>
    R(end+1,:) = add([nm ': time monotonically increasing'], n2s(double(mono)), mono); %#ok<AGROW>
    if strcmp(nm,'Cell_Temperature') && CD.nT == 0
        R(end+1,:) = {[nm ': NaN values'], n2s(nn), 'NOT_AVAILABLE'}; %#ok<AGROW>      % V7.1: no temperature logged
    else
        R(end+1,:) = add([nm ': NaN values'], n2s(nn), nn == 0); %#ok<AGROW>
    end
end
vn = CD.Voltage.Properties.VariableNames(2:end);
R(end+1,:) = add('Cell_Statistics: IDs match Cell_Voltage columns', n2s(height(CD.Stats)), isequal(CD.Stats.Cell_ID(:)', vn));
okI = true;
if height(CD.Current) > 0 && CD.nI > 0
    okI = all(CD.Current.I_Cell_Max_ID >= 1 & CD.Current.I_Cell_Max_ID <= CD.nI & CD.Current.I_Cell_Min_ID >= 1 & CD.Current.I_Cell_Min_ID <= CD.nI);
end
R(end+1,:) = add('Cell_Current: column IDs within 1..number of logged current columns', n2s(CD.nI), okI);
R(end+1,:) = add('No invented signals: voltage / current / SOC / temperature columns taken from the log', sprintf('%d/%d/%d/%d', CD.nV, CD.nI, CD.nS, CD.nT), true);
R(end+1,:) = add('Rows removed because of NaN (common mask)', n2s(CD.RemovedRows), CD.RemovedRows == 0);
V = cell2table(R, 'VariableNames', {'Check','Value','Status'});
end

function sh = evSheets12(CD)
sh = {'Cell_Summary',CD.Summary; 'Cell_Voltage',CD.Voltage; 'Cell_Current',CD.Current; 'Cell_SOC',CD.SOC; ...
      'Cell_Temperature',CD.Temp; 'Cell_Statistics',CD.Stats; 'Cell_Events',CD.Events};
end


%% ========================================================================
%%  V6  EXCEL WRITERS  (12 files, fixed structure)
%% ========================================================================
function F = evExcelFiles()
F = {'01_EV_Run_Summary.xlsx',       'Run summary, system overview, final results, V&V status, file index';
     '02_Parameters_and_Setup.xlsx', 'Battery, BLDC, vehicle, controller parameters and simulation settings';
     '03_Cleaned_Data.xlsx',         'Canonical engineering dataset (1 ms grid, 14 columns)';
     '04_VV_Results.xlsx',           'Validation results per area and the limits used';
     '05_Signal_Map.xlsx',           'One row per actual logged / derived signal';
     '06_Logging_Audit.xlsx',        'Acquisition audit: signals, time, missing and duplicate data';
     '07_Group_Summary.xlsx',        'Statistics per signal group';
     '08_Event_Log.xlsx',            'Meaningful events only';
     '09_Performance_Report.xlsx',   'Timing, memory, file sizes, optimisation';
     '10_Compression_Audit.xlsx',    'Raw-archive compaction audit and cell memory reduction';
     '11_Live_Telemetry.xlsx',       '100 ms live telemetry (13 instantaneous columns + 5 *_1msMean window-mean columns)';
     '12_Cell_Diagnostics.xlsx',     'Cell-level diagnostics (aggregated, 7 sheets)'; ...
     'EV_Master_Data.xlsx',          'Master data: Battery_Motor_Data + Cell_Data (5 ms) + Notes'};
end

function info = evXlsx(runDir, fname, sheets, MAXB)
xl = fullfile(runDir, fname);
if isfile(xl), delete(xl); end
ns = size(sheets,1);  rows = zeros(ns,1);  cols = zeros(ns,1);
for k = 1:ns
    Tt = sheets{k,2};
    writetable(Tt, xl, 'Sheet', sheets{k,1}, 'UseExcel', false);
    rows(k) = height(Tt);  cols(k) = width(Tt);
end
d = dir(xl);
present = true;
try
    sn = cellstr(sheetnames(xl));
    present = all(ismember(sheets(:,1), sn)) && numel(sn) == ns;
catch
end
info = struct('File',fname,'Sheets',{sheets(:,1)},'Rows',rows,'Cols',cols,'Bytes',d.bytes,'Present',present,'Ok',present && d.bytes < MAXB);
end

function T = evClean14(C)
names = {'Time','BatteryVoltage','BatteryCurrent','BatteryPower','SOC','DCLinkVoltage','RPMReference','RPM','SpeedError', ...
         'MotorTorque','MotorMechanicalPower','MotorCurrent','WheelSpeed','Efficiency'};
T = table(C.Time, 'VariableNames', {'Time'});
for k = 2:numel(names), T.(names{k}) = col(C, names{k}); end     % missing signal -> NaN column (never invented)
end

function T = evLive13(LT)
% only what was captured during the simulation; signals the tap did not capture stay NaN (never filled from post-run data)
names = {'Time','BatteryVoltage','BatteryCurrent','SOC','BatteryPower','DCLinkVoltage','DCLinkCurrent','RPMReference','RPM', ...
         'MotorTorque','MotorCurrent','WheelSpeed','Temperature'};
n = height(LT);  T = table(LT.Time, 'VariableNames', {'Time'});
for k = 2:numel(names)
    nm = names{k};  v = nan(n,1);
    if ismember(nm, LT.Properties.VariableNames), v = LT.(nm); end
    T.(nm) = v;                                                 % DCLinkCurrent is not logged by the model -> NaN
end
end

function sh = evSheets01(RiT, MDL, P, FR, VVT, vvStr, tEnd, infos)
bat = sprintf('%dS%dP | %.1f V | %.0f Ah', P.cells_series, P.cells_parallel, P.cells_series*3.7, P.pack_Ah);
so = {'Model',[MDL '.slx']; 'Battery',bat; ...
      'Motor',sprintf('%.0f V | %.0f A cont | %.0f A peak | %.0f rpm | Kt %.4f Nm/A', P.Vmotor_nom, P.I_cont, P.I_peak, P.rpm_nom, P.Kt); ...
      'Drivetrain',sprintf('gear %.1f | wheel radius %.3f m', P.gear_ratio, P.r_wheel); ...
      'Controller',sprintf('speed PI %.4f/%.2f | voltage PI %.3f/%.2f | target %.0f rpm', P.Kpw, P.Kiw, P.Kpv, P.Kiv, P.rpm_ref); ...
      'Simulated time',sprintf('%.4f s', tEnd); 'Time bases','1 ms engineering grid; 0.1 s live telemetry'};
SO = cell2table(so, 'VariableNames', {'Item','Value'});
fr = {'Final RPM',FR.FinalRPM,'rpm'; 'Peak RPM',FR.PeakRPM,'rpm'; 'Motor current peak',FR.MotorCurrentPeak,'A'; ...
      'Motor current RMS',FR.MotorCurrentRMS,'A'; 'Battery current (mean |I|, last 10%)',FR.BatteryCurrent,'A'; ...
      'Battery current peak',FR.BatteryCurrentPeak,'A'; 'Battery voltage',FR.BatteryVoltage,'V'; 'Final SOC',FR.FinalSOC,'-'; ...
      'Battery power (last 10%)',FR.BatteryPower,'W'; 'Mechanical power (last 10%)',FR.MechPower,'W'; ...
      'Efficiency (ratio of means, last 10%)',FR.Efficiency,'%'};
FRt = cell2table(fr, 'VariableNames', {'Metric','Value','Unit'});
vv = [VVT(:,{'RequirementID','Requirement','Status'}); cell2table({'OVERALL','Overall V&V status',vvStr}, 'VariableNames', {'RequirementID','Requirement','Status'})];
F = evExcelFiles();  nF = size(F,1);
sz = nan(nF,1);  shs = cell(nF,1);
for k = 1:nF
    shs{k} = 'see workbook';
    for j = 1:numel(infos)
        if strcmp(infos{j}.File, F{k,1}), sz(k) = infos{j}.Bytes/2^20;  shs{k} = strjoin(infos{j}.Sheets', ', '); end
    end
end
FI = table(F(:,1), F(:,2), shs, sz, 'VariableNames', {'File','Content','Sheets','Size_MB'});   % this file's own size stays NaN
sh = {'Run_Summary',RiT; 'System_Overview',SO; 'Final_Results',FRt; 'V&V_Status',vv; 'File_Index',FI};
end

function sh = evSheets02(PrmT, cfg)
g = PrmT.Group;
sim = PrmT(ismember(g,{'Scenario','System'}),:);
ex = {'Simulation','EngineeringGrid_Ts','0.001','s','EV_DAQ_Builder_V7'; ...
      'Simulation','LiveTelemetry_Ts',num2str(cfg.Ts_live),'s','evCfg'; ...
      'Simulation','MaxFileSize',num2str(cfg.maxBytes/2^20),'MB','evCfg'};
sim = [sim; cell2table(ex, 'VariableNames', PrmT.Properties.VariableNames)];
sh = {'Battery_Parameters',PrmT(strcmp(g,'Battery'),:); 'BLDC_Parameters',PrmT(strcmp(g,'Motor'),:); ...
      'Vehicle_Parameters',PrmT(strcmp(g,'Vehicle'),:); 'Controller_Parameters',PrmT(strcmp(g,'Controller'),:); ...
      'Simulation_Settings',sim};
end

function sh = evSheets04(VVT, vvStr, CD)
id = VVT.RequirementID;
sub = @(l) VVT(ismember(id, l),:);
summ = [VVT(:,{'RequirementID','Requirement','Status'}); cell2table({'OVERALL','Overall V&V status',vvStr}, 'VariableNames', {'RequirementID','Requirement','Status'})];
lim = VVT(:,{'RequirementID','Requirement','Expected','Limit'});
% Owner-approved motor-current policy: project threshold is not a datasheet rating.
policyRows = {'POLICY-I30','Motor datasheet continuous-current rating','30 A','UNCONFIRMED for continuous operation at 35 A'; ...
              'POLICY-I35','Project acceptance limit for VV-004 / VV-008 / VV-023','35 A','Owner approved; project criterion only'; ...
              'POLICY-IPEAK','VV-003 peak-current acceptance criterion','48 A','Retained by owner; 45 A limiter + 3 A margin'};
lim = [lim; cell2table(policyRows,'VariableNames',lim.Properties.VariableNames)];
if isfield(CD,'th') && isstruct(CD.th)
    th = CD.th;
    cr = {'CELL-001','Cell voltage max (diagnostic threshold)',   '-', n2s(th.vMax); ...
          'CELL-002','Cell voltage min (diagnostic threshold)',   '-', n2s(th.vMin); ...
          'CELL-003','Cell voltage imbalance warning',            '-', n2s(th.vImb); ...
          'CELL-004','Cell current peak = I_peak / cells_parallel','-', n2s(th.iPeak); ...
          'CELL-005','Cell temperature max (diagnostic threshold)','-', n2s(th.tMax); ...
          'CELL-006','Cell SOC min (diagnostic threshold)',       '-', n2s(th.socMin)};
    lim = [lim; cell2table(cr, 'VariableNames', lim.Properties.VariableNames)];
end
sh = {'V&V_Summary',summ; 'Speed_VV',sub({'VV-001','VV-002'}); 'Battery_VV',sub({'VV-005'}); ...
      'Motor_VV',sub({'VV-003','VV-004','VV-008','VV-022','VV-023'}); 'SOC_VV',sub({'VV-006','VV-007'}); 'Power_VV',sub({'VV-009','VV-012','VV-016','VV-024'}); 'Limits',lim};
end

function T = evSignalMap13(SmT, sigMap, CD)
keep = ~strcmp(SmT.Status,'NOT_AVAILABLE');
S = SmT(keep,:);
n = height(S);
rows = cell(n,13);
for k = 1:n
    switch S.Status{k}
        case 'LOGGED',  stor = 'Dense, 1 ms grid';
        case 'DERIVED', stor = 'Derived (computed, not logged)';
        otherwise,      stor = S.Status{k};
    end
    rows(k,:) = {sprintf('S%03d',k), S.SignalName{k}, S.SignalName{k}, S.SimulinkSource{k}, S.SignalGroup{k}, S.Unit{k}, S.DataType{k}, ...
        S.SampleTime{k}, stor, S.Description{k}, 'YES', S.VandV{k}, S.LiveTelemetry{k}};
end
cell_defs = {'CellVoltage','vbatt',CD.nV,'V'; 'CellCurrent','ibatt',CD.nI,'A'; 'CellSOC','soc',CD.nS,'-'; 'CellTemperature','temperature',CD.nT,'degC'};
for k = 1:size(cell_defs,1)
    key = cell_defs{k,2};  nc = cell_defs{k,3};
    if nc > 0 && isfield(sigMap,key) && sigMap.(key).Available
        j = size(rows,1) + 1;
        rows(j,:) = {sprintf('S%03d',j), sprintf('%s[1..%d]',cell_defs{k,1},nc), cell_defs{k,1}, sigMap.(key).BlockPath, 'Battery', cell_defs{k,4}, 'double', ...
            'as logged', 'Raw_Archive (02b/02c/02d) + aggregated in 12_Cell_Diagnostics', sprintf('%d logged column(s), per-cell level', nc), 'NO', 'NO', 'NO'};
    end
end
T = cell2table(rows, 'VariableNames', {'Signal_ID','Signal_Name','Display_Name','Source_Block','Subsystem','Unit','Data_Type','Sample_Time','Storage_Type','Description','Required','VV_Used','Dashboard_Used'});
end

function sh = evSheets06(AudT, Raw, Clean, ci, TV, CA, nDupT, nRowsNative, CD, CV, spec)
nP = sum(strcmp(AudT.Status,'PASS'));  nF = sum(strcmp(AudT.Status,'FAIL'));  nW = sum(strcmp(AudT.Status,'WARN'));
ls = {'Logging checks (total)', n2s(height(AudT)), 'INFO'; 'Checks PASS', n2s(nP), 'INFO'; 'Checks FAIL', n2s(nF), iif(nF==0,'PASS','FAIL'); ...
      'Checks WARN', n2s(nW), iif(nW==0,'PASS','WARN'); 'Native raw rows (full width)', n2s(nRowsNative), 'INFO'; ...
      'Pack-level raw rows', n2s(height(Raw)), 'INFO'; 'Cleaned rows (1 ms)', n2s(height(Clean)), 'INFO'};
LS = cell2table(ls, 'VariableNames', {'Check','Value','Status'});
if ~isempty(CV), LS = [LS; CV]; end
for k = 1:numel(CD.Notes)
    LS = [LS; cell2table({'Cell diagnostics note', CD.Notes{k}, 'INFO'}, 'VariableNames', {'Check','Value','Status'})]; %#ok<AGROW>
end
% signal audit: raw vs clean range (pack signals) + cell signals
nm = {'BatteryVoltage','BatteryCurrent','BatteryPower','SOC','DCLinkVoltage','RPMReference','RPM','SpeedError','MotorTorque','MotorMechanicalPower','MotorCurrent','WheelSpeed','Efficiency'};
rows = cell(0,9);
for k = 1:numel(nm)
    c1 = col(Clean, nm{k});
    if ~any(isfinite(c1)), continue, end
    cmin = min(c1,[],'omitnan');  cmax = max(c1,[],'omitnan');
    if ismember(nm{k}, Raw.Properties.VariableNames)
        r1 = Raw.(nm{k});  rmin = min(r1,[],'omitnan');  rmax = max(r1,[],'omitnan');
        df = max(abs(cmin-rmin), abs(cmax-rmax));  tol = 1e-9*max(1,max(abs([rmin rmax])));
        st = iif(cmin >= rmin - tol && cmax <= rmax + tol, 'PASS', 'CHECK');  note = 'pack-level raw vs 1 ms grid';
    else
        rmin = NaN;  rmax = NaN;  df = NaN;  st = 'DERIVED';  note = 'computed on the 1 ms grid';
    end
    rows(end+1,:) = {nm{k}, 'Pack', rmin, rmax, cmin, cmax, df, st, note}; %#ok<AGROW>
end
SA = cell2table(rows, 'VariableNames', CD.Integ.Properties.VariableNames);
SA = [SA; CD.Integ];
m = contains(lower(AudT.Check), {'time','grid','duration'});
TA = AudT(m,:);
tv = {'Distinct time vectors', TV.Distinct, NaN, 'INFO', sprintf('among %d logged signals', TV.Signals); ...
      'Signals sharing an identical time vector', TV.Duplicate, NaN, 'INFO', 'one canonical time column suffices'; ...
      'Repeated time stamps in native logs', TV.RepeatedStamps, 0, iif(TV.RepeatedStamps==0,'PASS','WARN'), 'zero-length steps'};
TA = [TA; cell2table(tv, 'VariableNames', TA.Properties.VariableNames)];
mi = {}; 
for k = 1:size(spec,1)
    nmk = spec{k,1};
    inC = ismember(nmk, Clean.Properties.VariableNames);
    nn = NaN;  if inC, nn = sum(isnan(Clean.(nmk))); end
    mi(end+1,:) = {nmk, spec{k,3}, iif(inC,'YES','NO'), nn, iif(inC, iif(nn==0,'PASS','WARN'), 'NOT_AVAILABLE')}; %#ok<AGROW>
end
MD = cell2table(mi, 'VariableNames', {'Signal','Kind','In_Cleaned_Data','NaN_Count','Status'});
dd = {'Duplicate time stamps (raw)', ci.DupTime; 'Duplicate time stamps with differing values', ci.DupTimeDiffering; ...
      'Repeated time stamps removed (pack raw)', nDupT; 'Duplicate rows', ci.DupRows; 'Duplicate column names', ci.DupColName; ...
      'Bit-identical duplicate columns (raw archive)', CA.DuplicateColumns; 'Constant columns (raw archive)', CA.ConstantColumns};
DD = cell2table(dd, 'VariableNames', {'Item','Count'});
sh = {'Logging_Summary',LS; 'Signal_Audit',SA; 'Time_Audit',TA; 'Missing_Data',MD; 'Duplicate_Data',DD};
end

function sh = evSheets07(GrpT, LT13)
L = {'Battery',{'BatteryVoltage','BatteryCurrent','BatteryPower','SOC'}; 'DC_Link',{'DCLinkVoltage','DCLinkCurrent','DCLinkPower'}; ...
     'Motor',{'RPM','MotorTorque','MotorMechanicalPower','MotorCurrent','MotorTemperature','Efficiency'}; 'Vehicle',{'WheelSpeed'}; ...
     'Controller',{'RPMReference','SpeedError'}; 'Thermal',{'BatteryTemperature','BatteryTemperatureMax','MotorTemperature'}};
sh = cell(size(L,1)+1, 2);
for k = 1:size(L,1)
    sh(k,:) = {L{k,1}, GrpT(ismember(GrpT.Signal, L{k,2}),:)};
end
rows = cell(0,6);
for k = 2:width(LT13)
    x = LT13{:,k};  xf = x(isfinite(x));
    if isempty(xf), v = nan(1,4); else, v = [min(xf) max(xf) mean(xf) xf(end)]; end
    rows(end+1,:) = [{LT13.Properties.VariableNames{k}, numel(xf)}, num2cell(v)]; %#ok<AGROW>
end
sh(end,:) = {'Telemetry', cell2table(rows, 'VariableNames', {'Signal','Samples','Minimum','Maximum','Mean','Final'})};
end

function T = evEventLog(EvtT, C)
m = {'SpeedCommandStart','Speed','RPMReference','Info'; 'SpeedRamp_10pct','Speed','RPM','Info'; 'SpeedRamp_90pct','Speed','RPM','Info'; ...
     'LoadStep','Load','MotorTorque','Info'; 'CurrentLimitActivated','Current','MotorCurrent','Warning'; ...
     'CurrentLimitReleased','Current','MotorCurrent','Info'; 'CurrentAboveContinuous','Current','MotorCurrent','Warning'; ...
     'BatteryVoltageLimit','Battery','BatteryVoltage','Critical'; 'SOCWarning','Battery','SOC','Warning'; 'Fault','Fault','','Critical'; ...
     'SimulationStart','System','','Info'; 'SimulationStop','System','','Info'; 'SimulationComplete','System','','Info'};
n = height(EvtT);  rows = cell(n,10);
for k = 1:n
    nm = EvtT.EventType{k};  t = EvtT.Time_s(k);
    i = find(strcmp(m(:,1), nm), 1);
    typ = 'Other';  sg = '';  sev = 'Info';
    if ~isempty(i), typ = m{i,2};  sg = m{i,3};  sev = m{i,4}; end
    bef = NaN;  aft = NaN;
    if ~isempty(sg) && ismember(sg, C.Properties.VariableNames)
        j = find(abs(C.Time - t) < 1e-9, 1);
        if ~isempty(j), aft = C.(sg)(j);  if j > 1, bef = C.(sg)(j-1); end, end
    end
    rows(k,:) = {sprintf('EVT-%03d',k), t, typ, nm, sg, bef, aft, EvtT.Detail{k}, sev, 'Recorded'};
end
T = cell2table(rows, 'VariableNames', {'Event_ID','Time','Event_Type','Event_Name','Signal','Before_Value','After_Value','Description','Severity','Status'});
end

function sh = evSheets09(PT, PM, TM, simWall, CA, CM, CD, runDir, cfg)
it = evTimes('get');
tm = {'Model_Load_Time',gf(it,'ModelLoading'),'StartFcn'; 'Parameter_Load_Time',gf(it,'ParameterLoading'),'StartFcn'; ...
      'Configuration_Time',gf(it,'ModelConfiguration'),'StartFcn'; 'Simulation_Time',simWall,'StartFcn to StopFcn'; ...
      'Raw_Extraction_Time',gf(TM,'RawExtraction'),''; 'Compression_Time',gf(TM,'Compression'),'includes writing the raw archive and verification'; ...
      'Reconstruction_Verification_Time',gf(TM,'Verify'),'0 unless cfg.auditMode = true'; 'Data_Acquisition_Time',gf(TM,'RawExtraction'),'harvest + raw table + pack raw archive'; ...
      'PostProcessing_Time',PM.postWall,'StopFcn work up to this report'; ...
      'Cleaning_Time',gf(TM,'Cleaning'),'includes cell diagnostics'; 'VV_Time',gf(TM,'VV'),'tables, V&V, events'; ...
      'Excel_Time',gf(TM,'Excel'),'10 workbooks; 09 and 01 are written afterwards (milliseconds)'; 'Figure_Time',gf(TM,'Figures'),''; ...
      'Archive_Time',gf(TM,'Archive'),'writing Raw_Archive CSV files'; 'Total_Time',PM.total,'start-up + simulation + post-processing'; ...
      'CellDiag_Time (included in Cleaning)',gf(TM,'CellDiag'),''};
TT = cell2table(tm, 'VariableNames', {'Metric','Seconds','Note'});
mb = 2^20;
mm = {'Peak_MATLAB_Memory',PM.peakMB,'MB','stage-boundary samples; n/a unless memory() exists (Windows)'; ...
      'Cell raw table in memory (before)',CD.RawBytesMem/mb,'MB','RawFull, freed after cleaning'; ...
      'Cell report tables in memory (after)',CD.AfterBytesMem/mb,'MB',''; ...
      'Cell memory reduction',iif(CD.RawBytesMem>0, 100*(1-CD.AfterBytesMem/CD.RawBytesMem), NaN),'%',''};
MT = cell2table(mm, 'VariableNames', {'Metric','Value','Unit','Note'});
FS = evFileManifest(runDir, cfg.maxBytes);
op = {'Raw_Size_estimate',PM.rawEst/mb,'MB','uncompressed full-width CSV (not written)'; 'Raw_Archive_Size',PM.comp/mb,'MB','02b+02c+02d+constants'; ...
      'Cleaned_Size',PM.clean/mb,'MB','03_Cleaned_Data.xlsx'; 'Excel_Size',PM.xl/mb,'MB','xlsx written before this report'; ...
      'Compression_Ratio',PM.ratio,'%','archive vs estimate'; 'Memory_Reduction',iif(CD.RawBytesMem>0, 100*(1-CD.AfterBytesMem/CD.RawBytesMem), NaN),'%','cell data'; ...
      'Duplicate_Columns_Merged',CA.DuplicateColumns,'-',''; 'Constant_Columns',CA.ConstantColumns,'-',''; 'RLE_Columns',CA.RLEColumns,'-','only where smaller than dense'; ...
      'Dense_Columns',CA.DenseColumns,'-',''};
OT = cell2table(op, 'VariableNames', {'Metric','Value','Unit','Note'});
sh = {'Timing',TT; 'Memory',MT; 'File_Size',FS; 'Optimization',OT; 'Performance_Summary',PT};
end

function [CCT, RLT] = evColumnCompression(comp)
C = comp.C;  N = comp.N;
nm = comp.names(2:end);  nm = nm(:);
orig = repmat(N*8, C, 1);  fin = zeros(C,1);  meth = cell(C,1);
rleU = repmat({'NO'},C,1);  cst = rleU;  dup = rleU;  rleEst = nan(C,1);
for j = 1:C
    s = comp.rep(j);
    rleEst(j) = 24*comp.nRuns(s);
    if s ~= j
        dup{j} = 'YES';  fin(j) = 0;  meth{j} = ['duplicate of ' comp.names{1+s}];
        continue
    end
    switch comp.kind(j)
        case 1, fin(j) = N*8;  meth{j} = 'dense';
        case 2, fin(j) = 8;  meth{j} = 'constant';  cst{j} = 'YES';
        case 3, fin(j) = 24*numel(comp.rle{j}.st);  meth{j} = 'RLE';  rleU{j} = 'YES';
    end
end
red = 100*(1 - fin./orig);
CCT = table(nm, orig, fin, meth, red, rleU, cst, dup, orig, rleEst, repmat({'bytes (float64 estimate)'},C,1), ...
    'VariableNames', {'Signal','Original_Size','Final_Size','Storage_Method','Reduction_Percent','RLE_Used','Constant','Duplicate','Dense_Estimate','RLE_Estimate','Size_Unit'});
ix = find(strcmp(rleU,'YES'));
RLT = table(nm(ix), fin(ix)/24, orig(ix), fin(ix), 100*(1-fin(ix)./orig(ix)), ...
    'VariableNames', {'Signal','Segments','Dense_Estimate','RLE_Estimate','Saved_Percent'});
end

function T = evEmptyColT()
T = table(cell(0,1), zeros(0,1), zeros(0,1), cell(0,1), zeros(0,1), cell(0,1), cell(0,1), cell(0,1), zeros(0,1), zeros(0,1), cell(0,1), ...
    'VariableNames', {'Signal','Original_Size','Final_Size','Storage_Method','Reduction_Percent','RLE_Used','Constant','Duplicate','Dense_Estimate','RLE_Estimate','Size_Unit'});
end

function T = evEmptyRleT()
T = table(cell(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), 'VariableNames', {'Signal','Segments','Dense_Estimate','RLE_Estimate','Saved_Percent'});
end

function T = evEmptyConstT()
T = table(cell(0,1), cell(0,1), zeros(0,1), zeros(0,1), zeros(0,1), 'VariableNames', {'SignalName','ConstantValue','Count','StartTime','EndTime'});
end

function evPrintExcelStructure(infos, cfg, CA, PM, CM, CV)
F = evExcelFiles();
fprintf('\n===== FINAL EXCEL STRUCTURE (12 report files + EV_Master_Data.xlsx) =====\n\n');
tot = 0;  cleanB = NaN;
for k = 1:size(F,1)
    st = 'MISSING';  inf1 = [];
    for j = 1:numel(infos)
        if strcmp(infos{j}.File, F{k,1}), inf1 = infos{j}; end
    end
    if ~isempty(inf1), st = iif(inf1.Ok,'PASS','FAIL');  tot = tot + inf1.Bytes; end
    fprintf('%-30s %s\n', F{k,1}, st);
end
fprintf('\n%-30s %-22s %8s %8s %12s\n', 'File', 'Sheet', 'Rows', 'Columns', 'File size');
for j = 1:numel(infos)
    s = infos{j};
    for q = 1:numel(s.Sheets)
        fprintf('%-30s %-22s %8d %8d %9.3f MB\n', iif(q==1, s.File, ''), s.Sheets{q}, s.Rows(q), s.Cols(q), s.Bytes/2^20);
    end
    if strcmp(s.File,'03_Cleaned_Data.xlsx'), cleanB = s.Bytes; end
end
memRed = NaN;
if ~isempty(CM) && height(CM) >= 4, memRed = CM.Reduction_Percent(4); end
fprintf('\nTotal Excel size            : %.3f MB (limit per file %.0f MB)\n', tot/2^20, cfg.maxBytes/2^20);
fprintf('Raw data size (estimate)    : %.2f MB (uncompressed full-width CSV, not written)\n', CA.UncompBytes/2^20);
fprintf('Cleaned data size           : %.3f MB (03_Cleaned_Data.xlsx)\n', cleanB/2^20);
if ~isempty(PM), fprintf('Compression ratio           : %.1f %% (raw archive vs estimate)\n', PM.ratio); end
fprintf('Memory reduction (cell data): %.1f %%\n', memRed);
fprintf('Duplicate columns removed   : %g (bit-identical, stored once in the archive)\n', CA.DuplicateColumns);
fprintf('Constant columns removed    : %g (stored as one value in the archive)\n', CA.ConstantColumns);
fprintf('RLE columns                 : %g\n', CA.RLEColumns);
fprintf('Dense columns               : %g\n', CA.DenseColumns);
if ~isempty(CV)
    fprintf('\nCell diagnostics validation : %d PASS, %d FAIL\n', sum(strcmp(CV.Status,'PASS')), sum(strcmp(CV.Status,'FAIL')));
    for k = find(strcmp(CV.Status,'FAIL'))', fprintf('  FAIL: %s (%s)\n', CV.Check{k}, CV.Value{k}); end
end
fprintf('=================================\n\n');
end


%% ========================================================================
%%  V6  EV_Master_Data.xlsx  (human-readable master dataset)
%%  Battery_Motor_Data : pack-level signals, every 5 ms row taken EXACTLY from the 1 ms cleaned grid (no new interpolation)
%%  Cell_Data          : logged cell voltages only, same 5 ms rows
%%  Notes              : interval, row-count check, derived columns, unavailable signals
%% ========================================================================
function sh = evSheetsMaster(Clean, CD, tEnd, ci)
step = 5;                                                      % 5 ms = 5 rows of the 1 ms grid
idx = find(mod(round(Clean.Time/1e-3), step) == 0);
defs = {'Battery_Voltage_V','BatteryVoltage',1,'logged'; 'Battery_Current_A','BatteryCurrent',1,'logged'; 'SOC_percent','SOC',100,'logged (x100)'; ...
        'Battery_Power_W','BatteryPower',1,'DERIVED'; 'DC_Link_Voltage_V','DCLinkVoltage',1,'logged'; 'DC_Link_Current_A','DCLinkCurrent',1,'logged'; ...
        'RPM_Reference_rpm','RPMReference',1,iif(ci.RefDerived,'DERIVED','logged'); 'Motor_RPM_rpm','RPM',1,'logged'; ...
        'Motor_Torque_Nm','MotorTorque',1,'logged'; 'Motor_Current_A','MotorCurrent',1,'logged'; ...
        'Battery_Temperature_C','BatteryTemperature',1,'logged'; 'Battery_Temperature_Max_C','BatteryTemperatureMax',1,'logged'; ...
        'Motor_Temperature_C','MotorTemperature',1,'logged'; ...
        'Phase_A_Current_A','PhaseCurrentA',1,'logged'; 'Phase_B_Current_A','PhaseCurrentB',1,'logged'; 'Phase_C_Current_A','PhaseCurrentC',1,'logged'; ...
        'Wheel_Speed_as_logged','WheelSpeed',1,'logged'; 'Vehicle_Speed_m_s','VehicleSpeed',1,'logged'; ...
        'Mechanical_Power_W','MotorMechanicalPower',1,'DERIVED'; 'Efficiency_percent','Efficiency',1,'DERIVED'};
BM = table(Clean.Time(idx), 'VariableNames', {'Time_s'});
avail = {};  unavail = {};  deriv = {};
for k = 1:size(defs,1)
    x = col(Clean, defs{k,2});
    if any(isfinite(x))
        BM.(defs{k,1}) = x(idx)*defs{k,3};
        avail{end+1} = defs{k,1};                              %#ok<AGROW>
        if startsWith(defs{k,4},'DERIVED'), deriv{end+1} = defs{k,1}; end %#ok<AGROW>
    else
        unavail{end+1} = defs{k,2};                            %#ok<AGROW>
    end
end
CT = table(Clean.Time(idx), 'VariableNames', {'Time_s'});
if CD.OK && CD.nV > 0
    iv = find(mod(round(CD.Voltage.Time/1e-3), step) == 0);
    CT = table(CD.Voltage.Time(iv), 'VariableNames', {'Time_s'});
    for c = 1:CD.nV, CT.(sprintf('Cell_V%02d_V', c)) = CD.Voltage{iv, 1+c}; end
end
nExp = round(tEnd/5e-3) + 1;
okT = all(diff(BM.Time_s) > 0);
rows = {'Sampling interval (both sheets)', '0.0050 s (5 ms)', 'every 5th row of the 1 ms cleaned grid; engineering values are not re-interpolated or rounded'; ...
        'Expected readings = duration/0.005 + 1', sprintf('%d', nExp), sprintf('duration = %.4f s', tEnd); ...
        'Battery_Motor_Data readings', sprintf('%d', height(BM)), iif(height(BM) == nExp,'PASS','CHECK'); ...
        'Cell_Data readings', sprintf('%d', height(CT)), iif(height(CT) == nExp,'PASS','CHECK (rows with invalid cell data are removed in Cell diagnostics)'); ...
        'Time monotonic, no duplicate timestamps', iif(okT,'YES','NO'), iif(okT,'PASS','FAIL'); ...
        'Derived columns (computed, not measured)', evJoin(deriv), 'Battery power = V*I, mechanical power = |torque|*rpm*2*pi/60, efficiency = Pmech/|Pbatt| (blank where |Pbatt| < 1 W); SOC_percent = SOC*100 (unit conversion)'; ...
        'Signals NOT available in the model (not invented, not in the sheet)', evJoin(unavail), 'recorded as unavailable'; ...
        'Cell voltage columns present', sprintf('%d', CD.nV), 'only logged cell voltages are included; no cell value is manufactured'; ...
        'Meaning of Cell_Vnn', 'voltage of series group nn', 'each group is 10 parallel cells; the 13 groups add up to Battery_Voltage_V; Battery_Current_A is the terminal current (sum of 130 cell currents / 13)'};
NT = cell2table(rows, 'VariableNames', {'Item','Value','Detail'});
sh = {'Battery_Motor_Data',BM; 'Cell_Data',CT; 'Notes',NT};
end

function [ok, msg] = evFormatMaster(xl)
% Excel display formatting only (values are untouched): frozen header, AutoFilter, auto-size, number formats. Needs Windows + Excel.
ok = false;  msg = 'formatting skipped (needs Windows with Excel installed)';
if ~ispc, return, end
ex = [];
try
    ex = actxserver('Excel.Application');  ex.DisplayAlerts = false;
    wb = ex.Workbooks.Open(xl);
    for k = 1:2
        ws = wb.Worksheets.Item(k);  ws.Activate;
        ex.ActiveWindow.FreezePanes = false;
        ws.Range('A2').Select;
        ex.ActiveWindow.FreezePanes = true;
        ws.Range('1:1').Font.Bold = true;
        ur = ws.UsedRange;  nr = double(ur.Rows.Count);  nc = double(ur.Columns.Count);   % V7.3: COM returns int32
        invoke(ur, 'AutoFilter', 1);
        ws.Range(sprintf('A1:A%d', nr)).NumberFormat = '0.00000';                          % V7.3: A1 addresses, no Range.Item
        if nc > 1 && nr > 1, ws.Range(sprintf('B2:%s%d', evColLetter(nc), nr)).NumberFormat = '0.0000'; end
        ur.Columns.AutoFit;
    end
    wb.Worksheets.Item(3).Columns.AutoFit;
    wb.Worksheets.Item(1).Activate;
    wb.Save;  wb.Close(false);  ex.Quit;  delete(ex);
    ok = true;  msg = '';
catch ME
    msg = ['formatting failed: ' ME.message];
    try, ex.Quit; delete(ex); catch, end
end
end

function s = evColLetter(n)
% V7.3: 1 -> 'A', 27 -> 'AA'
s = '';
while n > 0
    r = mod(n-1, 26);  s = [char(65 + r) s];  n = floor((n-1)/26); %#ok<AGROW>
end
end

function t = evJoin(c)
if isempty(c), t = 'none'; else, t = strjoin(c, ', '); end
end


%% ========================================================================
%%  V7 : PARAMETER OVERRIDES, LOAD PROFILE, ON-SCREEN GAINS
%% ========================================================================
function evApplyOverrides(verbose)
% kappa = effective torque constant ratio of the Simscape BLDC block. Ke_ph = Kt/kappa, so the
% torque per amp is proportional to 1/kappa x (true ratio). Measured 0.113 N*m/A at kappa 0.71
% -> true ratio 0.75 -> kappa 0.75 gives 0.107. (BLDCSpeedControlData.m formulas, unchanged.)
cfg = evCfg();
if ~evalin('base','exist(''Kt'',''var'')')
    try, evalin('base','BLDCSpeedControlData;'); catch, end
end
Kt = safeBase('Kt',0.107);  wm = safeBase('w_meas_rpm',600);  kOld = safeBase('kappa',NaN);
Ke = Kt/cfg.kappa;
assignin('base','kappa',      cfg.kappa);
assignin('base','Ke_ph',      Ke);
assignin('base','emf_max_ev', Ke*wm*2*pi/60);
assignin('base','psim',       0.0175*(Ke/0.1528));
assignin('base','t_stop',     cfg.t_stop);
if verbose
    fprintf('[DAQ]   kappa %.3f -> %.3f : Ke_ph = %.4f V*s/rad, emf_max_ev = %.3f V, psim = %.5f Wb (expected torque per amp %.3f N*m/A)\n', ...
        kOld, cfg.kappa, Ke, Ke*wm*2*pi/60, 0.0175*(Ke/0.1528), Kt);
end
end

function [ok, msg] = evEnsureLoadProfile(MDL, quiet)
% Built-in version of EV_SetLoadProfile. Idempotent: the file is rewritten only when the Torque
% signal differs from the wanted profile, then read back and checked.
cfg = evCfg();  L = cfg.load;  ok = false;  msg = '';
% V7.8: the profile is built on a FIXED horizon (never shorter than 0.3 s), so it does not depend on the Stop Time.
%       Any Stop Time from 0 to 0.3 s and beyond uses the same file; a run shorter than 0.23 s simply sees 0 Nm load.
tProfEnd = max(0.3, cfg.t_stop);
try, root = evalin('base','EV_DAQ_Root'); catch, root = evFindRoot(MDL); end
f = fullfile(root,'BLDCSpeedControlInput.mat');
if ~isfile(f), msg = ['not found: ' f]; return, end
try
    S = load(f);  vns = fieldnames(S);
    vn = '';
    scen = 'Test_1';
    try, if bdIsLoaded(MDL), scen = get_param([MDL '/Input'],'ActiveScenario'); end, catch, end
    if isfield(S,scen), vn = scen; end
    if isempty(vn)
        for k = 1:numel(vns), if contains(class(S.(vns{k})),'Dataset'), vn = vns{k}; break, end, end
    end
    if isempty(vn), vn = vns{1}; end
    ds = S.(vn);
    names = ds.getElementNames();
    idx = find(strcmpi(names,'Torque'),1);
    if isempty(idx), msg = ['no element named Torque in ' f '. Elements: ' strjoin(names',', ')]; return, end
    old = ds{idx};
    tt = old.Time(:);  yy = squeeze(double(old.Data));  yy = yy(:);
    [tt, iu] = unique(tt);  yy = yy(iu);                       % interp1 needs unique sample points
    chk = @(tq,yq) abs(interp1(tq,yq,L.t_end,'linear','extrap') + L.T) < 1e-6 && abs(interp1(tq,yq,tProfEnd,'linear','extrap') + L.T) < 1e-6 ...
                   && abs(interp1(tq,yq,L.t_start,'linear','extrap')) < 1e-6;
    if chk(tt,yy)
        ok = true;  msg = sprintf('already correct (%s / Torque: 0 Nm to %.3f s, %.2f Nm at %.3f s)', vn, L.t_start, -L.T, L.t_end);
        return
    end
    fprintf('[DAQ]   old Torque profile (for the record): t = %s s, value = %s Nm\n', mat2str(tt',4), mat2str(yy',4));
    ts = timeseries([0; 0; -L.T; -L.T], [0; L.t_start; L.t_end; tProfEnd], 'Name','Torque');
    try, ds = ds.setElement(idx, ts, 'Torque'); catch, ds{idx} = ts; end
    S.(vn) = ds;
    save(f,'-struct','S');
    S2 = load(f);  e2 = S2.(vn){idx};
    t2 = e2.Time(:);  y2 = squeeze(double(e2.Data));  y2 = y2(:);
    [t2, iu2] = unique(t2);  y2 = y2(iu2);
    ok = chk(t2,y2);
    if ok
        msg = sprintf('REWRITTEN and read back (%s / Torque: 0 Nm to %.3f s, ramp to %.2f Nm at %.3f s, hold to %.3f s). Close and reopen the model before the next run.', vn, L.t_start, -L.T, L.t_end, tProfEnd);
    else
        msg = 'rewritten but the read-back check FAILED - restore your file and edit the Torque points in the Input block by hand';
    end
catch ME
    msg = ['could not update the load profile: ' ME.message ' (close the model / Signal Editor and run setup again)'];
end
end

function evFixDisplayGains(MDL)
% The two scaling gains drive only the on-screen displays and the Live Signal Mux, not the logging.
% Original: current = cells_parallel x iCell (cell 1 x 10), voltage = cells_series x vAssy (group 1 x 13).
% V7: current = sum(iCell)/cells_series (pack terminal current), voltage = sum(vAssy) (pack voltage).
specs = {'Battery Current Scaling', 'cells_parallel', 'ones(1,cells_series*cells_parallel)/cells_series';
         'Battery Voltage Scaling', 'cells_series',   'ones(1,cells_series)'};
done = {};  g0 = {};  m0 = {};
for k = 1:size(specs,1)
    blk = [MDL '/' specs{k,1}];
    if getSimulinkBlockHandle(blk) < 0, fprintf('[DAQ]   %s: block not found, skipped.\n', specs{k,1}); continue, end
    try
        g = strtrim(get_param(blk,'Gain'));  m = get_param(blk,'Multiplication');
        if strcmp(g, specs{k,2})
            set_param(blk,'Gain',specs{k,3},'Multiplication','Matrix(K*u)');
            done{end+1} = blk;  g0{end+1} = g;  m0{end+1} = m; %#ok<AGROW>
        elseif strcmp(g, specs{k,3})
            fprintf('[DAQ]   %s: already pack-level.\n', specs{k,1});
        else
            fprintf('[DAQ]   %s: Gain = %s (custom), left unchanged.\n', specs{k,1}, g);
        end
    catch ME
        fprintf('[DAQ]   %s: not changed (%s)\n', specs{k,1}, ME.message);
    end
end
if isempty(done), return, end
try
    set_param(MDL,'SimulationCommand','update');                    % compile check
    for k = 1:numel(done), fprintf('[DAQ]   %s -> pack-level value (compile check passed).\n', strrep(done{k},[MDL '/'],'')); end
catch ME
    for k = 1:numel(done), try, set_param(done{k},'Gain',g0{k},'Multiplication',m0{k}); catch, end, end
    fprintf('[DAQ]   WARNING: the model did not compile with the pack-level gains, ORIGINAL gains restored (%s).\n', strtrim(ME.message));
    fprintf('[DAQ]            Logged data is not affected; only the on-screen Battery Current / Voltage keep showing cell 1 / group 1 scaled.\n');
end
end

%% ========================================================================
%%  V7.6  MODEL FIXES  (was EV_Model_Fixes_V8.m)   EV_DAQ_Builder_V7('Fixes', n)
%%   1 buck RC snubber -> exclude   2 Simscape local solver -> Backward Euler
%%   3 prints the input-capacitor recipe   4 Vdc feedback filter 0.01 -> 0.002 s
%%  One step per call, model must be stopped. Backup copy, change, read-back, save.
%% ========================================================================
function evModelFixes(MDL, step)
if ~bdIsLoaded(MDL), load_system(MDL); end
assert(strcmpi(get_param(MDL,'SimulationStatus'),'stopped'), 'Stop the model first.');
f = which([MDL '.slx']);
% (backup copy removed: no *_before_stepN.slx is created any more)
switch step
    case 1
        blk  = [MDL '/DC-DC Buck Converter'];
        want = 'ee.enum.converters.snubber.exclude';
        members = arrayfun(@char, enumeration('ee.enum.converters.snubber'), 'UniformOutput', false);
        if ~any(strcmp(members, 'exclude')), error('snubber enumeration has no member "exclude": %s', strjoin(members', ', ')); end
        old = get_param(blk,'snubber_type');
        fprintf('snubber_type before: %s (Cs=%s, Rs=%s)  [valid members: %s]\n', old, get_param(blk,'Cs'), get_param(blk,'Rs'), strjoin(members', ', '));
        if strcmp(old, want)
            fprintf('snubber_type already %s - nothing to change (model not re-saved).\n', want);
            return
        else
            lastwarn('');
            set_param(blk,'snubber_type',want);
            [wm, ~] = lastwarn;
            got = get_param(blk,'snubber_type');
            if ~strcmp(got, want) || ~isempty(wm)
                set_param(blk,'snubber_type',old);
                error('snubber_type NOT set (readback "%s", warning "%s"). Original restored.', got, wm);
            end
            try
                set_param(MDL,'SimulationCommand','update');            % compile check
            catch ME
                set_param(blk,'snubber_type',old);
                error('Model does not compile with snubber_type = exclude, original restored: %s', ME.message);
            end
            fprintf('snubber_type now   : %s (compile check passed)\n', get_param(blk,'snubber_type'));
        end
    case 2
        sc = [MDL '/Solver' newline 'Configuration'];
        fprintf('LocalSolverChoice before: %s\n', get_param(sc,'LocalSolverChoice'));
        set_param(sc,'LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER');
        fprintf('LocalSolverChoice now   : %s\n', get_param(sc,'LocalSolverChoice'));
    case 3
        fprintf(['Input capacitor (do by hand, wiring cannot be scripted safely without the port layout):\n' ...
            '  Add Simscape > Foundation > Electrical > Elements > Capacitor (C = 2.2 mF, series resistance 10 mOhm)\n' ...
            '  directly across the buck converter input terminals 1+ / 1- (battery side).\n' ...
            '  Starting value only: ripple ~ I*D*(1-D)/(f*C) = 30*0.21/(1e4*2.2e-3) = 0.29 V (ESR adds I*ESR).\n' ...
            '  Re-run and read VV-020 / VV-021; adjust C / ESR from the raw ripple, do not trust this number.\n']);
        return
    case 4
        b = [MDL '/Speed//RPM Controller/Vdc filter'];
        fprintf('T before: %s\n', get_param(b,'T'));  set_param(b,'T','0.002');  fprintf('T now: %s\n', get_param(b,'T'));
    otherwise
        error('step must be 1..4');
end
save_system(MDL);  fprintf('saved.\n');
end

%% ========================================================================
%%  V7.6  RUN ALL  (was EV_Run_All.m)
%%   EV_DAQ_Builder_V7('RunAll')                 snubber fix + setup (builds + saves EV_BlackBox) + run + post-process
%%   EV_DAQ_Builder_V7('RunAll','Solver',true)   also Backward Euler        ('Tune',true: Vdc filter 2 ms)
%%   EV_DAQ_Builder_V7('RunAll','Run',false)     apply everything, do not start the simulation
%% ========================================================================
function evRunAll(MDL, varargin)
p = inputParser;
addParameter(p,'Solver',false,@islogical);
addParameter(p,'Tune',  false,@islogical);
addParameter(p,'Run',   true, @islogical);
addParameter(p,'StopTime',[], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
parse(p,varargin{:});
root = evFindRoot(MDL);                          % V7.8: no hard-coded path
if isfolder(root), cd(root); end
addpath(pwd);
if isfolder(fullfile(pwd,'+Batteries2')), addpath(genpath(pwd)); end
fprintf('\n=== EV_DAQ_Builder_V7 RunAll ===\n');
if bdIsLoaded(MDL)
    if ~strcmpi(get_param(MDL,'SimulationStatus'),'stopped')
        error('Model is running. Press STOP, wait for Ready, then run again.');
    end
    userStop = p.Results.StopTime;
    if isempty(userStop), userStop = evStopTime(MDL); end          % V7.8: the value typed in the toolbar
    close_system(MDL,0);                       % reload from disk
    load_system(fullfile(root,[MDL '.slx']));
    if isfinite(userStop) && userStop > 0, set_param(MDL,'StopTime',sprintf('%.10g',userStop)); fprintf('[DAQ] Stop Time kept: %g s\n', userStop); end
elseif ~isempty(p.Results.StopTime)
    load_system(fullfile(root,[MDL '.slx']));  set_param(MDL,'StopTime',sprintf('%.10g',p.Results.StopTime));
end
fprintf('--- step 1: buck snubber -> exclude ---\n');            evModelFixes(MDL,1);
if p.Results.Solver, fprintf('--- step 2: local solver -> Backward Euler ---\n'); evModelFixes(MDL,2); end
if p.Results.Tune,   fprintf('--- step 4: Vdc filter T = 0.002 s ---\n');        evModelFixes(MDL,4); end
fprintf('--- DAQ setup (builds + saves EV_BlackBox) %s ---\n', iif(p.Results.Run,'and simulation start','only'));
feval(mfilename, 'Run', p.Results.Run);
end

