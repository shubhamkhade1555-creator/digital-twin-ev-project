function EV_MakeComparisonGraphs(data, batteryModel, opts)
% EV_MakeComparisonGraphs
% Create one non-duplicated comparison figure per available signal.
%
% MATLAB R2024b. Example:
%   EV_MakeComparisonGraphs(EV_DAQ_Clean, sysModel)
%   EV_MakeComparisonGraphs(EV_DAQ_Clean, [])
%
% data must be a table/timetable containing a time column/row time and logged
% Simulink signals. batteryModel is an optional identified idss model with
% inputs [RPM, MotorCurrent] and outputs [BatteryVoltage, BatteryCurrent].
%
% Important: this project identifies a BATTERY black-box model, not a motor
% black-box model. Therefore motor plots compare Simulink actual signals to
% reference/setpoint signals when present. They do not falsely label plant
% data as black-box motor predictions.

if nargin < 1 || isempty(data)
    if evalin('base',"exist('EV_DAQ_Clean','var')") == 1
        data = evalin('base','EV_DAQ_Clean');
    else
        error('Pass the clean DAQ table/timetable or create EV_DAQ_Clean first.');
    end
end
if nargin < 2, batteryModel = []; end
if nargin < 3 || isempty(opts), opts = struct(); end
if ~isfield(opts,'OutputDir'), opts.OutputDir = fullfile(pwd,'EV_COMPARISON_GRAPHS'); end
if ~isfield(opts,'ShowFigures'), opts.ShowFigures = true; end
if ~isfield(opts,'TimeRange'), opts.TimeRange = []; end
if ~exist(opts.OutputDir,'dir'), mkdir(opts.OutputDir); end

% Convert timetable to table while retaining row times as Time.
if istimetable(data)
    rt = data.Properties.RowTimes;
    data = timetable2table(data,'ConvertRowTimes',true);
    data.Properties.VariableNames{1} = 'Time';
    if isdatetime(rt) || isduration(rt)
        error('Time must be numeric seconds, not datetime/duration.');
    end
end
if ~istable(data), error('data must be a table or timetable.'); end
names = data.Properties.VariableNames;
time = getSignal(data, {'Time','time','tout','SimulationTime','t'});
if isempty(time)
    error('No time signal found. Provide a numeric Time column in seconds.');
end
time = double(time(:));
if numel(time) ~= height(data), error('Time length does not match data rows.'); end
valid = isfinite(time);
if ~isempty(opts.TimeRange)
    valid = valid & time >= opts.TimeRange(1) & time <= opts.TimeRange(2);
end
data = data(valid,:);
time = time(valid);
if numel(time) < 3, error('Fewer than 3 samples remain after time filtering.'); end

% Canonical signal groups: each group produces at most one plot.
specs = {
 'BatteryVoltage', {'BatteryVoltage','Vbatt_V','V_batt','PackVoltage','Battery_Voltage'}, ...
    {'BatteryVoltageMeasured','BatteryVoltagePredicted','Vbatt_1step','Vbatt_FreeRun'}, ...
    'Battery terminal voltage','V','battery_voltage';
 'BatteryCurrent', {'BatteryCurrent','Ibatt_A','I_batt','PackCurrent','Battery_Discharge_Current'}, ...
    {'BatteryCurrentMeasured','BatteryCurrentPredicted','Ibatt_1step','Ibatt_FreeRun'}, ...
    'Battery discharge current','A','battery_current';
 'SOC', {'SOC','BatterySOC','SOC_Source','SOC_pu'}, ...
    {'SOCMeasured','SOCPredicted','SOC_1step','SOC_FreeRun'}, ...
    'Battery state of charge','SOC','battery_soc';
 'BatteryTemperature', {'BatteryTemperature','BatteryTemp','T_batt','Battery_Temperature'}, ...
    {'BatteryTempMeasured','BatteryTempPredicted','BatteryTemp_1step','BatteryTemp_FreeRun'}, ...
    'Battery temperature','deg C','battery_temperature';
 'MotorRPM', {'MotorRPM','RPM','MotorSpeed','ActualRPM','SpeedRPM'}, ...
    {'RPMReference','SpeedReference','MotorRPMReference','RPM_Ref','CommandedRPM'}, ...
    'Motor speed tracking','rpm','motor_rpm';
 'MotorCurrent', {'MotorCurrent','MotorCurrent_A','Ia_RMS','MotorCurrentRMS','PhaseCurrentRMS'}, ...
    {'MotorCurrentReference','MotorCurrentLimit','Icont','MotorCurrentRef'}, ...
    'Motor current / current-limit comparison','A','motor_current';
 'MotorVoltage', {'MotorVoltage','MotorTerminalVoltage','Vmotor','MotorVoltage_V','LineVoltageAB'}, ...
    {'MotorVoltageReference','MotorVoltageCommand','VmotorRef'}, ...
    'Motor terminal / line voltage','V','motor_voltage';
 'MotorTorque', {'MotorTorque','Torque','ElectromagneticTorque','Te','TorqueNm'}, ...
    {'MotorLoadTorque','LoadTorque','TorqueReference','TorqueRef'}, ...
    'Motor torque and load torque','N m','motor_torque';
 'MotorLoad', {'MotorLoad','LoadTorque','MotorLoadTorque','RoadLoadTorque','Load_Nm'}, ...
    {'MotorLoadReference','LoadTorqueReference','LoadCommand'}, ...
    'Motor load','N m','motor_load';
 'DCLinkVoltage', {'DCLinkVoltage','Vdc','DCBusVoltage','DC_Link_Voltage'}, ...
    {'DCLinkVoltageReference','VdcRef','DCBusVoltageRef'}, ...
    'DC-link voltage tracking','V','dc_link_voltage'
};

