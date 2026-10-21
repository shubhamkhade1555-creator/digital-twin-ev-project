function R = Run_Simulation_Log(varargin)
%RUN_SIMULATION_LOG  Run the FINAL model fast and save the engineering logs.
%
%   Run_Simulation_Log                       Profile 'fast' (Accelerator mode)
%   Run_Simulation_Log('Profile','turbo')    Accelerator + larger solver step Ts = 2e-5
%   Run_Simulation_Log('Profile','normal')   Normal mode (slowest, no code build)
%   Run_Simulation_Log('StopTime',0.5)       override the stop time [s]
%
%   Output folder:  Simulation_Logs/Run_<timestamp>/
%     Summary.txt                   timing + V&V checks
%     Parameters.csv                BLDCSpeedControlData parameters used
%     EV_Telemetry_1ms.csv          engineering log, 1 ms grid
%     BlackBox_Telemetry_100ms.csv  same EV_Telemetry fields, 100 ms grid
%     Overview.png                  4-panel plot
%     complete_run.mat              raw model outputs + both telemetry tables
%
%   Internal option 'FromBase',true logs the To Workspace variables that a run in
%   the base workspace has already produced (used by Run_Simulation_Live), so the
%   live run and the log run share this ONE logger.

p = inputParser;
addParameter(p, 'Profile',  'fast');
addParameter(p, 'StopTime', []);
addParameter(p, 'FromBase', false);
addParameter(p, 'RunDir',   '');
parse(p, varargin{:});
prof = lower(p.Results.Profile);

root = fileparts(mfilename('fullpath'));
cd(root);  addpath(root);
mdl = 'BLDCSpeedControl_EV_Layout_FINAL';
if ~isfile(fullfile(root, [mdl '.slx'])), error('Run Create_Simulation first (FINAL model not found).'); end

evalin('base', 'BLDCSpeedControlData;');
load_system(mdl);
nSer = bv('cells_series', 13);   nPar = bv('cells_parallel', 10);

%% ---- run (or take the data from the base workspace) -----------------------
out = [];  wall = NaN;  usedMode = 'base workspace';
if ~p.Results.FromBase
    stopT = p.Results.StopTime;
    if isempty(stopT), stopT = bv('t_stop', 2); end
    mode = 'accelerator';  if strcmp(prof, 'normal'), mode = 'normal'; end
    for attempt = 1:2
        in = Simulink.SimulationInput(mdl);
        in = in.setModelParameter('SimulationMode', mode, 'StopTime', num2str(stopT, 12));
        if strcmp(prof, 'turbo'), in = in.setVariable('Ts', 2e-5); end
        fprintf('[RUN] %s mode, StopTime = %g s ... \n', mode, stopT);
        tic;
        try
            out = sim(in);
            wall = toc;  usedMode = mode;  break
        catch ME
            if attempt == 2 || strcmp(mode, 'normal'), rethrow(ME); end
            fprintf('[RUN] Accelerator failed (%s)\n[RUN] -> retrying in Normal mode.\n', strtrim(ME.message));
            mode = 'normal';
        end
    end
end

%% ---- collect the signals ----------------------------------------------------
keys = {'vbatt','ibatt','temp','soc','vdc','rpm_ref','rpm','imotor','torque','wheel'};
vars = {'log_vcell','log_icell','temperature','log_soc','log_vdc_m','log_rpm_ref','log_rpm', ...
        'log_idc_f','log_tq_meas','log_omega_wheel'};
tw   = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'Variants', 'AllVariants', 'BlockType', 'ToWorkspace');
twNames = cellfun(@(b) strtrim(get_param(b, 'VariableName')), tw, 'UniformOutput', false);
tout = [];
if ~isempty(out), try, tout = out.tout; catch, end, end

S = struct();  tEnd = 0;
for k = 1:numel(keys)
    j = find(strcmpi(twNames, vars{k}), 1);
    S.(keys{k}).t = [];  S.(keys{k}).y = [];
    if isempty(j), continue, end
    x = fetchVar(out, twNames{j}, p.Results.FromBase);
    if isempty(x), continue, end
    [t, Y] = toSeries(x, tout);
    S.(keys{k}).t = t;  S.(keys{k}).y = Y;
    if ~isempty(t), tEnd = max(tEnd, t(end)); end
