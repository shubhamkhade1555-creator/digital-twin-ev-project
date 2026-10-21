function Create_Simulation(varargin)
%CREATE_SIMULATION  Build BLDCSpeedControl_EV_Layout_FINAL.slx  (run once).
%
%   Create_Simulation                 build FINAL from v2 if missing, else update it
%   Create_Simulation('Rebuild',true) throw FINAL away and rebuild it from v2
%   Create_Simulation('Benchmark',false)  skip the speed benchmark
%
%   What it does
%     1. loads BLDCSpeedControlData.m (motor + battery + drivetrain parameters)
%     2. v2 -> FINAL  (copy)
%     3. battery: AHCell = 5, AHCell_unit = A*hr   (13S10P x 5 Ah = 50 Ah)
%     4. adds ONE BLACK_BOX_LIVE_TELEMETRY subsystem (EV_Telemetry bus) that taps the
%        signals already feeding the To Workspace blocks (no second acquisition)
%     5. speed set-up saved in the model: scopes do not pop up, Simscape logging off,
%        no Mechanics Explorer window
%     6. benchmark: as-delivered vs fast vs turbo (measured, not promised)
%     7. saves FINAL.slx
%
%   Needs in the same folder: BLDCSpeedControlData.m, BLDCSpeedControlInput.mat,
%   Batteries2_lib.slx, +Batteries2 (folder), BLDCSpeedControl_EV_Layout_v2.slx

p = inputParser;
addParameter(p, 'Rebuild',   false, @islogical);
addParameter(p, 'Benchmark', true,  @islogical);
parse(p, varargin{:});

root = fileparts(mfilename('fullpath'));
cd(root);  addpath(root);
mdl = 'BLDCSpeedControl_EV_Layout_FINAL';
src = 'BLDCSpeedControl_EV_Layout_v2';
finalFile = fullfile(root, [mdl '.slx']);
srcFile   = fullfile(root, [src '.slx']);
say = @(varargin) fprintf(['[CREATE] ' varargin{1} '\n'], varargin{2:end});

say('Folder: %s', root);
bdclose all;

%% 1. files + parameters
need = {'BLDCSpeedControlData.m', 'BLDCSpeedControlInput.mat', 'Batteries2_lib.slx'};
for k = 1:numel(need)
    if ~isfile(fullfile(root, need{k})), error('[CREATE] Missing file: %s', need{k}); end
end
if ~isfolder(fullfile(root, '+Batteries2'))
    warning('[CREATE] Folder +Batteries2 not found next to this script - the battery block may not load.');
end
evalin('base', 'BLDCSpeedControlData;');
say('Parameters loaded (BLDCSpeedControlData.m).');

%% 2. v2 -> FINAL
if p.Results.Rebuild || ~isfile(finalFile)
    if ~isfile(srcFile), error('[CREATE] %s.slx not found - cannot build FINAL.', src); end
    if isfile(finalFile), delete(finalFile); end
    load_system(srcFile);
    save_system(src, finalFile);
    close_system(src, 0);
    say('FINAL created from v2.');
else
    say('FINAL exists - updating it (use ''Rebuild'',true to start from v2).');
end
load_system(finalFile);

%% 3. battery: 5 Ah cell
n = setBattery(mdl);
say('AHCell set in %d block(s).', n);
if n == 0
    warning('[CREATE] No block with AHCell found. Set it by hand: AHCell = 5, unit A*hr.');
end

%% 4. black box
addBlackBox(mdl);
say('BLACK_BOX_LIVE_TELEMETRY added.');

%% 5/6. benchmark (before the fast set-up) + fast set-up
t0 = NaN;  t1 = NaN;  t2 = NaN;
if p.Results.Benchmark
    say('Benchmark: 0.25 s of simulated time per case (each run includes compile).');
    t0 = timeRun(mdl, 'normal', []);
end
setFast(mdl);
say('Fast set-up applied (scopes closed at start, Simscape logging off, no Mechanics Explorer).');
if p.Results.Benchmark
    timeRun(mdl, 'accelerator', []);                 % warm-up: builds the accelerator target
    t1 = timeRun(mdl, 'accelerator', []);
    t2 = timeRun(mdl, 'accelerator', 2e-5);
    fprintf('\n  Benchmark (wall-clock seconds for 0.25 s simulated)\n');
    fprintf('    as delivered (Normal)         : %7.1f s\n', t0);
    fprintf('    fast  (Accelerator)           : %7.1f s   -> %.1fx\n', t1, t0/t1);
    fprintf('    turbo (Accelerator, Ts=2e-5)  : %7.1f s   -> %.1fx\n', t2, t0/t2);
    fprintf('    turbo changes the solver step: check results with Run_Simulation_Log(''Profile'',''turbo'')\n\n');
end

%% 7. save
set_param(mdl, 'SimulationMode', 'normal');          % the live app needs Normal mode
save_system(mdl, finalFile);
say('Saved: %s', finalFile);
say('Next:  Run_Simulation_Log   |   Run_Simulation_Live');
end

% =========================================================================
function n = setBattery(mdl)
blks = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'Variants', 'AllVariants');
n = 0;
for k = 1:numel(blks)
    b = blks{k};
    try
        v = get_param(b, 'AHCell');
        u = get_param(b, 'AHCell_unit');
    catch
        continue
    end
    if ~strcmp(strtrim(v), '5'),    set_param(b, 'AHCell', '5');         end
    if ~strcmp(strtrim(u), 'A*hr'), set_param(b, 'AHCell_unit', 'A*hr'); end
    n = n + 1;
    fprintf('[CREATE]   %s : AHCell=%s %s, P=%s, S=%s\n', b, get_param(b,'AHCell'), ...
        get_param(b,'AHCell_unit'), get_param(b,'P'), get_param(b,'S'));
