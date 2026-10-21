function R = EV_BlackBox_ComparePlotsV2(Clean, runDir)
%EV_BLACKBOX_COMPAREPLOTSV2 Plot-only V2 workflow for EV simulation + SysID.
% MATLAB R2024b. No App Designer dashboard is created.
%
% Usage:
%   R = EV_BlackBox_ComparePlotsV2(Clean, runDir)
%   R = EV_BlackBox_ComparePlotsV2([], "Simulation Logs/EV_RUN_...")
%
% Generates source-labelled figures under <runDir>/Figures_BlackBox_V2:
%   Battery: simulation voltage/current/SOC/temperature/cell voltage if available
%   Motor: reference vs actual RPM, motor current, torque, DC-link voltage
%   SystemIdentification: validation measured-vs-1-step/free-run predictions,
%                        residuals, plus a metrics CSV.
%
% The identified model in this project predicts ONLY battery voltage and
% battery current from RPM and MotorCurrent. SOC is Coulomb-counted outside
% this model; temperature is omitted unless a real logged signal exists.
% No illustrative reference curves are generated here.

if nargin < 1, Clean = []; end
if nargin < 2, runDir = ""; end
if isempty(runDir)
    runDir = findLatestRun(pwd);
end
runDir = char(runDir);
assert(isfolder(runDir), 'EV_BBPlots:RunFolder', 'Run folder not found: %s', runDir);

if isempty(Clean)
    Clean = loadCleanTable(runDir);
end
assert(istable(Clean) || istimetable(Clean), ...
    'EV_BBPlots:CleanType', 'Clean data must be a table or timetable.');

if istimetable(Clean)
    tt = Clean.Properties.RowTimes;
    if isduration(tt), t = seconds(tt); else, t = seconds(tt - tt(1)); end
    C = timetable2table(Clean, 'ConvertRowTimes', false);
else
    C = Clean;
    t = getcol(C, {'Time','time','t_s','Time_s'});
end
t = double(t(:));
assert(numel(t) == height(C) && numel(t) >= 3 && all(isfinite(t)), ...
    'EV_BBPlots:Time', 'Clean data needs a finite Time column.');
assert(all(diff(t) > 0), 'EV_BBPlots:TimeOrder', 'Time must be strictly increasing.');

outRoot = fullfile(runDir, 'Figures_BlackBox_V2');
dirs = {fullfile(outRoot,'Battery'), fullfile(outRoot,'Motor'), ...
        fullfile(outRoot,'SystemIdentification')};
for k = 1:numel(dirs)
    if ~isfolder(dirs{k}), mkdir(dirs{k}); end
end

created = {};
% Battery plant signals: plot only channels that are actually present.
created = addSeriesPlot(C, t, dirs{1}, created, ...
    {'BatteryVoltage','Vbatt_V','Vbat'}, 'BatteryVoltage_Simulation.png', ...
    'Battery voltage - Simulink plant', 'Voltage [V]');
created = addSeriesPlot(C, t, dirs{1}, created, ...
    {'BatteryCurrent','Ibatt_A','Ibat'}, 'BatteryCurrent_Simulation.png', ...
    'Battery discharge current - Simulink plant', 'Current [A]');
created = addSeriesPlot(C, t, dirs{1}, created, ...
    {'SOC','StateOfCharge','BatterySOC'}, 'SOC_Simulation.png', ...
    'Battery state of charge - source-labelled signal', 'SOC [0..1]');
created = addSeriesPlot(C, t, dirs{1}, created, ...
    {'BatteryTemperature','BatteryTemp','Temperature'}, 'BatteryTemperature_Simulation.png', ...
    'Battery temperature - logged signal only', 'Temperature [deg C]');
created = addSeriesPlot(C, t, dirs{1}, created, ...
    {'CellVoltage','BatteryCellVoltage','Vcell'}, 'BatteryCellVoltage_Simulation.png', ...
    'Battery cell voltage - logged signal only', 'Voltage [V]');

% Motor / drivetrain plant signals. No motor prediction is claimed by this
% battery-only identified model.
rpm = getcolOptional(C, {'RPM','MotorRPM','MotorSpeed'});
rpmRef = getcolOptional(C, {'RPMReference','RPM_Reference','rpm_ref','SpeedReference'});
if ~isempty(rpm) && ~isempty(rpmRef)
    f = newFig();
    plot(t, rpmRef, '--', 'LineWidth', 1.4, 'DisplayName','RPM reference'); hold on;
    plot(t, rpm, 'LineWidth', 1.4, 'DisplayName','Actual simulated RPM');
    finishFig(f, fullfile(dirs{2},'MotorRPM_Reference_vs_Actual.png'), ...
        'Motor speed tracking - Simulink plant', 'Time [s]', 'Speed [rpm]');
    created{end+1} = fullfile(dirs{2},'MotorRPM_Reference_vs_Actual.png');
