function report = EV_Performance_Audit(varargin)
%EV_PERFORMANCE_AUDIT Read-only preflight audit for the EV Digital Twin.
%
%   report = EV_Performance_Audit
%   report = EV_Performance_Audit('Model','BLDCSpeedControl_EV_Layout_v2')
%
%   IMPORTANT:
%   - This function DOES NOT run or compile the model.
%   - It DOES NOT change/save any model blocks or battery/motor/controller parameters.
%   - Open the target model in Simulink first. A running/initializing model is reported.
%   - It checks configuration and likely causes of excessive run time; it cannot prove
%     numerical solver performance without a measured simulation.
%
%   Outputs:
%     results/EV_Performance_Audit_yyyymmdd_HHMMSS.txt
%     results/EV_Performance_Audit_yyyymmdd_HHMMSS.csv
%
%   MATLAB / Simulink R2024b compatible.

p = inputParser;
addParameter(p,'Model','BLDCSpeedControl_EV_Layout_v2',@(x)ischar(x)||isstring(x));
parse(p,varargin{:});
mdl = char(p.Results.Model);

if ~bdIsLoaded(mdl)
    error('EV_Performance_Audit:ModelNotLoaded', ...
        ['Model "%s" is not loaded. Open it in Simulink, wait for the editor to become Ready, ' ...
         'then run EV_Performance_Audit again. This audit deliberately does not load/compile models.'], mdl);
end

root = fileparts(get_param(mdl,'FileName'));
if isempty(root), root = pwd; end
resultDir = fullfile(root,'results');
if ~isfolder(resultDir), mkdir(resultDir); end
stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
txtFile = fullfile(resultDir,['EV_Performance_Audit_' stamp '.txt']);
csvFile = fullfile(resultDir,['EV_Performance_Audit_' stamp '.csv']);

rows = cell(0,4);
add('INFO','Audit mode','READ-ONLY; no compile; no simulation', ...
    'Use this report to identify configuration risks before a controlled short test.');
add('INFO','Model file',get_param(mdl,'FileName'),'Model content was not modified or saved.');

% Simulation state
state = safeGet(mdl,'SimulationStatus','unknown');
add(iif(strcmpi(state,'stopped'),'PASS','WARN'),'Simulation status',state, ...
    'Run the audit when the model is stopped for a reliable configuration snapshot.');

% Core model solver properties
solverProps = {'Solver','SolverType','StopTime','StartTime','FixedStep','MaxStep', ...
    'MinStep','RelTol','AbsTol','MaxConsecutiveMinStep','ZeroCrossControl', ...
    'AlgebraicLoopSolver','SimulationMode','FastRestart','SignalLogging'};
solver = struct();
for k = 1:numel(solverProps)
    solver.(solverProps{k}) = safeGet(mdl,solverProps{k},'<not exposed>');
    add('INFO',['Model.' solverProps{k}],solver.(solverProps{k}), ...
        'Read from current loaded model; no setting changed.');
end

% Stop time: model parameter versus base-workspace values.
modelStop = numericValue(solver.StopTime);
wsStop = baseValue('t_stop');
wsTs = baseValue('Ts');
wsTsc = baseValue('Tsc');
tsOverrideExists = baseExists('Ts_override');
tsOverride = baseValue('Ts_override');

if isfinite(modelStop) && modelStop > 0
    add('PASS','Model StopTime (s)',num2str(modelStop,'%.12g'), ...
        'The current loaded model is the run-time source unless code/callbacks override it.');
else
    add('FAIL','Model StopTime (s)',stringValue(solver.StopTime), ...
        'StopTime must resolve to a positive finite scalar.');
end
if isfinite(wsStop) && wsStop > 0
    status = 'PASS';
    rec = 'Compare with Model.StopTime; RunAll and builder callbacks may update one from the other.';
    if isfinite(modelStop) && abs(wsStop-modelStop) > max(1e-9,1e-6*modelStop)
        status = 'WARN';
        rec = 'WORKSPACE t_stop differs from model StopTime. Check RunAll, StartFcn and EV_LastStopTime.txt for overrides.';
    end
    add(status,'Workspace t_stop (s)',num2str(wsStop,'%.12g'),rec);
