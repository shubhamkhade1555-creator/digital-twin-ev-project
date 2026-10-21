function result = RunAll(varargin)
%RunAll  One-click run of the EV digital twin (BLDC + battery + Black Box).
%
%   RunAll                  full run: paths -> checks -> load -> setup -> simulate -> verify
%   RunAll('Fixes',false)   skip the "buck snubber = exclude" model fix
%   RunAll('Timeout',1800)  maximum wall-clock seconds to wait for the simulation (default 3600)
%   RunAll('StopTime',0.1)  simulate 0.1 s (any value). Without this option RunAll uses the Stop Time that is
%                           currently typed in the Simulink toolbar of the open model; only if the model is
%                           not open it uses the value saved in the .slx file.
%   RunAll('Compile',true)  also run a separate compile check first (default off: one compile less, faster start)
%   RunAll('Fast',true)     skip Excel files, figures and raw-archive compaction (much shorter wait after the run)
%
%   HOW TO USE (every group member):
%     1. Put RunAll.m in the SAME folder as BLDCSpeedControl_EV_Layout_v2.slx and EV_DAQ_Builder_V7.m
%        (any PC / OneDrive path works - nothing is hard-coded).
%     2. In MATLAB: open RunAll.m and press Run, or type  RunAll  in the Command Window.
%
%   OUTPUT
%     - Every step is printed in the Command Window ([RunAll] lines) and also saved to
%       <project>/results/RunAll_<time>.txt
%     - The simulation itself prints [LIVE] lines every 0.1 s of simulation time (from EV_DAQ_Builder_V7)
%     - The full data archive is written by EV_DAQ_Builder_V7 to EV_RUN_<time>/ (its own command log is inside)
%     - Returns a struct: result.pass / warn / fail counts, result.checks table, result.runDir, result.logFile
%
%   STEP 10: numbered clean data + comparison graphs (our system vs Electrica 2022 reference). Done by EV_MakeReference, which the
%     Simulink StopFcn also starts, so a manual Run in Simulink (Stop Time typed in the toolbar) saves exactly the same.
%     Every run keeps its files in its own run folder:
%       Simulation Logs\EV_RUN_<date_time>\EV_DAQ_Clean_<run no>_<seconds x 10>.mat / .csv   (0.1 s -> _1_01, 4th run 0.5 s -> _4_05)
%       Simulation Logs\EV_RUN_<date_time>\Figures\Battery\   Battery_1..4
%       Simulation Logs\EV_RUN_<date_time>\Figures\Motor\     Motor_1..5
%       Simulation Logs\EV_RUN_<date_time>\Figures\           Battery_MASTER, Motor_MASTER, Combined_MASTER + Reference_Master.xlsx
%     Reference mode: EV_Ref_Mode = 'calculated' (default) | 'live' | 'original' (type in Command Window).
%
%   RunAll does NOT change any physics or parameter. It only calls the existing project files.

