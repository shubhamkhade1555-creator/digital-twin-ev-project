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
%   RunAll('Fast',true)     fast post-processing (default): retain CSV/text, V&V, N4SID and PNG graphs
%   RunAll('FastRestart',true) reuse compiled model across repeated runs (first run still compiles).
%                            Turn FastRestart off before manually editing/adding Simulink blocks.
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
%   STEP 10: unified Battery, Motor and N4SID graph generation through EV_Graphs.m.
%     RunAll and the model StopFcn use the same graph source; duplicate generation is avoided.
%     Figures are saved under each run's Figures\Battery, Figures\Motor,
%     Figures\N4SID_Battery and Figures\N4SID_Motor folders. PNG (300 dpi) only.
%     PASS/FAIL verdicts remain in text/CSV reports and are not written on graphs.
%
%   RunAll does NOT change any physics or parameter. It only calls the existing project files.

p = inputParser;
addParameter(p, 'Fixes',   true, @islogical);
addParameter(p, 'Timeout', 3600, @isnumeric);
addParameter(p, 'StopTime', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
addParameter(p, 'Fast', true, @islogical); % fast post-processing is default; pass Fast=false for full Excel reports
addParameter(p, 'FastRestart', false, @islogical); % opt-in: keep compiled model for repeated runs in this MATLAB session
addParameter(p, 'Compile', false, @islogical);   % true = separate compile check before the run (the run compiles anyway; skipping saves one full Simscape compile)
addParameter(p, 'FullValidation', true, @islogical); % enforce duration >= 0.400 s (min 0.350 s) for speed ramp, load ramp & hold
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
        'Batteries2_lib.slx', true;  [BUILDER '.m'], true;  'EV_Graphs.m', true;  'Batteries2.slx', false};
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
if ~ispc && ~p.Results.Fast
    R = rarec(R, say, 'WARN', 'Excel reports', 'not Windows - full Excel reporting requires Excel/COM and may be skipped or fail');
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
assignin('base', 'EV_DAQ_Fast', p.Results.Fast);
if p.Results.Fast
    say('[RunAll] Fast mode ON: Excel workbooks and raw-archive compaction skipped; raw/clean data, Black Box, V&V, N4SID and PNG graphs retained.');
else
    say('[RunAll] Full reporting mode ON: Excel workbooks and raw-archive compaction enabled.');
end

%% ---- 4. parameters ------------------------------------------------------------------------------
say('[RunAll] 4. Loading parameters (BLDCSpeedControlData.m) ...');
evalin('base', 'BLDCSpeedControlData;');
rpm_ref = rav('rpm_ref', 2950);  I_cont = rav('I_cont', 30);  I_peak = rav('I_peak', 45);
I_project_accept = 35; % Owner-approved project acceptance threshold for motor RMS/average/hold checks only; not a datasheet rating
Kt      = rav('Kt', 0.107);      t_stop = rav('t_stop', 0.4);  pack_Ah = rav('pack_Ah', 50);
if ~isempty(userStop)
    t_stop = userStop;  assignin('base', 't_stop', t_stop);   % BLDCSpeedControlData.m sets 0.4; the user's value wins
    say('[RunAll]    Stop Time taken from %s: %g s (parameter file default %g s is overridden)', ...
        iif(isempty(p.Results.StopTime), 'the Simulink toolbar', 'RunAll(''StopTime'', ...)'), t_stop, rav('t_stop', 0.4));
end

% Stop-time enforcement: FullValidation mode vs DiagnosticMode
isDiagnostic = p.Results.DiagnosticMode;
if p.Results.FullValidation && ~isDiagnostic
    % Speed ramp completes at 0.227 s, load ramp completes at 0.280 s. Full validation requires hold window >= 0.070 s (t_stop >= 0.350 s; benchmark 0.400 s).
    if t_stop < 0.350
        err_msg = sprintf(['[RunAll] INSUFFICIENT DURATION FOR FULL VALIDATION:\n' ...
            'Requested StopTime = %.3f s is too short to complete the full validation sequence.\n' ...
            '  - Speed reference ramp (0 -> 2950 rpm) finishes at 0.227 s.\n' ...
            '  - Rated load torque ramp (0 -> 3.18 Nm) finishes at 0.280 s.\n' ...
            '  - Steady-state hold window requires at least 0.400 s (minimum 0.350 s).\n' ...
            'To run a full V&V benchmark, set StopTime >= 0.400 s.\n' ...
            'To run a quick short diagnostic check, explicitly pass: RunAll(''DiagnosticMode'', true, ''StopTime'', %.3f)'], ...
            t_stop, t_stop);
        R = rarec(R, say, 'FAIL', 'Validation Duration', sprintf('%.3f s < 0.350 s minimum needed for full ramp+hold', t_stop));
        error('RunAll:InsufficientDuration', '%s', err_msg);
    else
        say('[RunAll]    Mode: FULL VALIDATION (t_stop = %g s >= 0.350 s minimum required)', t_stop);
        R = rarec(R, say, 'PASS', 'Validation Duration', sprintf('%.3f s (meets full validation requirement)', t_stop));
    end