else
    created = addSeriesPlot(C, t, dirs{2}, created, ...
        {'RPM','MotorRPM','MotorSpeed'}, 'MotorRPM_Simulation.png', ...
        'Motor speed - Simulink plant', 'Speed [rpm]');
end
created = addSeriesPlot(C, t, dirs{2}, created, ...
    {'MotorCurrent','Imotor','I_motor'}, 'MotorCurrent_Simulation.png', ...
    'Motor current - logged input to battery model', 'Current [A]');
created = addSeriesPlot(C, t, dirs{2}, created, ...
    {'MotorTorque','Torque','Tmotor'}, 'MotorTorque_Simulation.png', ...
    'Motor torque - logged signal only', 'Torque [N m]');
created = addSeriesPlot(C, t, dirs{2}, created, ...
    {'DCLinkVoltage','Vdc','DC_Link_Voltage'}, 'DCLinkVoltage_Simulation.png', ...
    'DC-link voltage - Simulink plant', 'Voltage [V]');

% System Identification validation: use the normalized validation data stored
% by EV_SysID_Auto. compare() predictions are converted back to physical units.
modelFile = fullfile(runDir, 'EV_BlackBox_SysID.mat');
if isfile(modelFile)
    S = load(modelFile);
    needed = {'sys_blackbox','Zv','Ys','Y0'};
    assert(all(isfield(S,needed)), 'EV_BBPlots:ModelFields', ...
        'SysID MAT file is missing one or more required fields: %s', strjoin(needed,', '));
    sys = S.sys_blackbox; Zv = S.Zv;
    Ts = sys.Ts;
    [y1, fit1] = compare(Zv, sys, 1);
    [yf, fitf] = compare(Zv, sys, Inf);
    yTrue = double(Zv.OutputData) .* reshape(S.Ys,1,[]) + reshape(S.Y0,1,[]);
    yOne = double(y1.OutputData) .* reshape(S.Ys,1,[]) + reshape(S.Y0,1,[]);
    yFree = double(yf.OutputData) .* reshape(S.Ys,1,[]) + reshape(S.Y0,1,[]);
    nVal = size(yTrue,1);
    tVal = t(end) - (nVal-1:-1:0)' .* Ts;
    names = {'Battery voltage','Battery current'};
    units = {'V','A'};
    safeNames = {'Voltage','Current'};
    metrics = cell(0,8);

    for j = 1:2
        f = newFig();
        plot(tVal, yTrue(:,j), 'k', 'LineWidth',1.5, 'DisplayName','Measured / Simulink validation'); hold on;
        plot(tVal, yOne(:,j), '--', 'LineWidth',1.3, 'DisplayName','Black-box one-step prediction');
        plot(tVal, yFree(:,j), '-.', 'LineWidth',1.3, 'DisplayName','Black-box free-run simulation');
        finishFig(f, fullfile(dirs{3},['Validation_' safeNames{j} '_Measured_vs_Predicted.png']), ...
            [names{j} ' - validation comparison'], 'Time [s]', [names{j} ' [' units{j} ']']);
        created{end+1} = fullfile(dirs{3},['Validation_' safeNames{j} '_Measured_vs_Predicted.png']);

        e1 = yTrue(:,j)-yOne(:,j); ef = yTrue(:,j)-yFree(:,j);
        f = newFig();
        plot(tVal, e1, '--', 'LineWidth',1.25, 'DisplayName','One-step residual'); hold on;
        plot(tVal, ef, '-.', 'LineWidth',1.25, 'DisplayName','Free-run residual');
        yline(0,':k','DisplayName','Zero error');
        finishFig(f, fullfile(dirs{3},['Residual_' safeNames{j} '.png']), ...
            [names{j} ' prediction residuals'], 'Time [s]', ['Measured - predicted [' units{j} ']']);
        created{end+1} = fullfile(dirs{3},['Residual_' safeNames{j} '.png']);

        metrics(end+1,:) = {names{j}, units{j}, ...
            sqrt(mean(e1.^2,'omitnan')), mean(abs(e1),'omitnan'), mean(e1,'omitnan'), ...
            sqrt(mean(ef.^2,'omitnan')), mean(abs(ef),'omitnan'), mean(ef,'omitnan')}; %#ok<AGROW>
    end
    Metrics = cell2table(metrics, 'VariableNames', ...
        {'Output','Unit','OneStep_RMSE','OneStep_MAE','OneStep_Bias','FreeRun_RMSE','FreeRun_MAE','FreeRun_Bias'});
    writetable(Metrics, fullfile(dirs{3},'SysID_Validation_Metrics.csv'));
    created{end+1} = fullfile(dirs{3},'SysID_Validation_Metrics.csv');

    % Order-sweep plot if sweep results exist in the MAT file.
    if isfield(S,'sweep') && ~isempty(S.sweep) && size(S.sweep,2) >= 7
        sw = S.sweep;
        f = newFig();
        plot(sw(:,1),sw(:,3),'o-', 'DisplayName','Voltage 1-step fit'); hold on;
        plot(sw(:,1),sw(:,4),'o-', 'DisplayName','Current 1-step fit');
        plot(sw(:,1),sw(:,5),'s--','DisplayName','Voltage free-run fit');
        plot(sw(:,1),sw(:,6),'s--','DisplayName','Current free-run fit');
        yline(0,':k','DisplayName','Zero fit');
        finishFig(f, fullfile(dirs{3},'SysID_ModelOrder_Fit_Comparison.png'), ...
            'System Identification model-order comparison', 'Model order [states]', 'Raw fit [%]');
        created{end+1} = fullfile(dirs{3},'SysID_ModelOrder_Fit_Comparison.png');
    end