p = inputParser;
addParameter(p, 'Fixes',   true, @islogical);
addParameter(p, 'Timeout', 3600, @isnumeric);
addParameter(p, 'StopTime', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
addParameter(p, 'Fast', [], @(x) isempty(x) || islogical(x));
addParameter(p, 'Compile', false, @islogical);   % true = separate compile check before the run (the run compiles anyway; skipping saves one full Simscape compile)
addParameter(p, 'FullValidation', true, @islogical); % enforce benchmark duration >= 0.400 s for speed ramp, load ramp & hold
addParameter(p, 'DiagnosticMode', false, @islogical); % allow short-run diagnostic simulations (< 0.350 s)
parse(p, varargin{:});

MDL     = 'BLDCSpeedControl_EV_Layout_v2';
BUILDER = 'EV_DAQ_Builder_V7';
tAll    = tic;
R       = struct('level', {}, 'name', {}, 'detail', {});
result  = struct('pass', 0, 'warn', 0, 'fail', 0, 'checks', [], 'runDir', '', 'logFile', '');

%% ---- 1. project folder + path (automatic) ---------------------------------------------------
root = rafindroot(MDL);
cd(root);
rasetpaths(root);

logDir = fullfile(root, 'results');
if ~isfolder(logDir), mkdir(logDir); end
stamp   = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
logFile = fullfile(logDir, ['RunAll_' stamp '.txt']);
fid     = fopen(logFile, 'w');
cleaner = onCleanup(@() ralogclose(fid));
say     = @(varargin) ralog(fid, varargin{:});
result.logFile = logFile;

say('');
say('==============================================================');
say('  EV DIGITAL TWIN - RunAll   %s', char(datetime('now')));
say('==============================================================');
say('[RunAll] 1. Project folder (auto-detected): %s', root);
say('[RunAll]    MATLAB path set (project + sub-folders, run archives excluded).');
say('[RunAll]    Log file: %s', logFile);

%% ---- 2. required files ------------------------------------------------------------------------
say('[RunAll] 2. Checking files ...');
need = {[MDL '.slx'], true;  'BLDCSpeedControlData.m', true;  'BLDCSpeedControlInput.mat', true; ...
        'Batteries2_lib.slx', true;  [BUILDER '.m'], true;  'Batteries2.slx', false};
missingReq = {};
for k = 1:size(need, 1)
    ok = isfile(fullfile(root, need{k, 1}));
    if ok, tag = 'FOUND  '; elseif need{k, 2}, tag = 'MISSING'; else tag = 'missing (optional)'; end
    say('[RunAll]    %-18s %s', tag, need{k, 1});
    if ~ok && need{k, 2}, missingReq{end+1} = need{k, 1}; end %#ok<AGROW>
end
if ~isempty(missingReq)
    R = rarec(R, say, 'FAIL', 'Required files', ['missing: ' strjoin(missingReq, ', ')]);
    say('[RunAll] STOP: copy the missing file(s) into %s and run again.', root);
    result = rafinish(result, R, say, root, stamp, toc(tAll));
    return
end
R = rarec(R, say, 'PASS', 'Required files', 'all found');

%% ---- 3. MATLAB / products -----------------------------------------------------------------------
say('[RunAll] 3. Checking MATLAB ...');
rel = version('-release');
say('[RunAll]    MATLAB %s on %s', rel, computer);
if ~strcmp(rel, 'R2024b')
    R = rarec(R, say, 'WARN', 'MATLAB release', sprintf('%s (project was built in R2024b - the model may not open in an older release)', rel));
else
    R = rarec(R, say, 'PASS', 'MATLAB release', rel);
end
try
    vv = ver;
    names = {vv.Name};
catch
    names = {};
end
prods = {'Simulink', 'Simscape', 'Simscape Electrical', 'Simscape Battery'};
for k = 1:numel(prods)
    has = any(strcmp(names, prods{k}));
    if has, say('[RunAll]    product ok      : %s', prods{k});
    else,   say('[RunAll]    product NOT found: %s', prods{k}); end
end
if ~any(strcmp(names, 'Simscape Battery')) || ~any(strcmp(names, 'Simscape Electrical'))
    R = rarec(R, say, 'WARN', 'Products', 'Simscape Electrical / Battery not detected - the model may fail to compile');
end
if ~ispc
    R = rarec(R, say, 'WARN', 'Excel reports', 'not Windows - the Excel files of the archive need Excel (COM) and may be skipped or fail');
end

%% ---- 3b. remember the Stop Time the user typed in the toolbar (the reload in step 5 would discard it) ---
userStop = p.Results.StopTime;
if isempty(userStop) && bdIsLoaded(MDL)
    try
        str = strtrim(get_param(MDL, 'StopTime'));
        v = str2double(str);
        if ~isfinite(v), v = double(evalin('base', str)); end
        if isfinite(v) && v > 0, userStop = v; end
    catch
    end
end
if ~isempty(p.Results.Fast), assignin('base', 'EV_DAQ_Fast', p.Results.Fast); end

%% ---- 4. parameters ------------------------------------------------------------------------------
say('[RunAll] 4. Loading parameters (BLDCSpeedControlData.m) ...');
evalin('base', 'BLDCSpeedControlData;');
rpm_ref = rav('rpm_ref', 2950);  I_cont = rav('I_cont', 30);  I_peak = rav('I_peak', 45);
Kt      = rav('Kt', 0.107);      t_stop = rav('t_stop', 0.4);  pack_Ah = rav('pack_Ah', 50);
if ~isempty(userStop)
    t_stop = userStop;  assignin('base', 't_stop', t_stop);   % BLDCSpeedControlData.m sets 0.4; the user's value wins
    say('[RunAll]    Stop Time taken from %s: %g s (parameter file default %g s is overridden)', ...
        iif(isempty(p.Results.StopTime), 'the Simulink toolbar', 'RunAll(''StopTime'', ...)'), t_stop, rav('t_stop', 0.4));
end

% Stop-time enforcement: FullValidation mode vs DiagnosticMode
isDiagnostic = p.Results.DiagnosticMode;
if p.Results.FullValidation && ~isDiagnostic
    % The benchmark and its published validation windows require t_stop >= 0.400 s. Do not certify 0.350-0.399 s runs as full validation.
    if t_stop < 0.400
        err_msg = sprintf(['[RunAll] INSUFFICIENT DURATION FOR FULL VALIDATION:\n' ...
            'Requested StopTime = %.3f s is too short to complete the full validation sequence.\n' ...
            '  - Speed reference ramp (0 -> 2950 rpm) finishes at 0.227 s.\n' ...
            '  - Rated load torque ramp (0 -> 3.18 Nm) finishes at 0.280 s.\n' ...
            '  - The established benchmark requires the complete 0.400 s run.\n' ...
            'To run a full V&V benchmark, set StopTime >= 0.400 s.\n' ...
            'To run a quick short diagnostic check, explicitly pass: RunAll(''DiagnosticMode'', true, ''StopTime'', %.3f)'], ...
            t_stop, t_stop);
        R = rarec(R, say, 'FAIL', 'Validation Duration', sprintf('%.3f s < 0.400 s required benchmark duration', t_stop));
        error('RunAll:InsufficientDuration', '%s', err_msg);
    else
        say('[RunAll]    Mode: FULL VALIDATION (t_stop = %g s >= 0.350 s minimum required)', t_stop);
        R = rarec(R, say, 'PASS', 'Validation Duration', sprintf('%.3f s (meets 0.400 s benchmark duration)', t_stop));
    end
else
    say('[RunAll]    *** DIAGNOSTIC MODE ACTIVE *** (t_stop = %g s). Full V&V checks will NOT be certified.', t_stop);
    R = rarec(R, say, 'WARN', 'Validation Duration', sprintf('Diagnostic short run (%.3f s). Full V&V not certified.', t_stop));
end
say('[RunAll]    rpm_ref=%g rpm  I_cont=%g A  I_peak=%g A  Kt=%g N*m/A  t_stop=%g s  pack=%g Ah', ...
    rpm_ref, I_cont, I_peak, Kt, t_stop, pack_Ah);
Ts_run = rav('Ts', NaN);
say('[RunAll]    Ts = %g s (project setting: 1e-5 s = 2x faster, verified 15 PASS / 4 WARN / 0 FAIL)', Ts_run);
if abs(Ts_run - 1e-5) > 1e-12
    R = rarec(R, say, 'WARN', 'Sample time Ts', sprintf('Ts = %g s, not the verified 1e-5 s. If unintended, type  clear Ts_override  and run again.', Ts_run));
end

%% ---- 5. models ----------------------------------------------------------------------------------
say('[RunAll] 5. Loading models ...');
if bdIsLoaded(MDL)
    if ~strcmpi(get_param(MDL, 'SimulationStatus'), 'stopped')
        error('RunAll:running', 'Model %s is still running. Press STOP, wait for Ready, then run again.', MDL);
    end
    close_system(MDL, 0);      % reload from disk so every group member runs the file as saved
    say('[RunAll]    closed the old copy of %s (reload from disk).', MDL);
end
if ~isempty(userStop)
    load_system(fullfile(root, [MDL '.slx']));
    set_param(MDL, 'StopTime', sprintf('%.10g', userStop));   % re-apply: the reload gave back the value saved on disk
    say('[RunAll]    model Stop Time set to %g s after the reload.', userStop);
end
% clear results of an earlier run so they cannot be mistaken for this run
evalin('base', 'clear EV_BlackBox_log EV_DAQ_Clean EV_DAQ_Raw EV_DAQ_RunDir EV_MakeRef_Name EV_MakeRef_Busy');

%% ---- 6. model fix + DAQ setup (builds + saves EV_BlackBox, does not start) ------------------------
try
    if p.Results.Fixes
        say('[RunAll] 6a. Model fix: buck snubber -> exclude ...');
        feval(BUILDER, 'Fixes', 1);
    end
    say('[RunAll] 6b. DAQ setup (builds the LIVE tap and the Black Box, saves the model) ...');
    feval(BUILDER, 'Run', false);
catch ME
    R = rarec(R, say, 'FAIL', 'DAQ setup', ME.message);
    result = rafinish(result, R, say, root, stamp, toc(tAll));
    return
end
R = rarec(R, say, 'PASS', 'DAQ setup', 'model loaded, Black Box built, hooks written, model saved');

try
    v = str2double(strtrim(get_param(MDL, 'StopTime')));
    if isfinite(v) && v > 0, t_stop = v; end
catch
end
say('[RunAll]    Stop Time of the model for this run: %g s', t_stop);
% Re-check the effective model value AFTER DAQ setup/save. The setup callback can
% change model configuration, so checking only the requested value is insufficient.
if p.Results.FullValidation && ~p.Results.DiagnosticMode && t_stop < 0.400
    R = rarec(R, say, 'FAIL', 'Effective validation duration', ...
        sprintf('effective model StopTime %.3f s is below required 0.400 s benchmark', t_stop));
    result = rafinish(result, R, say, root, stamp, toc(tAll));
    error('RunAll:EffectiveStopTimeTooShort', ...
        'Full validation blocked: effective model StopTime %.3f s < 0.400 s. Use DiagnosticMode=true only for a diagnostic run.', t_stop);
end

%% ---- 7. compile check -----------------------------------------------------------------------------
if p.Results.Compile
    say('[RunAll] 7. Compile check (update diagram) ...');
    try
        if ~bdIsLoaded(MDL), load_system(fullfile(root, [MDL '.slx'])); end
        set_param(MDL, 'SimulationCommand', 'update');
        R = rarec(R, say, 'PASS', 'Compile check', 'model compiles');
    catch ME
        R = rarec(R, say, 'FAIL', 'Compile check', ME.message);
        result = rafinish(result, R, say, root, stamp, toc(tAll));
        return
    end
else
    say('[RunAll] 7. Separate compile check skipped (the simulation start compiles the model once; use RunAll(''Compile'',true) to force it).');
end

%% ---- 8. simulate ------------------------------------------------------------------------------------
say('[RunAll] 8. Starting simulation (t_stop = %g s). [LIVE] lines follow ...', t_stop);
say('--------------------------------------------------------------');
set_param(MDL, 'SimulationCommand', 'start');
tw = tic;  seen = false;  beat = 0;
while toc(tw) < p.Results.Timeout
    st = get_param(MDL, 'SimulationStatus');
    if ~strcmpi(st, 'stopped')
        seen = true;
        if toc(tw) - beat >= 5
            beat = toc(tw);
            try, tsim = get_param(MDL, 'SimulationTime'); catch, tsim = NaN; end
            say('[RunAll]    ... %s, simulation time %.3f / %g s, wall time %.0f s', st, tsim, t_stop, toc(tw));
        end
    elseif seen
        break
    elseif toc(tw) > 60
        break
    end
    pause(0.5);                      % lets the model callbacks (LIVE tap, StopFcn) run
end
if ~seen
    R = rarec(R, say, 'FAIL', 'Simulation start', 'the simulation never started (see Simulink Diagnostic Viewer)');
    result = rafinish(result, R, say, root, stamp, toc(tAll));
    return
end
if ~strcmpi(get_param(MDL, 'SimulationStatus'), 'stopped')
    set_param(MDL, 'SimulationCommand', 'stop');
    R = rarec(R, say, 'FAIL', 'Simulation time', sprintf('timeout after %g s - simulation stopped by RunAll', p.Results.Timeout));
end
pause(2); drawnow;                   % give the StopFcn (data archive) time to start; it runs to completion
for k = 1:120                        % wait up to ~2 min for the archive data
    if rahas('EV_DAQ_Clean') && rahas('EV_BlackBox_log'), break, end
    pause(1);
end
say('--------------------------------------------------------------');
say('[RunAll]    simulation finished after %.0f s wall time.', toc(tw));
R = rarec(R, say, 'PASS', 'Simulation run', sprintf('finished in %.0f s', toc(tw)));
if rahas('EV_DAQ_RunDir')
    result.runDir = evalin('base', 'EV_DAQ_RunDir');
    say('[RunAll]    data archive: %s', result.runDir);
end

%% ---- 9. verification of this run ------------------------------------------------------------------
say('[RunAll] 9. Verifying the result ...');
if ~(rahas('EV_BlackBox_log') && rahas('EV_DAQ_Clean'))
    R = rarec(R, say, 'FAIL', 'Result data', 'EV_BlackBox_log / EV_DAQ_Clean not in the workspace after the run');
    result = rafinish(result, R, say, root, stamp, toc(tAll));
    return
end
bb = evalin('base', 'EV_BlackBox_log');
C  = evalin('base', 'EV_DAQ_Clean');
lab = {};
try, lab = get_param([MDL '/EV_BlackBox'], 'UserData'); catch, end
if ~iscell(lab) || numel(lab) ~= size(bb.Data, 2)
    lab = {'Vbatt_V', 'Ibatt_A', 'SOC', 'RPM_rpm', 'Idc_f_A', 'Vdc_m_V', 'omega_wheel', 'Torque_Nm'};
end
V   = @(n) racol(bb, lab, n);
tb  = bb.Time(:);
Vb = V('Vbatt_V'); Ib = abs(V('Ibatt_A'));   % POSITIVE-CURRENT
 SOC = V('SOC'); RPM = V('RPM_rpm');
Im = V('Idc_f_A'); Vd = V('Vdc_m_V'); Tq = V('Torque_Nm'); Ww = V('omega_wheel');
if any(cellfun(@isempty, {Vb, Ib, SOC, RPM, Im, Vd, Tq, Ww}))
    R = rarec(R, say, 'FAIL', 'Black Box channels', 'a channel is missing from EV_BlackBox_log');
    result = rafinish(result, R, say, root, stamp, toc(tAll));
    return
end

% (a) size and content
nExp = floor(t_stop / 0.001 + 1e-9) + 1;      % 1 ms samples; a Stop Time that is not a multiple of 1 ms may add the final sample
[n, m] = size(bb.Data);
R = rarec(R, say, rapf((n == nExp || n == nExp + 1) && m == 8, 'FAIL'), 'Black Box size', sprintf('%d x %d (expected %d or %d x 8, 1 ms)', n, m, nExp, nExp + 1));
R = rarec(R, say, rapf(~any(isnan(bb.Data(:))), 'FAIL'), 'Black Box NaN', sprintf('%d NaN values', nnz(isnan(bb.Data(:)))));
R = rarec(R, say, rapf(abs(tb(end) - t_stop) < 1e-6 || (tb(end) <= t_stop + 1e-9 && t_stop - tb(end) < 0.001 + 1e-9), 'FAIL'), 'Reached t_stop', sprintf('last time = %.4f s', tb(end)));

% (b) start and end of the run
R = rarec(R, say, rapf(SOC(1) > 0.999 && abs(RPM(1)) < 1 && Vb(1) > 45 && Vb(1) < 55, 'FAIL'), 'Initial state', ...
    sprintf('SOC=%.5f  rpm=%.1f  Vbatt=%.2f V', SOC(1), RPM(1), Vb(1)));
shortRun = t_stop < 0.28;      % the speed ramp ends at 0.227 s and the load ramp at 0.28 s: a shorter run cannot reach the end state
if shortRun, say('[RunAll]    note: t_stop = %g s is shorter than 0.28 s, so end-of-run checks are WARN instead of FAIL.', t_stop); end
endLvl = iif(shortRun, 'WARN', 'FAIL');
R = rarec(R, say, rapf(RPM(end) >= 2900 && RPM(end) <= 3000, endLvl), 'Final speed (2900-3000 rpm)', sprintf('%.1f rpm (target %g)', RPM(end), rpm_ref));

% (c) physics
w  = tb >= t_stop - 0.01;
kt = mean(Tq(w)) / mean(Im(w));
R = rarec(R, say, rapf(abs(kt - Kt) / Kt <= 0.05, 'WARN'), 'Torque per amp (Kt)', sprintf('%.4f N*m/A (datasheet %.3f, +/-5%%)', kt, Kt));
R = rarec(R, say, rapf(max(Im) <= 1.1 * I_peak, 'FAIL'), 'Peak motor current', sprintf('max %.1f A (I_peak %g A)', max(Im), I_peak));
w2 = tb >= t_stop - 0.02;
R = rarec(R, say, rapf(mean(Im(w2)) <= I_cont, 'WARN'), 'Motor current vs I_cont', ...
    sprintf('mean of last 20 ms = %.1f A (I_cont %g A; run is short, load only reached 3.18 Nm at 0.28 s)', mean(Im(w2)), I_cont));
dSOCexp = trapz(tb, abs(Ib)) / 3600 / pack_Ah;
dSOC    = SOC(1) - SOC(end);
if dSOCexp > 0
    R = rarec(R, say, rapf(dSOC / dSOCexp > 0.8 && dSOC / dSOCexp < 1.25, 'WARN'), 'SOC vs coulomb count', ...
        sprintf('SOC drop %.2e, expected %.2e (ratio %.2f)', dSOC, dSOCexp, dSOC / dSOCexp));
end

% (d) Black Box against the archive (last 20 ms)
vn = C.Properties.VariableNames;
mc = C.Time >= t_stop - 0.02;
if all(ismember({'MotorCurrent', 'BatteryVoltage', 'BatteryCurrent', 'RPM'}, vn))
    d1 = mean(Im(w2)) / mean(C.MotorCurrent(mc)) - 1;
    d2 = mean(Vb(w2)) - mean(C.BatteryVoltage(mc));
    d3 = mean(RPM(w2)) / mean(C.RPM(mc)) - 1;
    d4 = mean(Ib(w2)) / mean(C.BatteryCurrent(mc)) - 1;
    R = rarec(R, say, rapf(abs(d1) < 0.02,  'FAIL'), 'BlackBox vs archive: motor current', sprintf('%+.2f %%', 100*d1));
    R = rarec(R, say, rapf(abs(d2) < 0.2,   'FAIL'), 'BlackBox vs archive: battery voltage', sprintf('%+.3f V', d2));
    R = rarec(R, say, rapf(abs(d3) < 0.005, 'FAIL'), 'BlackBox vs archive: RPM', sprintf('%+.3f %%', 100*d3));
    R = rarec(R, say, rapf(abs(d4) < 0.10,  'WARN'), 'BlackBox vs archive: battery current', ...
        sprintf('%+.1f %%  (BB %.2f A, archive %.2f A; ripple std BB %.2f A, archive %.2f A)', 100*d4, ...
        mean(Ib(w2)), mean(C.BatteryCurrent(mc)), std(Ib(w2)), std(C.BatteryCurrent(mc))));
    % which one is physically right? buck power balance Vdc*Idc / (Vbatt*Ibatt) should be about 0.85 ... 1.02
    pBB = mean(Vd(w2) .* Im(w2)) / mean(Vb(w2) .* abs(Ib(w2)));
    R = rarec(R, say, rapf(pBB >= 0.85 && pBB <= 1.02, 'WARN'), 'Power balance (Black Box)', sprintf('Pdc/Pbatt = %.3f (expected 0.85-1.02)', pBB));
    pCV = '';
    if ismember('DCLinkVoltage', vn), pCV = 'DCLinkVoltage'; elseif ismember('Vdc', vn), pCV = 'Vdc'; end
    if ~isempty(pCV)
        pC = mean(C.(pCV)(mc) .* C.MotorCurrent(mc)) / mean(C.BatteryVoltage(mc) .* abs(C.BatteryCurrent(mc)));
        R = rarec(R, say, rapf(pC >= 0.85 && pC <= 1.02, 'WARN'), 'Power balance (archive)', sprintf('Pdc/Pbatt = %.3f (expected 0.85-1.02)', pC));
    end
else
    R = rarec(R, say, 'WARN', 'BlackBox vs archive', 'archive table has other column names - comparison skipped');
end
%% ---- 9b + 10. numbered clean data, comparison graphs, reference Excel (EV_MakeReference) ---------------------
% EV_MakeReference runs inside the Simulink StopFcn chain (EV_DAQ_Builder_V7 step 14c), so a plain Run in Simulink saves
% the same files. RunAll waits for it and only calls it itself if the hook did not run.
say('[RunAll] 10. Clean data + comparison graphs (EV_MakeReference, inside the run folder) ...');
if logical(rav('EV_DAQ_Fast', false)) || logical(rav('EV_Ref_Skip', false))
    say('[RunAll]    Fast mode / EV_Ref_Skip: clean-data copy, graphs and reference Excel skipped.');
else
    try
        if isempty(result.runDir) || ~isfolder(result.runDir)
            error('RunAll:noRunDir', 'run folder not found - graphs skipped');
        end
        tp = tic;
        while toc(tp) < 180
            if rahas('EV_MakeRef_Name'), break, end
            busy = rahas('EV_MakeRef_Busy') && logical(rav('EV_MakeRef_Busy', false));
            if ~busy && toc(tp) > 15, break, end
            pause(1);
        end
        if rahas('EV_MakeRef_Name')
            fname = evalin('base', 'EV_MakeRef_Name');
        else
            say('[RunAll]    Simulink hook did not run (old EV_DAQ_Builder_V7.m?) - calling EV_MakeReference here.');
            EV_MakeReference(C, [], [], result.runDir);
            fname = evalin('base', 'EV_MakeRef_Name');
        end
        [~, rn] = fileparts(result.runDir);
        R = rarec(R, say, 'PASS', 'Clean data + graphs', [fullfile('Simulation Logs', rn, 'Figures') '  (' fname ')']);
    catch ME
        R = rarec(R, say, 'WARN', 'Clean data + graphs', ME.message);
    end
end

result = rafinish(result, R, say, root, stamp, toc(tAll));
end

%% =================================================================================================
%%  local helpers
%% =================================================================================================
function root = rafindroot(MDL)
mf   = [MDL '.slx'];
here = fileparts(mfilename('fullpath'));
cand = unique({here, pwd}, 'stable');
for k = 1:numel(cand)
    if ~isempty(cand{k}) && isfile(fullfile(cand{k}, mf)), root = cand{k}; return, end
end
for k = 1:numel(cand)
    if isempty(cand{k}), continue, end
    d = dir(fullfile(cand{k}, '**', mf));
    if ~isempty(d), root = d(1).folder; return, end
end
d = uigetdir(pwd, ['Select the folder that contains ' mf]);
if isequal(d, 0) || ~isfile(fullfile(d, mf))
    error('RunAll:noRoot', 'Cannot find %s. Put RunAll.m in the same folder as the model.', mf);
end
root = d;
end

function rasetpaths(root)
addpath(root);
pp = strsplit(genpath(root), pathsep);
bad = cellfun(@isempty, pp) | contains(pp, 'EV_RUN_') | contains(pp, [filesep 'results']) ...
    | contains(pp, 'slprj') | contains(pp, [filesep '.git']);
pp = pp(~bad);
if ~isempty(pp), addpath(strjoin(pp, pathsep)); end
end

function ralog(fid, varargin)
if isempty(varargin), s = ''; else, s = sprintf(varargin{:}); end
fprintf('%s\n', s);
if fid > 0, fprintf(fid, '%s\n', s); end
end

function ralogclose(fid)
if fid > 0, try, fclose(fid); catch, end, end
end

function R = rarec(R, say, level, name, detail)
R(end+1) = struct('level', level, 'name', name, 'detail', detail);
say('[RunAll]    [%-4s] %-38s %s', level, name, detail);
end

function lvl = rapf(cond, failLevel)
if cond, lvl = 'PASS'; else, lvl = failLevel; end
end

function o = iif(c, a, b)
if c, o = a; else, o = b; end
end

function v = rav(name, default)
try, v = evalin('base', name); catch, v = default; end
end

function tf = rahas(name)
tf = evalin('base', sprintf('exist(''%s'',''var'')', name)) == 1;
end

function v = racol(bb, lab, name)
k = find(strcmp(lab, name), 1);
if isempty(k), v = []; else, v = bb.Data(:, k); end
v = v(:);
end

function result = rafinish(result, R, say, root, stamp, secs)
lv = {R.level};
result.pass = nnz(strcmp(lv, 'PASS'));
result.warn = nnz(strcmp(lv, 'WARN'));
result.fail = nnz(strcmp(lv, 'FAIL'));
if isempty(R)
    result.checks = table();
else
    result.checks = struct2table(R);
end
say('');
say('==============================================================');
say('  SUMMARY   PASS %d   WARN %d   FAIL %d     (%.0f s)', result.pass, result.warn, result.fail, secs);
if result.fail == 0 && result.warn == 0
    say('  RESULT: ALL CHECKS PASSED');
elseif result.fail == 0
    say('  RESULT: OK, with %d warning(s) - read the WARN lines above', result.warn);
else
    say('  RESULT: %d CHECK(S) FAILED - read the FAIL lines above', result.fail);
end
if ~isempty(result.runDir), say('  Data archive : %s', result.runDir); end
say('  RunAll log   : %s', result.logFile);
say('==============================================================');
try
    save(fullfile(root, 'results', ['RunAll_' stamp '.mat']), 'result');
catch
end
end