else
    say('[RunAll]    *** DIAGNOSTIC MODE ACTIVE *** (t_stop = %g s). Full V&V checks will NOT be certified.', t_stop);
    R = rarec(R, say, 'WARN', 'Validation Duration', sprintf('Diagnostic short run (%.3f s). Full V&V not certified.', t_stop));
end
say('[RunAll]    rpm_ref=%g rpm  I_cont=%g A (datasheet; 35 A continuous unconfirmed)  I_project_accept=%g A  I_peak=%g A  Kt=%g N*m/A  t_stop=%g s  pack=%g Ah', ...
    rpm_ref, I_cont, I_project_accept, I_peak, Kt, t_stop, pack_Ah);
Ts_run = rav('Ts', NaN);
say('[RunAll]    Ts = %g s (project setting: 1e-5 s = 2x faster, verified 15 PASS / 4 WARN / 0 FAIL)', Ts_run);
if abs(Ts_run - 1e-5) > 1e-12
    R = rarec(R, say, 'WARN', 'Sample time Ts', sprintf('Ts = %g s, not the verified 1e-5 s. If unintended, type  clear Ts_override  and run again.', Ts_run));
end

%% ---- 5. models ----------------------------------------------------------------------------------
say('[RunAll] 5. Loading models ...');
fastRestartActive = false;
if bdIsLoaded(MDL)
    stNow = get_param(MDL, 'SimulationStatus');
    frOn = strcmpi(get_param(MDL, 'FastRestart'), 'on');
    % A completed Fast Restart run leaves the model initialized. Keep it initialized
    % only when explicitly requested; otherwise disable it before allowing setup/editing.
    if frOn && strcmpi(stNow, 'initialized') && ~p.Results.FastRestart
        set_param(MDL, 'FastRestart', 'off');
        stNow = get_param(MDL, 'SimulationStatus');
        say('[RunAll]    Fast Restart disabled; model released for normal setup/editing.');
        frOn = false;
    elseif frOn && ~strcmpi(stNow, 'initialized')
        set_param(MDL, 'FastRestart', 'off');
        stNow = get_param(MDL, 'SimulationStatus');
        say('[RunAll]    stale Fast Restart state cleared before setup.');
        frOn = false;
    end
    fastRestartActive = p.Results.FastRestart && frOn && strcmpi(stNow, 'initialized');
    if ~strcmpi(stNow, 'stopped') && ~fastRestartActive
        error('RunAll:running', 'Model %s is in state "%s". Press STOP, wait for Ready, or disable Fast Restart before setup.', MDL, stNow);
    end
    if fastRestartActive
        say('[RunAll]    Fast Restart compiled model reused; no block rebuild/save will run.');
    else
        % Keep the loaded model in memory. Never discard unsaved manual sensor/layout edits.
        try
            isDirty = strcmpi(get_param(MDL, 'Dirty'), 'on');
        catch
            isDirty = false;
        end
        if isDirty
            say('[RunAll]    unsaved model edits detected; saving before setup ...');
            try
                save_system(MDL);
                say('[RunAll]    saved current model edits.');
            catch ME_save
                error('RunAll:SaveBeforeReloadFailed', ...
                    'Could not save the open model; RunAll stopped without closing it. Save manually and retry. Details: %s', ME_save.message);
            end
        else
            say('[RunAll]    reusing the loaded model (no close/reload).');
        end
    end
