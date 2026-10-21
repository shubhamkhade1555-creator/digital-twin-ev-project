classdef EV_BlackBox_App < matlab.apps.AppBase
%EV_BLACKBOX_APP  Live EV digital-twin black-box monitor.
%
%   Run:   EV_BlackBox_App            (project folder must be on the path)
%cdcdcdcccd
%   DATA FLOW
%     BLDCSpeedControl_EV_Layout_FINAL.slx
%       -> DATA ACQUISITION (the model's existing To Workspace blocks)
%       -> EV_Telemetry   (built here, every 100 ms, from those blocks' live inputs)
%       -> graphs / panels / V&V / Save / MQTT   (all fed from the same row)
%
%   The app does not add blocks to the model and does not log anything a
%   second time: it reads the inputs of the existing To Workspace blocks via
%   get_param(block,'RuntimeObject') while the simulation is running.
%   Signals the model does not supply are shown as n/a and stored as NaN.
%
%   Requires: Simulink (+ Simscape for the model), MATLAB R2022a+ for mqttclient
%   (Industrial Communication Toolbox / MATLAB MQTT support).

    %% ------------------------------------------------------------------ UI
    properties (Access = public)
        UIFigure      matlab.ui.Figure
        StartButton   matlab.ui.control.Button
        PauseButton   matlab.ui.control.Button
        ResumeButton  matlab.ui.control.Button
        StopButton    matlab.ui.control.Button
        SaveButton    matlab.ui.control.Button
        StatusLabel   matlab.ui.control.Label
        MqttCheck     matlab.ui.control.CheckBox
        BrokerField   matlab.ui.control.EditField
        PortField     matlab.ui.control.NumericEditField
        UserField     matlab.ui.control.EditField
        PassField     matlab.ui.control.EditField
        TopicField    matlab.ui.control.EditField
        MqttStatus    matlab.ui.control.Label
        AxRPM         matlab.ui.control.UIAxes
        AxBatt        matlab.ui.control.UIAxes
        AxMotor       matlab.ui.control.UIAxes
        AxSOC         matlab.ui.control.UIAxes
        BBTable       matlab.ui.control.Table
        FootLabel     matlab.ui.control.Label
    end

    %% ----------------------------------------------------------- internals
    properties (Constant, Access = private)
        % EV_Telemetry columns (names/order from the model specification, section I)
        TelNames = {'Time','BatteryVoltage','BatteryCurrent','BatteryTemperature', ...
            'SOC','BatteryPower','DCLinkVoltage','DCLinkCurrent','RPMReference','RPM', ...
            'MotorCurrent','Torque','WheelSpeed','MechanicalPower','Efficiency','RPM_Error'};
        TelUnits = {'s','V','A','degC','-','W','V','A','rpm','rpm','A','Nm','rpm','W','%','rpm'};
        % signal key -> accepted To Workspace variable names (case-insensitive, same
        % names as EV_Run_Simulation.m / the model specification)
        SigKeys  = {'vbatt','ibatt','temp','soc','vdc','rpm_ref','rpm','imotor','torque','wheel'};
        SigVars  = {'log_vcell','log_icell','temperature','log_soc','log_vdc_m', ...
                    'log_rpm_ref','log_rpm','log_idc_f','log_tq_meas','log_omega_wheel'};
        PeriodS  = 0.1;                    % 100 ms
    end

    properties (Access = private)
        Model   = 'BLDCSpeedControl_EV_Layout_FINAL'
        Cfg     = []                       % cfg returned by EV_Final_Setup (if present)
        Tmr     = []
        Mqtt    = []
        MqttFails = 0
        PwdReal = ''
        RunID   = ''
        Blocks  = struct()                 % key -> To Workspace block path ('' = not in model)
        Rows    = zeros(0,16)              % EV_Telemetry buffer
        N       = 0
        nSer    = 13
        nPar    = 10
        Lim     = struct()
        State   = 'READY'
        SawRunning = false
        UserStop   = false
        Active     = false
        T0      = []
        Soc0    = NaN
        Worst   = 0
        Val     = struct()                 % value labels by field name
        VV      = struct()                 % V&V labels
        LnRef; LnRPM; LnV; LnI; LnTq; LnIm; LnSOC
        Opts = struct('AutoStart',false,'CSVFile','','OnComplete',[],'Overrides',struct())
    end

    %% =================================================================
    %%  SIMULATION CONTROL
    %% =================================================================
    methods (Access = private)

        function startupFcn(app, varargin)
            % optional name-value options (used by Run_Simulation_Live):
            %  'AutoStart',true  'CSVFile',path  'OnComplete',@fcn  'Overrides',struct('Ts',2e-5)
            %  'MQTT',struct('Enable',true,'Broker','localhost','Port',1883,'User','','Pass','','Topic','...')
            ip = inputParser;  ip.KeepUnmatched = true;
            addParameter(ip, 'AutoStart', false);   addParameter(ip, 'CSVFile', '');
            addParameter(ip, 'OnComplete', []);     addParameter(ip, 'Overrides', struct());
            addParameter(ip, 'MQTT', struct());
            parse(ip, varargin{:});
            app.Opts = struct('AutoStart', ip.Results.AutoStart, 'CSVFile', ip.Results.CSVFile, ...
                'OnComplete', ip.Results.OnComplete, 'Overrides', ip.Results.Overrides);
            m = ip.Results.MQTT;
            if isfield(m, 'Enable'), app.MqttCheck.Value = logical(m.Enable); end
            if isfield(m, 'Broker'), app.BrokerField.Value = m.Broker; end
            if isfield(m, 'Port'),   app.PortField.Value   = m.Port;   end
            if isfield(m, 'User'),   app.UserField.Value   = m.User;   end
            if isfield(m, 'Pass'),   app.PwdReal = m.Pass; app.PassField.Value = repmat('*', 1, numel(m.Pass)); end
            if isfield(m, 'Topic'),  app.TopicField.Value  = m.Topic;  end
            app.setState('READY', 'Press START');
            if app.Opts.AutoStart, app.onStart(); end
        end

        function onStart(app)
            try
                app.setState('READY', 'Preparing model ...');  drawnow;
                app.prepareModel();
                app.findSignals();
                app.resetBuffers();
                app.connectMqtt();
                set_param(app.Model, 'SimulationCommand', 'start');   % non-blocking
                app.T0 = tic;  app.Active = true;
                app.startTimer();
                app.setState('RUNNING', 'Simulation started');
            catch ME
                app.stopTimer();  app.closeMqtt();  app.Active = false;
                app.setState('ERROR', ME.message);
            end
        end

        function onPause(app)
            try
                set_param(app.Model, 'SimulationCommand', 'pause');
                app.setState('PAUSED', 'Simulation paused');
            catch ME
                app.setState('ERROR', ME.message);
            end
        end

        function onResume(app)
            try
                set_param(app.Model, 'SimulationCommand', 'continue');
                app.setState('RUNNING', 'Simulation resumed');
            catch ME
                app.setState('ERROR', ME.message);
            end
        end

        function onStop(app)
            app.UserStop = true;
            try, set_param(app.Model, 'SimulationCommand', 'stop'); catch, end
            app.finish();
        end

        function prepareModel(app)
            % Same configuration step the project already uses (no simulation inside).
            app.Cfg = [];
            if exist('EV_Final_Setup', 'file') == 2
                try
                    app.Cfg = EV_Final_Setup(app.Model);
                catch ME
                    app.FootLabel.Text = ['EV_Final_Setup failed, using defaults: ' app.short(ME.message)];
                    app.Cfg = [];
                end
            end
            if isempty(app.Cfg)                       % fallback: parameters only
                if exist('BLDCSpeedControlData', 'file') == 2, evalin('base', 'BLDCSpeedControlData'); end
                if isempty(which(app.Model)), error('Model %s not found on the MATLAB path.', app.Model); end
            end
            ov = app.Opts.Overrides;                     % e.g. Ts for the turbo profile
            for fn = fieldnames(ov).', assignin('base', fn{1}, ov.(fn{1})); end
            if ~bdIsLoaded(app.Model), load_system(app.Model); end
            if ~strcmpi(get_param(app.Model, 'SimulationStatus'), 'stopped')
                error('Model is already running or paused. Stop it first.');
            end
            % SimulationInput: apply the run configuration to the model
            in = Simulink.SimulationInput(app.Model);
            if ~isempty(app.Cfg) && isstruct(app.Cfg) && isfield(app.Cfg, 'tStop') && isnumeric(app.Cfg.tStop)
                in = in.setModelParameter('StopTime', num2str(app.Cfg.tStop, 12));
            end
            in.applyToModel;
            if ~strcmpi(get_param(app.Model, 'SimulationMode'), 'normal')
                error('Live readout needs SimulationMode = normal (now: %s).', get_param(app.Model, 'SimulationMode'));
            end
            % pack scaling + limits that the project already defines
            app.nSer = app.baseVar('cells_series', 13);
            app.nPar = app.baseVar('cells_parallel', 10);
            cellVmax = 4.19;                 % BLDCSpeedControlData.m: 13*4.19 V = full-charge pack
            startup  = 2e-3;                 % EV_Run_Simulation.m: post-start-up window
            if isstruct(app.Cfg) && isfield(app.Cfg, 'logCfg')
                if isfield(app.Cfg.logCfg, 'cellVmax'),   cellVmax = app.Cfg.logCfg.cellVmax;   end
                if isfield(app.Cfg.logCfg, 'startupWin'), startup  = app.Cfg.logCfg.startupWin; end
            end
            app.Lim = struct('rpmLo', 2900, 'rpmHi', 3000, ...      % speed window (project target)
                'Icont', app.baseVar('I_cont', 30), 'Ipeak', app.baseVar('I_peak', 40), ...
                'Vmax', app.nSer*cellVmax + 0.1, 'startup', startup);
        end

        function findSignals(app)
            tw = find_system(app.Model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'BlockType', 'ToWorkspace');
            names = lower(strtrim(cellfun(@(b) get_param(b, 'VariableName'), tw, 'UniformOutput', false)));
            app.Blocks = struct();
            for k = 1:numel(app.SigKeys)
                i = find(strcmp(names, app.SigVars{k}), 1);
                if isempty(i), app.Blocks.(app.SigKeys{k}) = '';
                else,          app.Blocks.(app.SigKeys{k}) = tw{i};
                end
            end
            if isempty(app.Blocks.rpm), error('Model has no To Workspace block "log_rpm" - nothing to monitor.'); end
            miss = app.SigKeys(cellfun(@(k) isempty(app.Blocks.(k)), app.SigKeys));
            if ~isempty(miss)
                app.FootLabel.Text = ['Not supplied by the model (shown n/a): ' strjoin(app.SigVars(ismember(app.SigKeys, miss)), ', ')];
            else
                app.FootLabel.Text = 'All telemetry signals found.';
            end
        end

        function resetBuffers(app)
            app.Rows = nan(2000, 16);  app.N = 0;
            app.RunID = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
            app.SawRunning = false;  app.UserStop = false;
            app.Soc0 = NaN;  app.Worst = 0;  app.MqttFails = 0;
            app.updatePlots();
        end
    end

    %% =================================================================
    %%  100 ms TIMER : sample -> EV_Telemetry row -> UI + MQTT
    %% =================================================================
    methods (Access = private)

        function startTimer(app)
            app.stopTimer();
            app.Tmr = timer('ExecutionMode', 'fixedSpacing', 'Period', app.PeriodS, ...
                'BusyMode', 'drop', 'TimerFcn', @(~,~) app.onTick());
            start(app.Tmr);
        end

        function stopTimer(app)
            if ~isempty(app.Tmr) && isvalid(app.Tmr)
                try, stop(app.Tmr); catch, end
                delete(app.Tmr);
            end
            app.Tmr = [];
        end

        function onTick(app)
            if ~app.Active || ~isvalid(app) || ~isvalid(app.UIFigure), return, end
            try
                st = get_param(app.Model, 'SimulationStatus');
            catch
                st = 'stopped';
            end
            switch st
                case 'running'
                    app.SawRunning = true;
                    if strcmp(app.State, 'PAUSED'), app.setState('RUNNING', ''); end
                    app.sample();
                case 'paused'
                    if strcmp(app.State, 'RUNNING'), app.setState('PAUSED', 'Simulation paused'); end
                    app.sample();
                case 'stopped'
                    if app.SawRunning || app.N > 0 || toc(app.T0) > 5
                        app.finish();
                    end
            end
        end

        function sample(app)
            try
                ts = get_param(app.Model, 'SimulationTime');
            catch
                return
            end
            if app.N > 0 && ts <= app.Rows(app.N, 1), return, end    % no new sim time
            vb = app.readSig('vbatt');   ib  = app.readSig('ibatt');
            tp = app.readSig('temp');    soc = app.readSig('soc');
            vd = app.readSig('vdc');     ref = app.readSig('rpm_ref');
            rp = app.readSig('rpm');     im  = app.readSig('imotor');
            tq = app.readSig('torque');  wh  = app.readSig('wheel');
            dci = NaN;                                  % DC-link current: no logged source in the model
            pb  = abs(vb*ib);                           % same derivations as EV_Run_Simulation.m
            pm  = abs(tq) * rp * 2*pi/60;
            if pb > 1, eff = 100*pm/pb; else, eff = NaN; end
            row = [ts vb ib tp soc pb vd dci ref rp im tq wh pm eff ref-rp];
            if app.N >= size(app.Rows, 1), app.Rows(end+2000, :) = NaN; end
            app.N = app.N + 1;  app.Rows(app.N, :) = row;
            if isnan(app.Soc0) && isfinite(soc), app.Soc0 = soc; end
            app.refresh(row, false);
            app.publish(row);
        end

        function v = readSig(app, key)
            v = NaN;
            blk = app.Blocks.(key);
            if isempty(blk), return, end
            try
                rto = get_param(blk, 'RuntimeObject');
                x   = double(rto.InputPort(1).Data);
                x   = x(:);
                if isempty(x), return, end
                switch key
                    case 'vbatt'
                        if numel(x) > 1, v = sum(x); else, v = x*app.nSer; end
                    case 'ibatt'
                        v = mean(x) * app.nPar;
                    case {'soc', 'temp'}
                        v = mean(x);
                    otherwise
                        v = x(1);
                end
            catch
                v = NaN;
            end
        end

        function finish(app)
            if ~app.Active, return, end
            app.Active = false;
            app.stopTimer();
            app.closeMqtt();
            if app.N > 0
                app.refresh(app.Rows(app.N, :), true);
                assignin('base', 'EV_Telemetry', app.telemetryStruct());
            end
            if app.N > 0 && ~isempty(app.Opts.CSVFile)
                try
                    writetable(array2table(app.Rows(1:app.N, :), 'VariableNames', app.TelNames), app.Opts.CSVFile);
                catch ME
                    app.FootLabel.Text = ['CSV save failed: ' app.short(ME.message)];
                end
            end
            if app.UserStop
                app.setState('READY', 'Stopped by user');
            elseif app.N == 0
                app.setState('ERROR', 'Simulation ended without any telemetry (check the Simulink Diagnostic Viewer).');
            else
                tEnd = NaN;
                try, tEnd = evalin('base', get_param(app.Model, 'StopTime')); catch, end
                app.setState('COMPLETED', sprintf('%d samples, last t = %.3f s of %.3f s; EV_Telemetry -> base workspace', ...
                    app.N, app.Rows(app.N, 1), tEnd));
                if ~isempty(app.Opts.OnComplete)
                    try, app.Opts.OnComplete(); catch ME, app.FootLabel.Text = ['Logger: ' app.short(ME.message)]; end
                end
            end
        end
    end

    %% =================================================================
    %%  DISPLAY / V&V
    %% =================================================================
    methods (Access = private)

        function refresh(app, row, isFinal)
            fmt = {'BatteryVoltage','%.2f'; 'BatteryCurrent','%.2f'; 'BatteryTemperature','%.1f'; ...
                   'SOC','%.4f'; 'BatteryPower','%.0f'; 'RPMReference','%.0f'; 'RPM','%.1f'; ...
                   'MotorCurrent','%.2f'; 'Torque','%.3f'; 'MechanicalPower','%.0f'; 'WheelSpeed','%.1f'};
            for k = 1:size(fmt, 1)
                i = find(strcmp(app.TelNames, fmt{k,1}), 1);
                app.Val.(fmt{k,1}).Text = app.num(row(i), fmt{k,2});
            end
            app.updateVV(row, isFinal);
            app.updatePlots();
            app.updateTable();
            drawnow limitrate;
        end

        function updateVV(app, row, isFinal)
            ix  = @(n) row(find(strcmp(app.TelNames, n), 1));
            L   = app.Lim;
            t = row(1);  rpm = ix('RPM');  err = ix('RPM_Error');
            vb = ix('BatteryVoltage');  im = ix('MotorCurrent');  soc = ix('SOC');

            % RPM: <= 3000 rpm always; final-speed window 2900..3000 after the run (project checks)
            if isnan(rpm), sR = 'n/a';
            elseif rpm > L.rpmHi, sR = 'FAIL';
            else, sR = 'PASS'; end
            if isFinal && app.N > 1
                m  = app.Rows(1:app.N, 1) >= 0.9*t;
                fr = mean(app.Rows(m, strcmp(app.TelNames, 'RPM')), 'omitnan');
                if fr >= L.rpmLo && fr <= L.rpmHi, sR = 'PASS'; else, sR = 'FAIL'; end
            end
            app.setVV('RPM_Error', sR, [app.num(err, '%+.1f') ' rpm']);

            % Voltage: pack <= nSer*cellVmax (post start-up)
            if isnan(vb) || t < L.startup, sV = 'n/a';
            elseif vb <= L.Vmax, sV = 'PASS'; else, sV = 'FAIL'; end
            app.setVV('Voltage', sV, [app.num(vb, '%.2f') ' V (max ' num2str(L.Vmax, '%.1f') ')']);

            % Current: <= I_peak hard limit, <= I_cont continuous
            if isnan(im), sI = 'n/a';
            elseif abs(im) > L.Ipeak, sI = 'FAIL';
            elseif abs(im) > L.Icont, sI = 'WARN';
            else, sI = 'PASS'; end
            app.setVV('Current', sI, [app.num(im, '%.1f') ' A (cont ' num2str(L.Icont) ' / peak ' num2str(L.Ipeak) ')']);

            % SOC: within 0..1 and not increasing
            if isnan(soc), sS = 'n/a';
            elseif soc < 0 || soc > 1 || soc > app.Soc0 + 1e-9, sS = 'FAIL';
            else, sS = 'PASS'; end
            app.setVV('SOC', sS, app.num(soc, '%.4f'));

            rank = @(s) find(strcmp(s, {'n/a','PASS','WARN','FAIL'})) - 1;
            app.Worst = max([app.Worst, rank(sR), rank(sV), rank(sI), rank(sS)]);
            names = {'n/a','PASS','WARN','FAIL'};
            app.setVV('Overall', names{app.Worst+1}, 'worst status during run');
        end

        function setVV(app, key, status, txt)
            lbl = app.VV.(key);
            lbl.Text = [txt '   ' status];
            switch status
                case 'PASS', lbl.BackgroundColor = [0.70 0.90 0.70];
                case 'WARN', lbl.BackgroundColor = [1.00 0.88 0.55];
                case 'FAIL', lbl.BackgroundColor = [0.95 0.60 0.60];
                otherwise,   lbl.BackgroundColor = [0.88 0.88 0.88];
            end
        end

        function updatePlots(app)
            n = app.N;
            if n == 0
                t = NaN;  R = nan(1, 16);
            else
                i0 = max(1, n-3000+1);  R = app.Rows(i0:n, :);  t = R(:, 1);
            end
            c = @(name) R(:, strcmp(app.TelNames, name));
            set(app.LnRef, 'XData', t, 'YData', c('RPMReference'));
            set(app.LnRPM, 'XData', t, 'YData', c('RPM'));
            set(app.LnV,   'XData', t, 'YData', c('BatteryVoltage'));
            set(app.LnI,   'XData', t, 'YData', c('BatteryCurrent'));
            set(app.LnTq,  'XData', t, 'YData', c('Torque'));
            set(app.LnIm,  'XData', t, 'YData', c('MotorCurrent'));
            set(app.LnSOC, 'XData', t, 'YData', c('SOC'));
        end

        function updateTable(app)
            n = app.N;
            if n == 0, app.BBTable.Data = []; return, end
            app.BBTable.Data = flipud(app.Rows(max(1, n-7):n, :));    % newest first
        end

        function s = num(~, x, f)
            if isempty(x) || ~isfinite(x), s = 'n/a'; else, s = sprintf(f, x); end
        end

        function v = baseVar(~, name, default)
            try
                v = evalin('base', name);
                if ~isnumeric(v) || ~isscalar(v), v = default; end
            catch
                v = default;
            end
        end

        function setState(app, state, msg)
            app.State = state;
            col = struct('READY', [0.80 0.80 0.80], 'RUNNING', [0.60 0.88 0.60], 'PAUSED', [1.00 0.88 0.55], ...
                         'COMPLETED', [0.65 0.80 0.95], 'ERROR', [0.95 0.55 0.55]);
            app.StatusLabel.Text = state;
            app.StatusLabel.BackgroundColor = col.(state);
            if nargin > 2 && ~isempty(msg), app.FootLabel.Text = msg; end
            on = @(b) set(b, 'Enable', 'on');  off = @(b) set(b, 'Enable', 'off');
            btns = {app.StartButton, app.PauseButton, app.ResumeButton, app.StopButton};
            for k = 1:numel(btns), off(btns{k}); end
            switch state
                case 'RUNNING', on(app.PauseButton);  on(app.StopButton);
                case 'PAUSED',  on(app.ResumeButton); on(app.StopButton);
                otherwise,      on(app.StartButton);
            end
            app.SaveButton.Enable = matlab.lang.OnOffSwitchState(app.N > 0 && ~strcmp(state, 'RUNNING'));
        end
    end

    %% =================================================================
    %%  MQTT  (never allowed to crash the app)
    %% =================================================================
    methods (Access = private)

        function connectMqtt(app)
            app.closeMqtt();
            if ~app.MqttCheck.Value
                app.MqttStatus.Text = 'MQTT: off';  return
            end
            try
                host = strtrim(app.BrokerField.Value);
                if isempty(host), error('Broker is empty.'); end
                if ~contains(host, '://')
                    if app.PortField.Value == 8883, host = ['ssl://' host]; else, host = ['tcp://' host]; end
                end
                args = {'Port', app.PortField.Value, 'ClientID', ['EV_BlackBox_' app.RunID(end-5:end)]};
                if ~isempty(strtrim(app.UserField.Value))
                    args = [args, {'Username', strtrim(app.UserField.Value), 'Password', app.PwdReal}];
                end
                app.Mqtt = mqttclient(host, args{:});
                app.MqttStatus.Text = 'MQTT: connected';
            catch ME
                app.Mqtt = [];
                app.MqttStatus.Text = ['MQTT: ' app.short(ME.message)];
            end
        end

        function publish(app, row)
            if isempty(app.Mqtt), return, end
            try
                s = cell2struct(num2cell(row(:)), app.TelNames(:), 1);   % EV_Telemetry row
                s.RunID = app.RunID;
                write(app.Mqtt, strtrim(app.TopicField.Value), jsonencode(s), 'QualityOfService', 0);
                app.MqttFails = 0;
                app.MqttStatus.Text = sprintf('MQTT: publishing (%d)', app.N);
            catch ME
                app.MqttFails = app.MqttFails + 1;
                app.MqttStatus.Text = ['MQTT: ' app.short(ME.message)];
                if app.MqttFails >= 5
                    app.closeMqtt();
                    app.MqttStatus.Text = 'MQTT: disabled after 5 errors';
                end
            end
        end

        function closeMqtt(app)
            try, app.Mqtt = []; catch, end        % releasing the object disconnects it
        end

        function s = short(~, msg)
            s = regexprep(msg, '\s+', ' ');
            if numel(s) > 60, s = [s(1:57) '...']; end
        end

        function onPassChanged(app)
            v = app.PassField.Value;
            if ~isempty(v) && ~all(v == '*')       % new text typed -> keep real value, mask the display
                app.PwdReal = v;
                app.PassField.Value = repmat('*', 1, numel(v));
            elseif isempty(v)
                app.PwdReal = '';
            end
        end
    end

    %% =================================================================
    %%  SAVE  (same EV_Telemetry source - no second logger)
    %% =================================================================
    methods (Access = private)

        function S = telemetryStruct(app)
            R = app.Rows(1:app.N, :);
            S = struct();
            for k = 1:numel(app.TelNames), S.(app.TelNames{k}) = R(:, k); end
            S.Units    = cell2struct(app.TelUnits(:), app.TelNames(:), 1);
            S.RunID    = app.RunID;
            S.SampleDt = app.PeriodS;
            S.Latest   = cell2struct(num2cell(R(end, :)).', app.TelNames(:), 1);
        end

        function onSave(app)
            if app.N == 0, uialert(app.UIFigure, 'No telemetry yet.', 'Save'); return, end
            [f, p] = uiputfile({'*.mat', 'MAT-file (EV_Telemetry struct)'; '*.csv', 'CSV'}, ...
                'Save live session', ['EV_Telemetry_' app.RunID '.mat']);
            figure(app.UIFigure);
            if isequal(f, 0), return, end
            full = fullfile(p, f);
            try
                [~, ~, ext] = fileparts(f);
                if strcmpi(ext, '.csv')
                    writetable(array2table(app.Rows(1:app.N, :), 'VariableNames', app.TelNames), full);
                else
                    EV_Telemetry = app.telemetryStruct();                        %#ok<NASGU>
                    meta = struct('Model', app.Model, 'RunID', app.RunID, 'Limits', app.Lim, ...
                        'Broker', app.BrokerField.Value, 'Topic', app.TopicField.Value);  %#ok<NASGU>
                    save(full, 'EV_Telemetry', 'meta', '-v7.3');                 % password is never saved
                end
                app.FootLabel.Text = ['Saved ' full];
            catch ME
                uialert(app.UIFigure, ME.message, 'Save failed');
            end
        end

        function closeApp(app)
            app.Active = false;
            app.stopTimer();  app.closeMqtt();
            try
                if bdIsLoaded(app.Model) && ~strcmpi(get_param(app.Model, 'SimulationStatus'), 'stopped')
                    set_param(app.Model, 'SimulationCommand', 'stop');
                end
            catch
            end
            delete(app);
        end
    end

    %% =================================================================
    %%  COMPONENT CREATION
    %% =================================================================
    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Visible', 'off', 'Position', [30 30 1520 880], ...
                'Name', 'EV Digital Twin - Black Box', 'CloseRequestFcn', @(~,~) app.closeApp());
            root = uigridlayout(app.UIFigure, [3 1], 'RowHeight', {84, '1x', 22}, 'Padding', [6 6 6 4], 'RowSpacing', 4);

            % ---- control bar -------------------------------------------------
            top = uipanel(root);
            tg  = uigridlayout(top, [2 1], 'RowHeight', {34, 28}, 'Padding', [6 4 6 4], 'RowSpacing', 4);
            g1  = uigridlayout(tg, [1 8], 'ColumnWidth', {90, 90, 90, 90, 120, 20, 160, '1x'}, 'Padding', 0);
            app.StartButton  = uibutton(g1, 'Text', 'START',  'ButtonPushedFcn', @(~,~) app.onStart());
            app.PauseButton  = uibutton(g1, 'Text', 'PAUSE',  'ButtonPushedFcn', @(~,~) app.onPause());
            app.ResumeButton = uibutton(g1, 'Text', 'RESUME', 'ButtonPushedFcn', @(~,~) app.onResume());
            app.StopButton   = uibutton(g1, 'Text', 'STOP',   'ButtonPushedFcn', @(~,~) app.onStop());
            app.SaveButton   = uibutton(g1, 'Text', 'Save session', 'ButtonPushedFcn', @(~,~) app.onSave());
            app.StatusLabel  = uilabel(g1, 'Text', 'READY', 'FontWeight', 'bold', 'FontSize', 16, ...
                'HorizontalAlignment', 'center', 'BackgroundColor', [0.8 0.8 0.8]);
            app.StatusLabel.Layout.Column = 7;

            g2 = uigridlayout(tg, [1 13], 'Padding', 0, 'ColumnSpacing', 4, ...
                'ColumnWidth', {100, 45, '1x', 32, 70, 36, '1x', 36, '1x', 40, '2x', '1.2x', 1});
            app.MqttCheck   = uicheckbox(g2, 'Text', 'Publish MQTT', 'Value', false);
            uilabel(g2, 'Text', 'Broker');
            app.BrokerField = uieditfield(g2, 'text', 'Value', 'localhost');
            uilabel(g2, 'Text', 'Port');
            app.PortField   = uieditfield(g2, 'numeric', 'Value', 1883, 'Limits', [1 65535], 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d');
            uilabel(g2, 'Text', 'User');
            app.UserField   = uieditfield(g2, 'text', 'Value', '');
            uilabel(g2, 'Text', 'Pass');
            app.PassField   = uieditfield(g2, 'text', 'Value', '', 'ValueChangedFcn', @(~,~) app.onPassChanged());
            uilabel(g2, 'Text', 'Topic');
            app.TopicField  = uieditfield(g2, 'text', 'Value', 'ev/digitaltwin/telemetry');
            app.MqttStatus  = uilabel(g2, 'Text', 'MQTT: off');

            % ---- body ---------------------------------------------------------
            body = uigridlayout(root, [1 2], 'ColumnWidth', {350, '1x'}, 'Padding', 0, 'ColumnSpacing', 6);
            left = uigridlayout(body, [4 1], 'RowHeight', {172, 172, 62, 192}, 'Padding', 0, 'RowSpacing', 6, 'Scrollable', 'on');
            app.metricPanel(left, 'Battery', {'BatteryVoltage','Voltage [V]'; 'BatteryCurrent','Current [A]'; ...
                'BatteryTemperature','Temperature [degC]'; 'SOC','SOC [0..1]'; 'BatteryPower','Power [W]'});
            app.metricPanel(left, 'Motor', {'RPMReference','RPM reference [rpm]'; 'RPM','Motor RPM [rpm]'; ...
                'MotorCurrent','Motor current [A]'; 'Torque','Torque [Nm]'; 'MechanicalPower','Mechanical power [W]'});
            app.metricPanel(left, 'Vehicle', {'WheelSpeed','Wheel speed [rpm]'});

            vv = uipanel(left, 'Title', 'V&V');
            vg = uigridlayout(vv, [5 2], 'ColumnWidth', {95, '1x'}, 'RowHeight', repmat({26}, 1, 5), 'Padding', [6 4 6 4], 'RowSpacing', 3);
            items = {'RPM_Error','RPM error'; 'Voltage','Voltage status'; 'Current','Current status'; 'SOC','SOC status'; 'Overall','Overall status'};
            for k = 1:5
                uilabel(vg, 'Text', items{k,2});
                app.VV.(items{k,1}) = uilabel(vg, 'Text', 'n/a', 'FontWeight', 'bold', 'BackgroundColor', [0.88 0.88 0.88], 'HorizontalAlignment', 'center');
            end

            right = uigridlayout(body, [2 1], 'RowHeight', {'1x', 200}, 'Padding', 0, 'RowSpacing', 6);
            pg = uigridlayout(right, [2 2], 'Padding', 0);

            app.AxRPM = uiaxes(pg);  title(app.AxRPM, 'RPM');  xlabel(app.AxRPM, 'Time [s]');  ylabel(app.AxRPM, 'rpm');  grid(app.AxRPM, 'on');  hold(app.AxRPM, 'on');
            app.LnRef = plot(app.AxRPM, NaN, NaN, '--', 'LineWidth', 1.3);
            app.LnRPM = plot(app.AxRPM, NaN, NaN, '-',  'LineWidth', 1.6);
            legend(app.AxRPM, [app.LnRef app.LnRPM], {'RPM reference', 'Motor RPM'}, 'Location', 'southeast');

            app.AxBatt = uiaxes(pg);  title(app.AxBatt, 'Battery');  xlabel(app.AxBatt, 'Time [s]');  grid(app.AxBatt, 'on');
            yyaxis(app.AxBatt, 'left');   app.LnV = plot(app.AxBatt, NaN, NaN, 'LineWidth', 1.5);  ylabel(app.AxBatt, 'Voltage [V]');
            yyaxis(app.AxBatt, 'right');  app.LnI = plot(app.AxBatt, NaN, NaN, 'LineWidth', 1.5);  ylabel(app.AxBatt, 'Current [A]');
            legend(app.AxBatt, [app.LnV app.LnI], {'Voltage', 'Current'}, 'Location', 'best');

            app.AxMotor = uiaxes(pg);  title(app.AxMotor, 'Motor');  xlabel(app.AxMotor, 'Time [s]');  grid(app.AxMotor, 'on');
            yyaxis(app.AxMotor, 'left');   app.LnTq = plot(app.AxMotor, NaN, NaN, 'LineWidth', 1.5);  ylabel(app.AxMotor, 'Torque [Nm]');
            yyaxis(app.AxMotor, 'right');  app.LnIm = plot(app.AxMotor, NaN, NaN, 'LineWidth', 1.5);  ylabel(app.AxMotor, 'Motor current [A]');
            legend(app.AxMotor, [app.LnTq app.LnIm], {'Torque', 'Motor current'}, 'Location', 'best');

            app.AxSOC = uiaxes(pg);  title(app.AxSOC, 'SOC');  xlabel(app.AxSOC, 'Time [s]');  ylabel(app.AxSOC, 'SOC [0..1]');  grid(app.AxSOC, 'on');
            app.LnSOC = plot(app.AxSOC, NaN, NaN, 'LineWidth', 1.6);

            app.BBTable = uitable(right, 'ColumnName', app.TelNames, 'RowName', {}, 'FontSize', 10, ...
                'ColumnWidth', repmat({'auto'}, 1, numel(app.TelNames)));
            app.FootLabel = uilabel(root, 'Text', '');

            app.UIFigure.Visible = 'on';
        end

        function metricPanel(app, parent, title, rows)
            p = uipanel(parent, 'Title', title);
            g = uigridlayout(p, [size(rows, 1) 2], 'ColumnWidth', {'1x', 95}, ...
                'RowHeight', repmat({22}, 1, size(rows, 1)), 'Padding', [6 4 6 4], 'RowSpacing', 2);
            for k = 1:size(rows, 1)
                uilabel(g, 'Text', rows{k, 2});
                app.Val.(rows{k, 1}) = uilabel(g, 'Text', 'n/a', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
            end
        end
    end

    %% ------------------------------------------------------- app lifecycle
    methods (Access = public)
        function app = EV_BlackBox_App(varargin)
            createComponents(app);
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @(a) startupFcn(a, varargin{:}));
            if nargout == 0, clear app, end
        end

        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
    end
end