end
if isempty(S.rpm.t), error('log_rpm not found - nothing to log. Did the simulation run?'); end

%% ---- telemetry tables --------------------------------------------------------
names = {'Time','BatteryVoltage','BatteryCurrent','BatteryTemperature','SOC','BatteryPower', ...
    'DCLinkVoltage','DCLinkCurrent','RPMReference','RPM','MotorCurrent','Torque','WheelSpeed', ...
    'MechanicalPower','Efficiency','RPM_Error'};
T1 = buildTel((0:1e-3:tEnd).', S, nSer, nPar, names);      % engineering 1 ms grid
T2 = buildTel((0:0.1:tEnd).',  S, nSer, nPar, names);      % black box 100 ms grid

%% ---- save ----------------------------------------------------------------------
runDir = p.Results.RunDir;
if isempty(runDir)
    runDir = fullfile(root, 'Simulation_Logs', ['Run_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
end
if ~isfolder(runDir), mkdir(runDir); end
writetable(T1, fullfile(runDir, 'EV_Telemetry_1ms.csv'));
writetable(T2, fullfile(runDir, 'BlackBox_Telemetry_100ms.csv'));

pn = {'Kt','I_cont','I_peak','Ts','Tsc','Vdc','Kpw','Kiw','rpm_ref','rpm_ramp','t_stop', ...
      'pack_Ah','cells_series','cells_parallel','gear_ratio','r_wheel'};
pv = cellfun(@(n) bv(n, NaN), pn).';
writetable(table(pn.', pv, 'VariableNames', {'Parameter','Value'}), fullfile(runDir, 'Parameters.csv'));

vv = checks(T1, nSer, bv('I_cont', 30), bv('I_peak', 40));
rtf = tEnd / wall;
fid = fopen(fullfile(runDir, 'Summary.txt'), 'w');
fprintf(fid, 'EV digital twin run  %s\nModel: %s   mode: %s   profile: %s\n', runDir, mdl, usedMode, prof);
fprintf(fid, 'Simulated time : %.3f s\nWall-clock     : %.1f s\nSpeed          : %.3f sim-s per wall-s\n\n', tEnd, wall, rtf);
fprintf(fid, 'V&V (limits from BLDCSpeedControlData.m)\n');
for k = 1:size(vv, 1), fprintf(fid, '  %-28s %-5s %s\n', vv{k,1}, vv{k,2}, vv{k,3}); end
fprintf(fid, '\nSignals not supplied by the model are NaN: ');
fprintf(fid, '%s ', names{all(isnan(T1{:, :}), 1)}); fprintf(fid, '\n');
fclose(fid);

try
    fg = figure('Visible', 'off', 'Position', [50 50 1200 800]);
    subplot(2,2,1); plot(T2.Time, T2.RPMReference, '--', T2.Time, T2.RPM); grid on; title('RPM'); legend('ref','motor');
    subplot(2,2,2); yyaxis left; plot(T2.Time, T2.BatteryVoltage); yyaxis right; plot(T2.Time, T2.BatteryCurrent); grid on; title('Battery');
    subplot(2,2,3); yyaxis left; plot(T2.Time, T2.Torque); yyaxis right; plot(T2.Time, T2.MotorCurrent); grid on; title('Motor');
    subplot(2,2,4); plot(T2.Time, T2.SOC); grid on; title('SOC');
    saveas(fg, fullfile(runDir, 'Overview.png'));  close(fg);
catch
end
EV_Telemetry_1ms = T1;  EV_Telemetry_100ms = T2;                       %#ok<NASGU>
save(fullfile(runDir, 'complete_run.mat'), 'out', 'S', 'EV_Telemetry_1ms', 'EV_Telemetry_100ms', '-v7.3');

R = struct('RunDir', runDir, 'Wall_s', wall, 'SimTime_s', tEnd, 'Mode', usedMode, 'VV', {vv});
fprintf('\n[RUN] Done: %.3f s simulated in %.1f s (%.3f sim-s per wall-s).\n[RUN] Logs: %s\n', tEnd, wall, rtf, runDir);
for k = 1:size(vv, 1), fprintf('      %-28s %-5s %s\n', vv{k,1}, vv{k,2}, vv{k,3}); end
end

% =========================================================================
function v = bv(name, default)
try
    v = evalin('base', name);
    if ~isnumeric(v) || ~isscalar(v), v = default; end
catch
    v = default;
end
end

function x = fetchVar(out, name, fromBase)
x = [];
try
    if fromBase
        if evalin('base', sprintf('exist(''%s'',''var'')', name)), x = evalin('base', name); end
    elseif any(strcmp(out.getElementNames, name))
        x = out.get(name);
    end
catch
end
end

function [t, Y] = toSeries(x, tout)
if isa(x, 'timeseries')
    t = x.Time(:);  d = x.Data;  sz = size(d);
    if x.IsTimeFirst, Y = reshape(d, sz(1), []); else, Y = reshape(d, [], sz(end)).'; end
elseif isstruct(x) && isfield(x, 'time')
    t = x.time(:);  d = x.signals(1).values;  Y = reshape(d, numel(t), []);
else
    t = tout(:);  Y = reshape(x, numel(t), []);
end
Y = double(Y);
end

function y = onGrid(sig, tg, key, nSer, nPar)
y = nan(size(tg));
if isempty(sig.t), return, end
Y = sig.y;
switch key
    case 'vbatt', if size(Y,2) > 1, Y = sum(Y, 2); else, Y = Y * nSer; end
    case 'ibatt', Y = mean(Y, 2) * nPar;
    case {'soc','temp'}, Y = mean(Y, 2);
    otherwise, Y = Y(:, 1);
end
[tu, iu] = unique(sig.t(:));
y = interp1(tu, Y(iu), tg, 'linear', NaN);
end

function T = buildTel(tg, S, nSer, nPar, names)
g  = @(k) onGrid(S.(k), tg, k, nSer, nPar);
vb = g('vbatt'); ib = g('ibatt'); rp = g('rpm'); tq = g('torque'); ref = g('rpm_ref');
pb = abs(vb .* ib);
pm = abs(tq) .* rp * 2*pi/60;
eff = 100 * pm ./ pb;  eff(pb <= 1) = NaN;
M = [tg, vb, ib, g('temp'), g('soc'), pb, g('vdc'), nan(size(tg)), ref, rp, g('imotor'), tq, g('wheel'), pm, eff, ref - rp];
T = array2table(M, 'VariableNames', names);
end

function vv = checks(T, nSer, Icont, Ipeak)
Vmax = nSer * 4.19 + 0.1;                         % BLDCSpeedControlData.m: full-charge pack
late = T.Time >= 0.9 * T.Time(end);
fr = mean(T.RPM(late), 'omitnan');
vv = {};
vv(end+1,:) = {'Final speed 2900..3000 rpm', pf(fr >= 2900 && fr <= 3000), sprintf('mean last 10%% = %.1f rpm', fr)};
vv(end+1,:) = {'Peak speed <= 3000 rpm',     pf(max(T.RPM) <= 3000),        sprintf('max = %.1f rpm', max(T.RPM))};
im = max(abs(T.MotorCurrent));
if isnan(im), st = 'n/a'; elseif im > Ipeak, st = 'FAIL'; elseif im > Icont, st = 'WARN'; else, st = 'PASS'; end
vv(end+1,:) = {sprintf('Motor current (cont %g / peak %g A)', Icont, Ipeak), st, sprintf('max = %.1f A', im)};
vm = max(T.BatteryVoltage(T.Time > 2e-3));
vv(end+1,:) = {sprintf('Pack voltage <= %.1f V', Vmax), pf(vm <= Vmax), sprintf('max = %.2f V', vm)};
s = T.SOC(isfinite(T.SOC));
if isempty(s)
    vv(end+1,:) = {'SOC within 0..1, not increasing', 'n/a', 'no SOC logged'};
else
    vv(end+1,:) = {'SOC within 0..1, not increasing', pf(all(s >= 0 & s <= 1) && all(diff(s) <= 1e-9)), ...
        sprintf('%.4f -> %.4f', s(1), s(end))};
end
end

function s = pf(c)
if isempty(c) || isnan(c), s = 'n/a'; elseif c, s = 'PASS'; else, s = 'FAIL'; end
end