end
if ~isempty(userStop)
    if ~bdIsLoaded(MDL), load_system(fullfile(root, [MDL '.slx'])); end
    currentStop = str2double(strtrim(get_param(MDL, 'StopTime')));
    if ~isfinite(currentStop) || abs(currentStop-userStop) > max(1e-12, 1e-9*abs(userStop))
        set_param(MDL, 'StopTime', sprintf('%.10g', userStop));
        say('[RunAll]    model Stop Time updated to %g s.', userStop);
    else
        say('[RunAll]    model Stop Time retained at %g s.', userStop);
    end
end
% clear results of an earlier run so they cannot be mistaken for this run
evalin('base', 'clear EV_BlackBox_log EV_DAQ_Clean EV_DAQ_Raw EV_DAQ_RunDir EV_MakeRef_Name EV_MakeRef_Busy');

%% ---- 6. model fix + DAQ setup (builds + saves EV_BlackBox, does not start) ------------------------
if fastRestartActive
    say('[RunAll] 6. Fast Restart cache is active: skipped model fixes, block rebuild and save.');
else
    % The model's own simulation start performs compilation. During this coordinated RunAll path,
    % defer helper compile checks so one run does not compile the same Simscape model multiple times.
    assignin('base','EV_DAQ_DeferCompile',true);
    try
        if p.Results.Fixes
            say('[RunAll] 6a. Model fix: buck snubber -> exclude ...');
            feval(BUILDER, 'Fixes', 1);
        end
        say('[RunAll] 6b. DAQ setup (builds the LIVE tap and the Black Box, saves the model) ...');
        feval(BUILDER, 'Run', false);
    catch ME
        evalin('base','clear EV_DAQ_DeferCompile');
        R = rarec(R, say, 'FAIL', 'DAQ setup', ME.message);
        result = rafinish(result, R, say, root, stamp, toc(tAll));
        return
    end
    evalin('base','clear EV_DAQ_DeferCompile');
    R = rarec(R, say, 'PASS', 'DAQ setup', 'model loaded, Black Box built, hooks written, model saved');
end

try
    v = str2double(strtrim(get_param(MDL, 'StopTime')));
    if isfinite(v) && v > 0, t_stop = v; end
catch
end
say('[RunAll]    Stop Time of the model for this run: %g s', t_stop);

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
elseif fastRestartActive
    say('[RunAll] 7. Separate compile check skipped; retaining Fast Restart compiled state.');
else
    say('[RunAll] 7. Separate compile check skipped (the simulation start compiles the model once; use RunAll(''Compile'',true) to force it).');
end

%% ---- 8. simulate ------------------------------------------------------------------------------------
fastRestartEnabled = fastRestartActive;
if p.Results.FastRestart && ~fastRestartActive
    try
        set_param(MDL, 'FastRestart', 'on');
        fastRestartEnabled = strcmpi(get_param(MDL, 'FastRestart'), 'on');
        if fastRestartEnabled
            say('[RunAll] Fast Restart enabled. First run still compiles; repeat runs may reuse the initialized model.');
        end
    catch ME_fr
        fastRestartEnabled = false;
        R = rarec(R, say, 'WARN', 'Fast Restart', ['Could not enable Fast Restart; using normal simulation: ' ME_fr.message]);
    end
elseif fastRestartActive
    say('[RunAll] Fast Restart already initialized; reusing the compiled model.');
end
say('[RunAll] 8. Starting simulation (t_stop = %g s). [LIVE] lines follow ...', t_stop);
say('--------------------------------------------------------------');
% Time this call separately: Simulink may spend a long time compiling/initializing
% before it returns. Previously this interval was omitted from the simulation timer.
tStartCall = tic;
set_param(MDL, 'SimulationCommand', 'start');
startCallWall = toc(tStartCall);
say('[RunAll]    start-command wall time (compile/startup if blocking): %.1f s', startCallWall);
tw = tic;  seen = false;  beat = 0;
while toc(tw) < p.Results.Timeout
    st = get_param(MDL, 'SimulationStatus');
    idleState = strcmpi(st, 'stopped') || (fastRestartEnabled && strcmpi(st, 'initialized'));
    if ~idleState
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
    pause(0.5);                      % lets model callbacks (LIVE tap, StopFcn) run
end
if ~seen
    R = rarec(R, say, 'FAIL', 'Simulation start', 'the simulation never started (see Simulink Diagnostic Viewer)');
    result = rafinish(result, R, say, root, stamp, toc(tAll));
    return