else
    add('WARN','Workspace t_stop',stringValue(wsStop), ...
        'Variable absent or not a positive scalar; check which run configuration supplies StopTime.');
end

if isfinite(wsTs) && wsTs > 0
    add('PASS','Workspace Ts (s)',num2str(wsTs,'%.12g'), ...
        'Fundamental/project sample-time value; not necessarily the adaptive solver step.');
    if isfinite(modelStop) && modelStop > 0
        nominalSteps = modelStop/wsTs;
        if nominalSteps > 1e8
            add('FAIL','Nominal StopTime/Ts step count',num2str(nominalSteps,'%.6g'), ...
                'Extremely high nominal count. Verify units and the source of Ts before simulating.');
        elseif nominalSteps > 1e7
            add('WARN','Nominal StopTime/Ts step count',num2str(nominalSteps,'%.6g'), ...
                'Very high nominal count. Confirm this is intended before a full run.');
        else
            add('PASS','Nominal StopTime/Ts step count',num2str(nominalSteps,'%.6g'), ...
                'Arithmetic estimate only; variable-step solvers and Simscape switching can take many more steps.');
        end
    end
else
    add('WARN','Workspace Ts (s)',stringValue(wsTs), ...
        'Ts is missing or invalid; inspect BLDCSpeedControlData.m and workspace overrides.');
end
if isfinite(wsTsc) && wsTsc > 0
    add('INFO','Workspace Tsc (s)',num2str(wsTsc,'%.12g'), ...
        'Compare the PWM/control period to the model solver/sample-time configuration.');
    if isfinite(wsTs) && wsTs > 0 && wsTsc < wsTs
        add('WARN','Tsc versus Ts','Tsc < Ts', ...
            'Control/PWM period is shorter than the configured fundamental sample time; verify intended multi-rate timing.');
    end
else
    add('INFO','Workspace Tsc (s)',stringValue(wsTsc), ...
        'No valid Tsc value was available in the base workspace.');
end
if tsOverrideExists
    add('WARN','Ts_override',stringValue(tsOverride), ...
        'A test override is present in the base workspace. Clear it only after confirming no active benchmark depends on it.');
else
    add('PASS','Ts_override','not present','No Ts_override variable is currently present.');
end

% Variable-step solver details: FixedStep is typically ignored in this mode.
solverType = lower(stringValue(solver.SolverType));
if contains(solverType,'variable')
    add('INFO','Solver-step interpretation','Variable-step solver', ...
        'FixedStep is normally not the active integration step here; inspect MaxStep, MinStep and Simscape local solvers.');
    maxStep = numericValue(solver.MaxStep);
    if isfinite(maxStep) && maxStep > 0 && isfinite(wsTs) && wsTs > 0 && maxStep < wsTs/100
        add('WARN','MaxStep relative to Ts',sprintf('MaxStep=%g, Ts=%g',maxStep,wsTs), ...
            'The maximum solver step is much smaller than Ts. Verify the restriction is required by switching events/physics.');
    end
end
minStep = numericValue(solver.MinStep);
if isfinite(minStep) && minStep > 0 && isfinite(wsTs) && wsTs > 0 && minStep < wsTs/1e6
    add('WARN','MinStep relative to Ts',sprintf('MinStep=%g, Ts=%g',minStep,wsTs), ...
        'A very small configured minimum step can contribute to extreme runtimes in difficult solver regions.');
end

% Collect model/block counts and visible sample-time settings without compiling.
try
    blocks = find_system(mdl,'Type','Block','LookUnderMasks','all','FollowLinks','off');
    blocks = blocks(~strcmp(blocks,mdl));
catch ME
    blocks = {};
    add('WARN','Block enumeration failed',ME.message, ...
        'Review model access and masked subsystem settings; this audit did not compile the model.');
end
add('INFO','Block count',num2str(numel(blocks)), ...
    'Counts blocks visible through masked subsystems; linked library internals are not expanded.');