end
end

% =========================================================================
function addBlackBox(mdl)
bb = [mdl '/BLACK_BOX_LIVE_TELEMETRY'];
te = [mdl '/EV_Telemetry_end'];
if getSimulinkBlockHandle(bb) ~= -1, delete_block(bb); end
if getSimulinkBlockHandle(te) ~= -1, delete_block(te); end

tw = find_system(mdl, 'SearchDepth', 1, 'BlockType', 'ToWorkspace');
if isempty(tw), error('[CREATE] No top-level To Workspace blocks found in %s.', mdl); end
vars = cellfun(@(b) strtrim(get_param(b, 'VariableName')), tw, 'UniformOutput', false);
n = numel(tw);

add_block('built-in/Subsystem', bb, 'Position', [900 40 1100 40+30*(n+2)]);
ln0 = find_system(bb, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'line');
for q = 1:numel(ln0), try, delete_line(ln0(q)); catch, end, end
bl0 = find_system(bb, 'SearchDepth', 1, 'Type', 'Block');
for q = 1:numel(bl0)
    if ~strcmp(bl0{q}, bb), delete_block(bl0{q}); end
end

for k = 1:n
    add_block('built-in/Inport', [bb '/' vars{k}], 'Position', [30 30+50*k 60 44+50*k]);
end
iR = find(strcmpi(vars, 'log_rpm'), 1);
iT = find(strcmpi(vars, 'log_Tq_meas'), 1);
nB = n;
if ~isempty(iR) && ~isempty(iT)
    add_block('simulink/Math Operations/Abs',     [bb '/AbsTq'],  'Position', [150 30+50*iT 180 50+50*iT]);
    add_block('simulink/Math Operations/Product', [bb '/PmechP'], 'Position', [230 60+50*iT 260 90+50*iT]);
    add_block('simulink/Math Operations/Gain',    [bb '/PmechK'], 'Gain', '2*pi/60', 'Position', [300 60+50*iT 340 90+50*iT]);
    nB = n + 1;
end
add_block('simulink/Signal Routing/Bus Creator', [bb '/EV_Telemetry_Bus'], ...
    'Inputs', num2str(nB), 'Position', [450 30 460 30+50*(nB+1)]);
add_block('built-in/Outport', [bb '/EV_Telemetry'], 'Position', [540 40 570 54]);

bc = get_param([bb '/EV_Telemetry_Bus'], 'PortHandles');
for k = 1:n
    ph = get_param([bb '/' vars{k}], 'PortHandles');
    l = add_line(bb, ph.Outport(1), bc.Inport(k));
    set_param(l, 'Name', vars{k});
end
if nB > n
    pr = get_param([bb '/' vars{iR}], 'PortHandles');
    pt = get_param([bb '/' vars{iT}], 'PortHandles');
    pa = get_param([bb '/AbsTq'],  'PortHandles');
    pp = get_param([bb '/PmechP'], 'PortHandles');
    pk = get_param([bb '/PmechK'], 'PortHandles');
    add_line(bb, pt.Outport(1), pa.Inport(1));
    add_line(bb, pa.Outport(1), pp.Inport(1));
    add_line(bb, pr.Outport(1), pp.Inport(2));
    add_line(bb, pp.Outport(1), pk.Inport(1));
    l = add_line(bb, pk.Outport(1), bc.Inport(nB));
    set_param(l, 'Name', 'Mechanical_Power_W');
end
po = get_param([bb '/EV_Telemetry'], 'PortHandles');
l = add_line(bb, bc.Outport(1), po.Inport(1));
set_param(l, 'Name', 'EV_Telemetry');

ph = get_param(bb, 'PortHandles');
for k = 1:n
    pt = get_param(tw{k}, 'PortHandles');
    ln = get_param(pt.Inport(1), 'Line');
    if ln == -1, warning('[CREATE] %s is not connected - input left open.', vars{k}); continue, end
    add_line(mdl, get_param(ln, 'SrcPortHandle'), ph.Inport(k), 'autorouting', 'on');
end
add_block('built-in/Terminator', te, 'Position', [1150 40 1170 60]);
add_line(mdl, ph.Outport(1), get_param(te, 'PortHandles').Inport(1));
end

% =========================================================================
function setFast(mdl)
% settings saved in the model; each one is optional (older releases lack some)
opt = {'SimscapeLogType', 'none'; 'SimscapeLogOpenViewer', 'off'; ...
       'SimMechanicsOpenEditorOnUpdate', 'off'};
for k = 1:size(opt, 1)
    try, set_param(mdl, opt{k,1}, opt{k,2}); catch, end
end
sc = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'Variants', 'AllVariants', 'BlockType', 'Scope');
for k = 1:numel(sc)
    try, set_param(sc{k}, 'OpenAtSimulationStart', 'off'); catch, end
end
end

% =========================================================================
function t = timeRun(mdl, mode, Ts)
in = Simulink.SimulationInput(mdl);
in = in.setModelParameter('SimulationMode', mode, 'StopTime', '0.25');
if ~isempty(Ts), in = in.setVariable('Ts', Ts); end
tic;
try
    sim(in);
    t = toc;
catch ME
    t = NaN;
    fprintf('[CREATE]   %s run failed: %s\n', mode, strtrim(ME.message));
end
end