end
stEnd = get_param(MDL, 'SimulationStatus');
idleAtEnd = strcmpi(stEnd, 'stopped') || (fastRestartEnabled && strcmpi(stEnd, 'initialized'));
if ~idleAtEnd
    set_param(MDL, 'SimulationCommand', 'stop');
    R = rarec(R, say, 'FAIL', 'Simulation time', sprintf('timeout after %g s - simulation stopped by RunAll (state=%s)', p.Results.Timeout, stEnd));
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
    def = {'Vbatt_V', 'Ibatt_A', 'SOC', 'RPM_rpm', 'Idc_f_A', 'Vdc_m_V', 'omega_wheel', 'Torque_Nm', 'Tmotor_C', 'Tbatt_C', 'Ibat_sens_A', 'Vbat_sens_V'};
    nc = size(bb.Data, 2);
    if nc <= numel(def) && nc >= 7, lab = def(1:nc); end
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
R = rarec(R, say, rapf((n == nExp || n == nExp + 1) && any(m == [8 9 10]), 'FAIL'), 'Black Box size', sprintf('%d x %d (expected %d or %d rows and 8 baseline / 9-10 optional thermal channels, 1 ms)', n, m, nExp, nExp + 1));
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
R = rarec(R, say, rapf(mean(Im(w2)) <= I_project_accept, 'WARN'), 'Motor current vs project acceptance limit', ...
    sprintf('mean of last 20 ms = %.1f A (project limit %.0f A; datasheet continuous rating %.0f A remains separate and unconfirmed for 35 A operation; load reaches 3.18 Nm at 0.28 s)', ...
    mean(Im(w2)), I_project_accept, I_cont));
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
    % DC-link power balance MUST use an independent measured DCLinkCurrent channel.
    % Idc_f_A / MotorCurrent is a filtered controller estimate, not a conductor measurement.
    IdcBB = V('DCLinkCurrent_A');
    if isempty(IdcBB) || ~any(isfinite(IdcBB))
        R = rarec(R, say, 'WARN', 'Power balance (Black Box)', ...
            'NOT_AVAILABLE: no finite measured DCLinkCurrent channel; controller estimate intentionally not used');
    else
        mbb = w2 & isfinite(Vd) & isfinite(IdcBB) & isfinite(Vb) & isfinite(Ib);
        if any(mbb) && mean(Vb(mbb).*abs(Ib(mbb))) >= 1
            pBB = mean(abs(Vd(mbb).*IdcBB(mbb))) / mean(Vb(mbb).*abs(Ib(mbb)));
            R = rarec(R, say, rapf(pBB >= 0.85 && pBB <= 1.02, 'WARN'), ...
                'Power balance (Black Box; measured DCLinkCurrent)', ...
                sprintf('Pdc/Pbatt = %.3f (expected 0.85-1.02)', pBB));
        else
            R = rarec(R, say, 'WARN', 'Power balance (Black Box)', ...
                'NOT_AVAILABLE: no aligned finite DCLinkCurrent and battery power samples');
        end
    end

    % Archive check: only use a real DCLinkCurrent column; never substitute MotorCurrent.
    pCV = '';
    if ismember('DCLinkVoltage', vn), pCV = 'DCLinkVoltage'; elseif ismember('Vdc', vn), pCV = 'Vdc'; end
    if ismember('DCLinkCurrent', vn) && ~isempty(pCV) && ...
            all(ismember({'BatteryVoltage','BatteryCurrent'}, vn))
        IdcC = C.DCLinkCurrent;
        VdcC = C.(pCV);
        if any(isfinite(IdcC(mc)))
            mC = mc & isfinite(VdcC) & isfinite(IdcC) & ...
                isfinite(C.BatteryVoltage) & isfinite(C.BatteryCurrent);
            if any(mC) && mean(C.BatteryVoltage(mC).*abs(C.BatteryCurrent(mC))) >= 1
                pC = mean(abs(VdcC(mC).*IdcC(mC))) / ...
                    mean(C.BatteryVoltage(mC).*abs(C.BatteryCurrent(mC)));
                R = rarec(R, say, rapf(pC >= 0.85 && pC <= 1.02, 'WARN'), ...
                    'Power balance (archive; measured DCLinkCurrent)', ...
                    sprintf('Pdc/Pbatt = %.3f (expected 0.85-1.02)', pC));
            else
                R = rarec(R, say, 'WARN', 'Power balance (archive)', ...
                    'NOT_AVAILABLE: no aligned finite DC-link and battery power samples');
            end
        else
            R = rarec(R, say, 'WARN', 'Power balance (archive)', ...
                'NOT_AVAILABLE: DCLinkCurrent is absent or all NaN in the evaluation window');
        end
    else
        R = rarec(R, say, 'WARN', 'Power balance (archive)', ...
            'NOT_AVAILABLE: archive lacks measured DCLinkCurrent, DCLinkVoltage/Vdc, or battery power channels');
    end
