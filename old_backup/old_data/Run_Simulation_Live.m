function app = Run_Simulation_Live(varargin)
%RUN_SIMULATION_LIVE  Simulation + live desktop app + MQTT + CSV saving, all at once.
%
%   Run_Simulation_Live                              MQTT off, Profile 'fast'
%   Run_Simulation_Live('MQTT',true,'Broker','192.168.1.10','Port',1883, ...
%                       'User','me','Pass','secret','Topic','ev/digitaltwin/telemetry')
%   Run_Simulation_Live('Profile','turbo')           larger solver step (check results!)
%
%   What runs (one path each):
%     FINAL model (Normal mode - the live read-out needs it)
%       -> EV_BlackBox_App   (starts the run itself, updates every 100 ms)
%            -> MQTT   (EV_Telemetry as JSON, if 'MQTT',true)
%            -> BlackBox_Live.csv   (the app's EV_Telemetry buffer)
%       -> when the run ends: Run_Simulation_Log('FromBase',true) writes the
%          engineering logs (same folder) - the SAME logger as Run_Simulation_Log.
%
%   Speed: live read-out cannot use Accelerator mode, so this run gets the model's
%   saved fast set-up (no scope windows, no Simscape logging) and, with
%   'Profile','turbo', the larger step Ts = 2e-5. For the biggest speed-up use
%   Run_Simulation_Log (Accelerator).

p = inputParser;
addParameter(p, 'MQTT',    false);
addParameter(p, 'Broker',  'localhost');
addParameter(p, 'Port',    1883);
addParameter(p, 'User',    '');
addParameter(p, 'Pass',    '');
addParameter(p, 'Topic',   'ev/digitaltwin/telemetry');
addParameter(p, 'Profile', 'fast');
parse(p, varargin{:});
r = p.Results;

root = fileparts(mfilename('fullpath'));
cd(root);  addpath(root);
mdl = 'BLDCSpeedControl_EV_Layout_FINAL';
if ~isfile(fullfile(root, [mdl '.slx'])), error('Run Create_Simulation first (FINAL model not found).'); end
bdclose all;
load_system(mdl);
set_param(mdl, 'SimulationMode', 'normal');

runDir = fullfile(root, 'Simulation_Logs', ['Live_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
mkdir(runDir);

ov = struct();
if strcmpi(r.Profile, 'turbo'), ov.Ts = 2e-5; end

mq = struct('Enable', logical(r.MQTT), 'Broker', r.Broker, 'Port', r.Port, ...
            'User', r.User, 'Pass', r.Pass, 'Topic', r.Topic);

app = EV_BlackBox_App('AutoStart', true, ...
    'MQTT',       mq, ...
    'Overrides',  ov, ...
    'CSVFile',    fullfile(runDir, 'BlackBox_Live.csv'), ...
    'OnComplete', @() Run_Simulation_Log('FromBase', true, 'RunDir', runDir));
fprintf('[LIVE] App started. Logs will be in:\n       %s\n', runDir);
end