sampleBlocks = {};
sampleVals = {};
solverConfigBlocks = {};
pwmLikeBlocks = {};
for k = 1:numel(blocks)
    b = blocks{k};
    bn = '';
    try, bn = get_param(b,'Name'); catch, end
    lowName = lower([b ' ' bn]);
    lowName = regexprep(lowName,'[\r\n]+',' ');
    if contains(lowName,'solver configuration') || contains(lowName,'solverconfiguration')
        solverConfigBlocks{end+1,1} = b; %#ok<AGROW>
    end
    if contains(lowName,'pwm') || contains(lowName,'pulse generator') || ...
            contains(lowName,'carrier') || contains(lowName,'repetitive sequence')
        pwmLikeBlocks{end+1,1} = b; %#ok<AGROW>
    end
    try
        st = get_param(b,'SampleTime');
        sv = stringValue(st);
        if ~isempty(sv) && ~strcmp(sv,'-1') && ~strcmpi(sv,'inherited')
            sampleBlocks{end+1,1} = b; %#ok<AGROW>
            sampleVals{end+1,1} = sv; %#ok<AGROW>
            nst = numericValue(st);
            if isfinite(nst) && nst > 0 && nst < 1e-8
                add('WARN','Very small block sample time',sprintf('%s : %g s',b,nst), ...
                    'Confirm this sample time is needed; a very small discrete rate may dominate execution time.');
            end
        end
    catch
    end
end
add('INFO','Blocks with explicit SampleTime',num2str(numel(sampleBlocks)), ...
    'The audit lists only exposed block parameters and does not propagate compiled sample times.');
if ~isempty(sampleVals)
    [sampleKinds,~,sampleGroup] = unique(sampleVals);
    sampleCounts = accumarray(sampleGroup,1);
    [sampleCounts,sortOrder] = sort(sampleCounts,'descend');
    for k = 1:min(30,numel(sortOrder))
        j = sortOrder(k);
        add('INFO','SampleTime frequency',sampleKinds{j}, ...
            sprintf('%d block(s) expose this SampleTime value. This is not compiled-rate propagation.',sampleCounts(k)));
    end
end
for k = 1:min(numel(solverConfigBlocks),30)
    b = solverConfigBlocks{k};
    val = {};
    for prop = {'UseLocalSolver','LocalSolverChoice','LocalSolverSampleTime','LocalSolverSampleTimeSpecified'}
        v = safeGet(b,prop{1},'n/a');
        if ~strcmp(v,'n/a'), val{end+1} = [prop{1} '=' v]; end %#ok<AGROW>
    end
    add('INFO','Simscape Solver Configuration',b, ...
        ['Exposed settings: ' strjoin(val,', ') '. Check for unintended local solver sample times.']);
end
if isempty(solverConfigBlocks)
    add('WARN','Simscape Solver Configuration','No block found by name', ...
        'Search the model manually if Simscape physical networks are present; name-based discovery can miss custom names.');
end
for k = 1:min(numel(pwmLikeBlocks),60)
    b = pwmLikeBlocks{k};
    per = safeGet(b,'Period','n/a');
    freq = safeGet(b,'Frequency','n/a');
    add('INFO','PWM/pulse-like block',b,sprintf('Period=%s; Frequency=%s',per,freq));
end
if isempty(pwmLikeBlocks)
    add('INFO','PWM/pulse-like blocks','none detected by block names', ...
        'The PWM implementation may use masked/library blocks whose names do not contain PWM or carrier.');
end

% Callback scan: detect potentially long-running or blocking callback code.
callbackNames = {'PreLoadFcn','PostLoadFcn','InitFcn','StartFcn','StopFcn','CloseFcn', ...
    'PreSaveFcn','PostSaveFcn','PauseFcn','ContinueFcn','LoadFcn','ModelCloseFcn'};
riskPattern = '(?i)(\bpause\s*\(|\bwaitfor\s*\(|\buiwait\s*\(|\binput\s*\(|\bkeyboard\b|\bwhile\s+|for\s+\w+\s*=\s*1\s*:\s*inf)';
for k = 1:numel(callbackNames)
    cbn = callbackNames{k};
    cb = safeGet(mdl,cbn,'');
    if isempty(cb), continue, end
    risk = ~isempty(regexp(cb,riskPattern,'once'));
    if risk
        add('WARN',['Callback scan: ' cbn],'Potential wait/loop/input detected', ...
            'Inspect the callback manually. Do not remove project hooks blindly; identify the exact blocking operation first.');
    else
        add('INFO',['Callback scan: ' cbn],'non-empty callback', ...
            ['Review callback if start/compile stalls. Prefix: ' clip(cb,180)]);
    end