else
    R = rarec(R, say, 'WARN', 'BlackBox vs archive', 'archive table has other column names - comparison skipped');
end

%% ---- 9c. Black-Box SysID Validation Audit (Dual Validation: 1-Step & Free-Run) ----
say('[RunAll] 9c. Auditing Black-Box SysID model and validation data ...');
bbMatFile = fullfile(root, 'EV_BlackBox_SysID.mat');
if ~isempty(result.runDir) && isfile(fullfile(result.runDir, 'EV_BlackBox_SysID.mat'))
    bbMatFile = fullfile(result.runDir, 'EV_BlackBox_SysID.mat');
end

if isfile(bbMatFile)
    try
        S_bb = load(bbMatFile);
        if isfield(S_bb, 'sys_blackbox') && isfield(S_bb, 'Zv') && isfield(S_bb, 'Ys') && isfield(S_bb, 'Y0')
            sys_m = S_bb.sys_blackbox;
            Zv_norm = S_bb.Zv;
            Ys_val = S_bb.Ys;
            Y0_val = S_bb.Y0;
            
            % Critical rule: Do NOT feed physical unscaled inputs to normalized model.
            % Zv_norm already contains normalized inputs and outputs.
            [yh_1step, fit_1step] = compare(Zv_norm, sys_m, 1);
            [yh_freerun, fit_freerun] = compare(Zv_norm, sys_m, Inf);
            
            % Convert outputs to physical engineering units (V, A)
            Y_true_phys = Zv_norm.OutputData .* Ys_val + Y0_val;
            Y_1step_phys = yh_1step.OutputData .* Ys_val + Y0_val;
            Y_freerun_phys = yh_freerun.OutputData .* Ys_val + Y0_val;
            
            % Calculate metrics separately for voltage and current
            err_1step = Y_true_phys - Y_1step_phys;
            err_freerun = Y_true_phys - Y_freerun_phys;
            
            rmse_1step = sqrt(mean(err_1step.^2, 1));
            mae_1step = mean(abs(err_1step), 1);
            bias_1step = mean(err_1step, 1);
            
            rmse_freerun = sqrt(mean(err_freerun.^2, 1));
            mae_freerun = mean(abs(err_freerun), 1);
            bias_freerun = mean(err_freerun, 1);
            
            % Percentage within +/-10% of physical mean
            tol_V = 0.10 * mean(abs(Y_true_phys(:,1)));
            tol_I = 0.10 * mean(abs(Y_true_phys(:,2)));
            pct_V_1step = 100 * mean(abs(err_1step(:,1)) <= tol_V);
            pct_I_1step = 100 * mean(abs(err_1step(:,2)) <= tol_I);
            pct_V_free = 100 * mean(abs(err_freerun(:,1)) <= tol_V);
            pct_I_free = 100 * mean(abs(err_freerun(:,2)) <= tol_I);
            
            say('[RunAll]    SysID 1-Step Validation  : Vbatt RMSE=%.4f V, MAE=%.4f V | Ibatt RMSE=%.2f A, MAE=%.2f A', ...
                rmse_1step(1), mae_1step(1), rmse_1step(2), mae_1step(2));
            say('[RunAll]    SysID Free-Run Simulation: Vbatt RMSE=%.4f V, MAE=%.4f V | Ibatt RMSE=%.2f A, MAE=%.2f A', ...
                rmse_freerun(1), mae_freerun(1), rmse_freerun(2), mae_freerun(2));
            say('[RunAll]    Raw NRMSE Fit (1-Step)   : Vbatt=%6.1f%%, Ibatt=%6.1f%%', fit_1step(1), fit_1step(2));
            say('[RunAll]    Raw NRMSE Fit (Free-Run) : Vbatt=%6.1f%%, Ibatt=%6.1f%%', fit_freerun(1), fit_freerun(2));
            say('[RunAll]    Samples in +/-10%% Tol   : Vbatt=%.1f%%, Ibatt=%.1f%% (Free-Run)', pct_V_free, pct_I_free);
            
            % Report 1-step and free-run results separately for each output
            outNames = {'Voltage', 'Current'};
            outUnits = {'V', 'A'};
            rmseThresh = [0.50, 5.00];
            pct_tol_1step = [pct_V_1step, pct_I_1step];
            pct_tol_free = [pct_V_free, pct_I_free];
            
            for k = 1:2
                % One-step prediction audit
                pass_1s = rmse_1step(k) <= rmseThresh(k);
                R = rarec(R, say, rapf(pass_1s, 'FAIL'), ...
                    sprintf('SysID %s Error (1-Step)', outNames{k}), ...
                    sprintf('RMSE = %.4f %s, MAE = %.4f %s, Bias = %+.4f %s, Fit = %6.1f%%, +/-10%% tol = %.1f%%', ...
                    rmse_1step(k), outUnits{k}, mae_1step(k), outUnits{k}, bias_1step(k), outUnits{k}, fit_1step(k), pct_tol_1step(k)));
                
                % Free-run simulation audit
                pass_fr = rmse_freerun(k) <= rmseThresh(k);
                R = rarec(R, say, rapf(pass_fr, 'FAIL'), ...
                    sprintf('SysID %s Error (Free-Run)', outNames{k}), ...
                    sprintf('RMSE = %.4f %s, MAE = %.4f %s, Bias = %+.4f %s, Fit = %6.1f%%, +/-10%% tol = %.1f%%', ...
                    rmse_freerun(k), outUnits{k}, mae_freerun(k), outUnits{k}, bias_freerun(k), outUnits{k}, fit_freerun(k), pct_tol_free(k)));
                
                % Raw NRMSE fit audit: flag negative fit without masking
                if fit_freerun(k) <= 0
                    R = rarec(R, say, 'WARN', sprintf('SysID %s Raw Fit (Free-Run)', outNames{k}), ...
                        sprintf('Raw NRMSE fit is negative (%6.1f%%); output variance is too small in steady-state validation', fit_freerun(k)));
                end
            end
            
            % Model stability audit
            stb_bb = isstable(sys_m);
            max_pole_bb = max(abs(pole(sys_m)));
            R = rarec(R, say, rapf(stb_bb, 'FAIL'), 'SysID Model Stability', ...
                sprintf('Max pole magnitude = %.4f (< 1.0 required)', max_pole_bb));
        else
            R = rarec(R, say, 'WARN', 'SysID Validation', 'EV_BlackBox_SysID.mat missing required fields');
        end
    catch ME_bb
        R = rarec(R, say, 'WARN', 'SysID Validation', ME_bb.message);
    end