else
    warning('EV_BBPlots:NoModel', ...
        'No EV_BlackBox_SysID.mat in %s. Simulation plots were created; SysID comparison plots skipped.', runDir);
end

% Machine-readable manifest: identifies the run and every generated output.
fid = fopen(fullfile(outRoot,'PLOT_MANIFEST.txt'),'w');
if fid >= 0
    fprintf(fid,'EV Black-Box Comparison Plots V2\nRun folder: %s\n', runDir);
    fprintf(fid,'Generated: %s\n', char(datetime('now')));
    fprintf(fid,'Model outputs available in this SysID workflow: battery voltage and battery current.\n');
    fprintf(fid,'SOC is outside the linear model; temperature is plotted only if logged.\n');
    fprintf(fid,'Motor RPM/current/torque are plant signals; this model does not predict them.\n\nFiles:\n');
    for k = 1:numel(created), fprintf(fid,'%s\n',created{k}); end
    fclose(fid);
end
R = struct('ok',true,'runDir',runDir,'outputDir',outRoot,'files',{created});
fprintf('[EV_BBPlotsV2] Created %d plot/report files in:\n  %s\n',numel(created),outRoot);
end

function out = addSeriesPlot(C,t,folder,out,aliases,fileName,ttl,ylab)
x = getcolOptional(C, aliases);
if isempty(x), return; end
f = newFig();
plot(t,x,'LineWidth',1.35,'DisplayName','Simulink logged signal');
finishFig(f,fullfile(folder,fileName),ttl,'Time [s]',ylab);
out{end+1} = fullfile(folder,fileName);
end

function x = getcol(C,aliases)
x = getcolOptional(C,aliases);
assert(~isempty(x),'EV_BBPlots:MissingTime','No Time column found.');
end

function x = getcolOptional(C,aliases)
x = [];
if ~istable(C), return; end
vn = C.Properties.VariableNames;
for k = 1:numel(aliases)
    ix = find(strcmpi(vn,aliases{k}),1);
    if ~isempty(ix)
        x = C.(vn{ix});
        if iscell(x), x = cellfun(@double,x); end
        if iscategorical(x), x = double(x); end
        x = double(x(:));
        return
    end
end
end

function f = newFig()
f = figure('Visible','off','Color','w','Position',[80 80 1100 650]);
end

function finishFig(f,path,ttl,xlab,ylab)
try
    title(ttl,'Interpreter','none');
    xlabel(xlab); ylabel(ylab);
    grid on; box on; legend('Location','best');
    exportgraphics(f,path,'Resolution',180);
catch
    saveas(f,path);
end
close(f);
end

function C = loadCleanTable(runDir)
files = dir(fullfile(runDir,'EV_DAQ_Clean*.mat'));
if isempty(files)
    error('EV_BBPlots:NoCleanMAT','No EV_DAQ_Clean*.mat file found in %s.',runDir);
end
[~,ix] = max([files.datenum]);
S = load(fullfile(files(ix).folder,files(ix).name));
fn = fieldnames(S); C = [];
for k = 1:numel(fn)
    if istable(S.(fn{k})) || istimetable(S.(fn{k}))
        C = S.(fn{k}); return
    end
end
error('EV_BBPlots:NoTable','No table/timetable found in %s.',files(ix).name);
end

function runDir = findLatestRun(root)
d = dir(fullfile(root,'Simulation Logs','EV_RUN_*'));
d = d([d.isdir]);
if isempty(d), d = dir(fullfile(root,'EV_RUN_*')); d = d([d.isdir]); end
if isempty(d), error('EV_BBPlots:NoRun','Could not find an EV_RUN_* folder. Pass runDir explicitly.'); end
[~,ix] = max([d.datenum]);
runDir = fullfile(d(ix).folder,d(ix).name);
end