% Draw signal-vs-reference comparisons only when both signals exist.
made = strings(0,1);
for k = 1:size(specs,1)
    key = specs{k,1}; aliases = specs{k,2}; refAliases = specs{k,3};
    % Battery validation is handled once in the dedicated three-curve plots below.
    % Do not also create actual-only or partial battery figures here.
    if any(strcmp(key, {'BatteryVoltage','BatteryCurrent','SOC','BatteryTemperature'})), continue; end
    y = getSignal(data, aliases);
    if isempty(y), continue; end
    ref = getSignal(data, refAliases);
    % If this is a battery channel, prefer measured vs black-box prediction.
    if startsWith(key,'Battery') || strcmp(key,'SOC')
        if isempty(ref)
            if strcmp(key,'BatteryVoltage'), ref = getSignal(data, {'Vbatt_1step','BatteryVoltage_1step','VoltageOneStep'});
            elseif strcmp(key,'BatteryCurrent'), ref = getSignal(data, {'Ibatt_1step','BatteryCurrent_1step','CurrentOneStep'});
            end
        end
    end
    if isempty(ref) && strcmp(key,'MotorRPM')
        % Reference is mandatory for a true tracking comparison; actual-only
        % plot is explicitly named if the reference is absent.
        plotPair(time,y,[],[],specs{k,4},specs{k,5},opts, key);
    elseif isempty(ref)
        % Do not create an uninformative duplicate actual-only figure for a
        % signal already represented by a reference/validation figure.
        continue;
    else
        plotPair(time,y,ref,[],specs{k,4},specs{k,5},opts,key);
    end
    made(end+1,1) = string(key); %#ok<AGROW>
end

% Battery black-box validation: compare plant measurement, one-step prediction,
% and free-run prediction using iddata + compare/predict. Model is used only
% for its two documented battery outputs.
if ~isempty(batteryModel)
    rpm = getSignal(data, {'RPM','MotorRPM','RPMReference','MotorRPMReference'});
    mi  = getSignal(data, {'MotorCurrent','MotorCurrent_A','MotorCurrentRMS'});
    bv  = getSignal(data, {'BatteryVoltage','Vbatt_V','PackVoltage'});
    bi  = getSignal(data, {'BatteryCurrent','Ibatt_A','PackCurrent'});
    if ~isempty(rpm) && ~isempty(mi) && ~isempty(bv) && ~isempty(bi)
        Ts = median(diff(time));
        if isfinite(Ts) && Ts > 0
            U = [rpm(:),mi(:)]; Y = [bv(:),bi(:)];
            good = all(isfinite([U Y]),2);
            if nnz(good) >= 20
                % Use data as a single validation segment; keep model input/output
                % channel order consistent with EV_SysID_Auto.m.
                z = iddata(Y(good,:),U(good,:),Ts, ...
                    'InputName',{'RPM','MotorCurrent'}, ...
                    'OutputName',{'BatteryVoltage','BatteryCurrent'});
                try
                    y1 = predict(batteryModel,z,1);
                    yfree = sim(batteryModel,z);
                    yp1 = y1.OutputData; ypf = yfree.OutputData;
                    plotTriple(time(good),Y(good,1),yp1(:,1),ypf(:,1), ...
                        'Battery voltage validation','V',opts,'battery_voltage_validation');
                    plotTriple(time(good),Y(good,2),yp1(:,2),ypf(:,2), ...
                        'Battery current validation','A',opts,'battery_current_validation');
                    made(end+1,1) = "battery_voltage_validation"; %#ok<AGROW>
                    made(end+1,1) = "battery_current_validation"; %#ok<AGROW>
                catch ME
                    warning('Battery model comparison skipped: %s',ME.message);
                end
            end
        end
    end