else
    R = rarec(R, say, 'WARN', 'SysID Validation', 'EV_BlackBox_SysID.mat not found');
end

%% ---- 10. Unified graph generation (also invoked by the Simulink StopFcn) ---------------------
say('[RunAll] 10. Unified Battery/Motor/N4SID graphs ...');
if logical(rav('EV_DAQ_SkipGraphs', false)) || logical(rav('EV_Ref_Skip', false))
 say('[RunAll] PNG graph generation explicitly skipped (EV_DAQ_SkipGraphs/EV_Ref_Skip).');
else
 try
  graphDone=false;
  if rahas('EV_Graphs_Result')
   gr=evalin('base','EV_Graphs_Result');
   graphDone=isstruct(gr)&&isfield(gr,'runDir')&&strcmp(char(gr.runDir),char(result.runDir))&&isfield(gr,'status')&&strcmp(gr.status,'complete');
  end
  if ~graphDone
   if isempty(result.runDir)||~isfolder(result.runDir),error('RunAll:GraphRunDir','Current run folder unavailable.');end
   EV_Graphs('generate',C,result.runDir,struct());
  else,say('[RunAll] StopFcn already generated graphs; duplicate generation avoided.');end
  say('[RunAll] Graph folder: %s',fullfile(result.runDir,'Figures'));
 catch ME_graph,R=rarec(R,say,'WARN','Unified graph generation',ME_graph.message);end
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