end

% Diagnostic interpretation: timeout setting in RunAll does not cover synchronous compile/start call.
add('WARN','RunAll start timeout coverage', ...
    'The current RunAll status-loop timeout starts only AFTER set_param(...,''SimulationCommand'',''start'') returns.', ...
    'If Simulink blocks inside the start call during compilation/initialization, the polling timeout cannot interrupt that phase. Record InitFcn/StartFcn timestamps or run a separate controlled compile test.');
add('INFO','Known runtime benchmark from project source', ...
    'Builder code documents ~283 s for 0.5 s simulated time at Ts=1e-5 s.', ...
    'A 0.4 s run is roughly 226 s by linear scaling only. A 30-hour wait is not explained by nominal StopTime/Ts count; isolate compile/start, solver, and StopFcn post-processing separately.');

T = cell2table(rows,'VariableNames',{'Status','Check','Value','Recommendation'});
report = struct('Model',mdl,'ModelFile',get_param(mdl,'FileName'), ...
    'Timestamp',char(datetime('now')),'Table',T,'TextFile',txtFile,'CSVFile',csvFile);

fid = fopen(txtFile,'w');
if fid < 0, error('EV_Performance_Audit:ReportOpen','Cannot write audit report: %s',txtFile); end
closer = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'EV DIGITAL TWIN - READ-ONLY PERFORMANCE / CONFIGURATION AUDIT\n');
fprintf(fid,'Timestamp: %s\nModel: %s\nFile: %s\n',report.Timestamp,mdl,report.ModelFile);
fprintf(fid,'No model compilation or simulation was started by this audit.\n\n');
for k = 1:height(T)
    fprintf(fid,'[%s] %s\n  Value: %s\n  Action: %s\n\n',T.Status{k},T.Check{k},T.Value{k},T.Recommendation{k});
end
writetable(T,csvFile);
fprintf('\n[EV_AUDIT] Read-only checks complete. No compile/simulation was run.\n');
fprintf('[EV_AUDIT] Text report: %s\n[EV_AUDIT] CSV report : %s\n',txtFile,csvFile);
disp(T);

    function add(status,check,value,recommendation)
        rows(end+1,:) = {char(status),char(check),clip(value,1000),char(recommendation)}; %#ok<AGROW>
    end
end

function v = safeGet(obj,prop,default)
v = default;
try
    q = get_param(obj,prop);
    v = stringValue(q);
catch
end
end

function v = baseValue(name)
v = NaN;
try
    if evalin('base',sprintf('exist(''%s'',''var'')',name)) == 1
        x = evalin('base',name);
        v = numericValue(x);
    end
catch
end
end

function tf = baseExists(name)
tf = false;
try, tf = evalin('base',sprintf('exist(''%s'',''var'')',name)) == 1; catch, end
end

function n = numericValue(v)
n = NaN;
try
    if isnumeric(v) && isscalar(v) && isfinite(v)
        n = double(v);
    elseif islogical(v) && isscalar(v)
        n = double(v);
    elseif ischar(v) || isstring(v)
        s = strtrim(char(v));
        x = str2double(s);
        if isfinite(x), n = x; end
    end
catch
end
end

function s = stringValue(v)
if isempty(v)
    s = '';
elseif isnumeric(v) || islogical(v)
    if isscalar(v), s = num2str(v,16); else, s = mat2str(v); end
elseif ischar(v)
    s = v;
elseif isstring(v)
    s = char(strjoin(v(:)',', '));
else
    try, s = char(string(v)); catch, s = class(v); end
end
end

function s = clip(s,n)
s = regexprep(stringValue(s),'[\r\n]+',' ');
if numel(s) > n, s = [s(1:n-3) '...']; end
end

function out = iif(c,a,b)
if c, out = a; else, out = b; end
end