end

% Residuals are one unique plot per battery output, only when prediction data
% is explicitly present in the table. Avoid generating the same residual twice.
resSpecs = {
 'BatteryVoltage', {'BatteryVoltage','Vbatt_V'}, {'BatteryVoltage_1step','Vbatt_1step','VoltageOneStep'}, 'Battery voltage residual','V','residual_voltage';
 'BatteryCurrent', {'BatteryCurrent','Ibatt_A'}, {'BatteryCurrent_1step','Ibatt_1step','CurrentOneStep'}, 'Battery current residual','A','residual_current'};
for k=1:size(resSpecs,1)
    meas = getSignal(data,resSpecs{k,2}); pred = getSignal(data,resSpecs{k,3});
    if ~isempty(meas) && ~isempty(pred)
        f = newFig(opts,resSpecs{k,6});
        plot(time,meas(:)-pred(:),'LineWidth',1.1); hold on; yline(0,':k','Zero error');
        grid on; xlabel('Time (s)'); ylabel(['Measured - predicted (' resSpecs{k,5} ')']);
        title(resSpecs{k,4},'Interpreter','none');
        saveFig(f,opts,resSpecs{k,6}); made(end+1,1)=string(resSpecs{k,6}); %#ok<AGROW>
    end
end

fprintf('\nEV comparison graph generation complete.\n');
fprintf('Output folder: %s\n',opts.OutputDir);
fprintf('Unique graph files generated this run: %d\n',numel(made));
disp(made);

end

function y = getSignal(T, aliases)
% Case-insensitive exact alias match; never silently use a different channel.
y = [];
vars = T.Properties.VariableNames;
for a=1:numel(aliases)
    idx=find(strcmpi(vars,aliases{a}),1);
    if ~isempty(idx)
        v=T.(vars{idx});
        if isnumeric(v) && isvector(v) && numel(v)==height(T)
            y=double(v(:)); return;
        end
    end
end
end

function f = newFig(opts,stem)
if opts.ShowFigures, f=figure('Name',stem,'Color','w'); else, f=figure('Visible','off','Name',stem,'Color','w'); end
end

function plotPair(t,y,ref,~,ttl,unit,opts,key)
f=newFig(opts,key); plot(t,y(:),'k','LineWidth',1.35); hold on;
if ~isempty(ref)
    plot(t,ref(:),'--','LineWidth',1.2);
    legend('Measured / Simulink actual','Reference / setpoint','Location','best');
else
    legend('Simulink actual','Location','best');
end
grid on; xlabel('Time (s)'); ylabel(unit); title(ttl,'Interpreter','none');
saveFig(f,opts,key);
end

function plotTriple(t,meas,one,free,ttl,unit,opts,key)
f=newFig(opts,key);
plot(t,meas(:),'k','LineWidth',1.3); hold on;
plot(t,one(:),'--','LineWidth',1.1);
plot(t,free(:),'-.','LineWidth',1.1);
grid on; xlabel('Time (s)'); ylabel(unit); title(ttl,'Interpreter','none');
legend('Measured / Simulink validation','Black-box one-step prediction', ...
       'Black-box free-run simulation','Location','best');
saveFig(f,opts,key);
end

function saveFig(f,opts,stem)
safe=regexprep(char(stem),'[^a-zA-Z0-9_-]','_');
exportgraphics(f,fullfile(opts.OutputDir,[safe '.png']),'Resolution',180);
savefig(f,fullfile(opts.OutputDir,[safe '.fig']));
end
