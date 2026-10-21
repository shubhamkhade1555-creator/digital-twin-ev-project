function fname = EV_MakeReference(src, mode, refXl, runDir)
%EV_MakeReference  Save the numbered clean data of a run and build the comparison graphs + reference workbook.
%
%   AUTOMATIC (nothing to type): EV_DAQ_Builder_V7 calls it at the end of EVERY run (step 14c), so pressing Run in
%   Simulink after typing the Stop Time does the same as RunAll:
%       EV_MakeReference(Clean, [], [], runDir)        Clean = clean table of the run just finished
%   The clean data is saved under a NEW name, never overwritten:
%       EV_DAQ_Clean_<run no>_<seconds x 10, 2 digits>      0.1 s, first run -> EV_DAQ_Clean_1_01 ; 0.5 s, 4th run -> EV_DAQ_Clean_4_05
%
%   MANUAL, from a saved file (needs no simulation):
%       EV_MakeReference('EV_DAQ_Clean_4_05.mat')
%       EV_MakeReference('EV_DAQ_Clean_4_05.mat', 'calculated', 'D:\other\EV_DAQ_Clean_4_05_Reference_Master.xlsx')
%
%   Everything of a run stays in ITS run folder  Simulation Logs\EV_RUN_<date_time>\ :
%       EV_DAQ_Clean_<n>_<s>.mat / .csv
%       Figures\Battery\   Battery_1..4        Figures\Motor\   Motor_1..5
%       Figures\           MASTER pictures + EV_DAQ_Clean_<n>_<s>_Reference_Master.xlsx  (sheet "Inputs" = which files fed the graphs)
%   An old .mat that lies loose in Simulation Logs gets its own folder  Simulation Logs\<name>\Figures\ .
%   Reference workbook default: docs\Reference_Research_Papers\EV_DAQ_Clean_4_05_Reference_Master.xlsx (only for 0.5 s runs,
%   other run lengths use the reference calculated in MATLAB). Switches: EV_Ref_Mode, EV_RefMasterFile (Command Window).

if nargin < 2, mode = ''; end
if nargin < 3, refXl = ''; end
if nargin < 4, runDir = ''; end
fname = '';
if istable(src)
    % ---- automatic call: save this run's clean data under the next free number, inside the run folder
    if isempty(runDir), error('EV_MakeReference:runDir', 'runDir is needed when the clean table is passed'); end
    if isempty(mode),  mode  = char(mrv('EV_Ref_Mode', 'calculated')); end
    if isempty(refXl), refXl = char(mrv('EV_RefMasterFile', '')); end
    runDir = char(runDir);
    while ~isempty(runDir) && (runDir(end) == '\' || runDir(end) == '/'), runDir(end) = []; end
    assignin('base', 'EV_MakeRef_Busy', true);
    cleaner = onCleanup(@() assignin('base', 'EV_MakeRef_Busy', false)); %#ok<NASGU>
    C0 = src;
    logsRoot = fileparts(runDir);
    secCode  = sprintf('%02d', round(max(C0.Time)*10));           % run length x 10 (0.5 s -> 05)
    dd = [dir(fullfile(logsRoot, 'EV_DAQ_Clean_*.mat')); dir(fullfile(logsRoot, 'EV_RUN_*', 'EV_DAQ_Clean_*.mat'))];
    runNo = 1;                                                     % run number over ALL runs (loose old files + run folders)
    for q = 1:numel(dd)
        tk = regexp(dd(q).name, '^EV_DAQ_Clean_(\d+)_', 'tokens', 'once');
        if ~isempty(tk), runNo = max(runNo, str2double(tk{1}) + 1); end
    end
    taken = @(n) isfile(fullfile(logsRoot, [n '.mat'])) || ~isempty(dir(fullfile(logsRoot, 'EV_RUN_*', [n '.mat'])));
    fname = sprintf('EV_DAQ_Clean_%d_%s', runNo, secCode);
    while taken(fname)
        runNo = runNo + 1;  fname = sprintf('EV_DAQ_Clean_%d_%s', runNo, secCode);
    end
    EV_DAQ_Clean = C0; %#ok<NASGU>
    matFile = fullfile(runDir, [fname '.mat']);
    save(matFile, 'EV_DAQ_Clean');
    writetable(C0, fullfile(runDir, [fname '.csv']));
    fprintf('[MakeReference] clean data saved: %s (+ .csv)\n', matFile);
else
    matFile = src;
    if isempty(mode), mode = 'calculated'; end
end

L = load(matFile);
if ~isfield(L, 'EV_DAQ_Clean'), error('EV_MakeReference:var', '%s has no variable EV_DAQ_Clean', matFile); end
C = L.EV_DAQ_Clean;
dm = dir(matFile);                                   % works for a bare name on the path, a relative path or a full path
if isempty(dm), dm = dir(which(matFile)); end
f = fullfile(dm(1).folder, dm(1).name);
matDir = fileparts(f);
[~, prefix] = fileparts(matFile);
[~, matDirName] = fileparts(matDir);
if startsWith(matDirName, 'EV_RUN_')
    outDir   = matDir;                               % new layout: clean data sits in its run folder
    logsRoot = fileparts(matDir);
else
    outDir   = fullfile(matDir, prefix);             % old loose file in Simulation Logs: one folder per run
    logsRoot = matDir;
end
projRoot = fileparts(logsRoot);                      % Simulation Logs -> project folder
if isempty(refXl)
    refXl = fullfile(projRoot, 'docs', 'Reference_Research_Papers', 'EV_DAQ_Clean_4_05_Reference_Master.xlsx');
end
msg = rafigs(C, '', mode, false, prefix, outDir, refXl, f);
fprintf('[EV_MakeReference] %s\n', msg);
if istable(src), assignin('base', 'EV_MakeRef_Name', prefix); end
end

function v = mrv(name, default)
try, v = evalin('base', name); catch, v = default; end
if isempty(v), v = default; end
end

function msg = rafigs(Cl, runDir, mode, show, prefix, outDir, refXl, matFile)
t  = Cl.Time(:);  t = t - t(1);
fprintf('[RunAll]    comparison graphs use %d samples, run length %.4f s\n', numel(t), t(end));
S  = raOurs(Cl, t);
[Rf, Par] = raRef(t, S, mode);
if nargin >= 7 && ~isempty(refXl) && isfile(refXl)
    try
        Rf = raRefFromXlsx(refXl, t, Rf);
        refSrc = sprintf('reference values from %s', refXl);
    catch ME
        refSrc = sprintf('reference calculated in MATLAB (mode %s): %s', mode, ME.message);
        fprintf('[RunAll]    WARN %s\n', refSrc);
    end
else
    refSrc = sprintf('reference calculated in MATLAB (mode %s): workbook not found at %s', mode, refXl);
end
fprintf('[RunAll]    %s\n', refSrc);
% layout (outDir = the EV_RUN_<date_time> folder of this run):
%   <outDir>\Figures\Battery\   Battery_1..4     <outDir>\Figures\Motor\   Motor_1..5
%   <outDir>\Figures\           MASTER pictures + Reference_Master.xlsx (open at once, new names every run)
figDir = fullfile(outDir, 'Figures');
batDir = fullfile(figDir, 'Battery');
motDir = fullfile(figDir, 'Motor');
for dd_ = {figDir, batDir, motDir}
    if ~isfolder(dd_{1}), mkdir(dd_{1}); end
end
if show, vis = 'on'; else, vis = 'off'; end
items = { ...   % ours field, reference field, label, unit, file name, short note
  'Vb',    'Vbatt',  'Battery voltage',      'V',    'Battery_1_Voltage', 'Ref: OCV 44-54 V and Rint 0.05 ohm assumed (not in paper)';
  'Ib',    'Ibatt',  'Battery current',      'A',    'Battery_2_Current', 'Plotted discharge-positive (sign flipped from the logged BatteryCurrent). Ref from paper Kt, Ke, eta';
  'SOC',   'SOC',    'State of charge',      '-',    'Battery_3_SOC',     'SOC moves <0.01 % in 0.5 s: agreement not meaningful';
  'Vcell', 'Vcell',  'Battery cell voltage', 'V',    'Battery_4_Cell',    'Ours 13S10P; ref 16 cells assumed (not in paper)';
  'Vmotor','Vmotor', 'Motor voltage',        'V',    'Motor_1_Voltage',   'Ours = DC-link proxy (motor voltage not logged)';
  'Im',    'Imotor', 'Motor current',        'A',    'Motor_2_Current',   'Ref Kt = 0.153 (paper). Measured Kt 0.245 gives ~13 A';
  'RPM',   'RPM',    'Motor RPM',            'rpm',  'Motor_3_RPM',       'Ref follows our 2950 rpm command';
  'speed', 'speed',  'Vehicle speed',        'km/h', 'Motor_4_Speed',     'Paper has no vehicle: our gear 11:1 and wheel 0.25 m used';
  'Vdc',   'Vdc',    'DC-link voltage',      'V',    'Motor_5_DCLink',    'Ref = 48 V boost bus (paper); ours buck output ramps from 0'};
AG = zeros(size(items,1), 2);
for k = 1:size(items,1)
    o = S.(items{k,1});  r = Rf.(items{k,2});
    [pa, cu] = raAgree(o, r);  AG(k,:) = [pa cu];
    f = figure('Visible', vis, 'Color', 'w', 'Position', [80 80 900 440]);
    ax = axes(f);  raDraw(ax, t, o, r);
    title(ax, sprintf('%s [%s]   point agreement %.1f %%   curve %.1f %%', items{k,3}, items{k,4}, pa, cu));
    ylabel(ax, items{k,4});  xlabel(ax, ['Time (s)     Note: ' items{k,6}]);
    if k <= 4, subDir = batDir; else, subDir = motDir; end      % items 1-4 battery, 5-9 motor
    exportgraphics(f, fullfile(subDir, [prefix '_' items{k,5} '.png']), 'Resolution', 150);
    close(f);
end
mnote = sprintf('Run %.3f s (%d samples). Live simulation vs Electrica 2022 reference (%s).', t(end), numel(t), refSrc);
raMaster(figDir, [prefix '_Battery_MASTER.png'],  items(1:4,:), S, Rf, t, vis, [2 2], AG(1:4,:), mnote);
raMaster(figDir, [prefix '_Motor_MASTER.png'],    items(5:9,:), S, Rf, t, vis, [2 3], AG(5:9,:), mnote);
raMaster(figDir, [prefix '_Combined_MASTER.png'], items,        S, Rf, t, vis, [3 3], AG,       mnote);
inputs = { ...
  'Graph input 1: OUR SYSTEM (different in every run)', matFile; ...
  'Run length (s)',                                     sprintf('%.4f', t(end)); ...
  'Samples',                                            sprintf('%d', numel(t)); ...
  'Graph input 2: REFERENCE (Electrica 2022)',          refSrc; ...
  'Reference mode (used when calculated in MATLAB)',    mode; ...
  'Created',                                            char(datetime('now'))};
fprintf('[MakeReference] input 1 (our system): %s\n[MakeReference] input 2 (reference)  : %s\n', matFile, refSrc);
raExcel(figDir, prefix, t, S, Rf, items, AG, Par, mode, inputs);
msg = sprintf('4 battery graphs (Figures\\Battery) + 5 motor graphs (Figures\\Motor) + 3 masters + %s_Reference_Master.xlsx in %s (%s)', prefix, figDir, refSrc);
end

function raExcel(outDir, prefix, t, S, Rf, items, AG, Par, mode, inputs)
xl = fullfile(outDir, [prefix '_Reference_Master.xlsx']);
if isfile(xl), delete(xl); end
P = table(t, 'VariableNames', {'Time_s'});
for k = 1:size(items,1)
    P.([items{k,5} '_ours']) = S.(items{k,1});
    P.([items{k,5} '_ref'])  = Rf.(items{k,2});
end
writetable(P, xl, 'Sheet', 'Points');
A = table(string(items(:,3)), AG(:,1), AG(:,2), string(items(:,6)), ...
    'VariableNames', {'Graph','PointAgreement_pct','CurveAgreement_pct','Note'});
writetable(A, xl, 'Sheet', 'Agreement');
Q = { 'Kt = Ke (N.m/A = V.s/rad)', Par.k,      'Paper',    'Table I, eq 4'; ...
      'Rline (ohm)',               Par.Rline,  'Derived',  'Table II, 3.24 N.m row'; ...
      'Kt measured (N.m/A)',       Par.Kt_eff, 'Measured', 'Table II: 3.24 N.m / 13.2 A'; ...
      'Overall efficiency',        Par.eta,    'Paper',    'Table IV mean'; ...
      'Battery capacity (Ah)',     Par.Ah,     'Paper',    'Table I'; ...
      'DC link (V)',               Par.Vbus,   'Paper',    'Sec III boost converter'; ...
      'Pack internal R (ohm)',     Par.Rint,   'Assumed',  'not in paper'; ...
      'Rotor inertia J (kg m2)',   Par.J,      'Assumed',  'our Jm'; ...
      'OCV low (V)',               Par.Vlo,    'Assumed',  'not in paper'; ...
      'OCV high (V)',              Par.Vhi,    'Assumed',  'not in paper'; ...
      'Reference cells in series', Par.Ncell,  'Assumed',  'not in paper'; ...
      'Reference mode',            mode,       'Setting',  'EV_Ref_Mode'};
vals = cellfun(@(x) char(string(x)), Q(:,2), 'UniformOutput', false);
Qt = table(string(Q(:,1)), string(vals), string(Q(:,3)), string(Q(:,4)), ...
    'VariableNames', {'Parameter','Value','Status','Source'});
writetable(Qt, xl, 'Sheet', 'Paper_Values');
It = table(string(inputs(:,1)), string(inputs(:,2)), 'VariableNames', {'Item','Value'});
writetable(It, xl, 'Sheet', 'Inputs');
end

function Rf = raRefFromXlsx(xl, t, Rf0)
% reads the reference curves from the reference workbook (Points sheet) instead of recalculating them
Rf = Rf0;
T  = readtable(xl, 'Sheet', 'Points');
tx = T.Time_s;
if abs(tx(end) - t(end)) > 1e-3
    error('RunAll:refLength', 'workbook covers %.3f s, this run %.3f s - reference calculated instead', tx(end), t(end));
end
map = {'Battery_1_Voltage_ref','Vbatt'; 'Battery_2_Current_ref','Ibatt'; 'Battery_3_SOC_ref','SOC'; ...
       'Battery_4_Cell_ref','Vcell'; 'Motor_1_Voltage_ref','Vmotor'; 'Motor_2_Current_ref','Imotor'; ...
       'Motor_3_RPM_ref','RPM'; 'Motor_4_Speed_ref','speed'; 'Motor_5_DCLink_ref','Vdc'};
for k = 1:size(map,1)
    if ~ismember(map{k,1}, T.Properties.VariableNames)
        error('RunAll:refColumn', 'column %s missing in %s', map{k,1}, xl);
    end
    Rf.(map{k,2}) = interp1(tx, T.(map{k,1}), t, 'linear', 'extrap');
end
end

function S = raOurs(Cl, t)
S.Vb  = raCol(Cl, 'BatteryVoltage', nan(size(t)));
S.Ib  = -raCol(Cl, 'BatteryCurrent', nan(size(t)));      % discharge positive
S.SOC = raCol(Cl, 'SOC', []);
if isempty(S.SOC), S.SOC = 1 - cumtrapz(t, S.Ib)/(3600*50); end   % coulomb count, 50 Ah pack
S.RPM = raCol(Cl, 'RPM', nan(size(t)));
S.Im  = raCol(Cl, 'MotorCurrent', nan(size(t)));
S.Vdc = raCol(Cl, 'DCLinkVoltage', raCol(Cl, 'Vdc', nan(size(t))));
S.Vmotor = S.Vdc;                                         % motor voltage not logged: DC link as proxy
S.Vcell  = S.Vb/13;                                       % 13 series cells
S.speed  = S.RPM/11*2*pi/60*0.25*3.6;                     % km/h, gear 11:1, wheel 0.25 m
S.cmd_rpm = raCol(Cl, 'RPMReference', []);
if isempty(S.cmd_rpm), S.cmd_rpm = 2950*min(t/0.227, 1); end
S.Tload = interp1([0 0.23 0.28 max(t)+1], [0 0 3.18 3.18], t, 'linear');
end

function v = raCol(T, name, def)
if ismember(name, T.Properties.VariableNames), v = T.(name)(:); else, v = def(:); end
end

function [R, Par] = raRef(t, S, mode)
% Electrica 2022 (Amalrajan & Gunabalan) constants, same load and speed profile as our run.
%   calculated : Kt = Ke = 0.153 (paper)           original : Kt = 3.24/13.2 measured (Table II)
%   live       : calculated + scope-like ripple and noise
k      = 0.153;
Rline  = (25.91 - k*1460*2*pi/60)/13.2;
Kt_eff = 3.24/13.2;
eta    = mean([83.29 83.48 83.73 82.85 83.36 83.01])/100;
J = 0.002; Rint = 0.05; Vlo = 44; Vhi = 54; Ah = 24; Ncell = 16; Vbus = 48;
Par = struct('k',k,'Rline',Rline,'Kt_eff',Kt_eff,'eta',eta,'Ah',Ah,'Vbus',Vbus, ...
             'Rint',Rint,'J',J,'Vlo',Vlo,'Vhi',Vhi,'Ncell',Ncell);
if strcmp(mode, 'original'), Kt = Kt_eff; else, Kt = k; end
n = numel(t);  dt = t(2) - t(1);
w  = S.cmd_rpm(:)*2*pi/60;
dw = gradient(w, dt);
Im = max((S.Tload(:) + J*dw)/Kt, 0);
Vm = k*w + Im*Rline;
Pin = Vm.*Im/eta;
Vb = zeros(n,1); Ib = zeros(n,1); SOC = ones(n,1);
for i = 1:n
    ocv = Vlo + (Vhi - Vlo)*SOC(i);
    Vb(i) = (ocv + sqrt(max(ocv^2 - 4*Rint*Pin(i), 0)))/2;
    Ib(i) = Pin(i)/Vb(i);
    if i < n, SOC(i+1) = SOC(i) - Ib(i)*dt/(3600*Ah); end
end
R = struct('Vbatt',Vb,'Ibatt',Ib,'SOC',SOC,'Vcell',Vb/Ncell,'Vmotor',Vm,'Imotor',Im, ...
           'RPM',S.cmd_rpm(:),'speed',S.cmd_rpm(:)/11*2*pi/60*0.25*3.6,'Vdc',Vbus*ones(n,1));
if strcmp(mode, 'live')
    rng(1);
    R.Imotor = R.Imotor.*(1 + 0.02*randn(n,1));
    R.Vmotor = R.Vmotor.*(1 + 0.005*randn(n,1));
    R.RPM    = R.RPM.*(1 + 0.01*randn(n,1));
    R.speed  = R.RPM/11*2*pi/60*0.25*3.6;
    R.Vbatt  = R.Vbatt.*(1 + 0.003*randn(n,1));
    R.Ibatt  = R.Ibatt.*(1 + 0.02*randn(n,1));
    R.Vcell  = R.Vbatt/Ncell;
    R.Vdc    = R.Vdc.*(1 + 0.002*randn(n,1));
end
end

function [pa, cu] = raAgree(yo, yr)
yo = yo(:); yr = yr(:);
f   = 0.05*max(abs(yr));
pts = max(0, 1 - abs(yo - yr)./max(abs(yr), f));
pa  = 100*mean(pts(isfinite(pts)));
cu  = max(0, 100*(1 - sqrt(mean((yo - yr).^2, 'omitnan'))/(mean(abs(yr), 'omitnan') + eps)));
end

function raDraw(ax, t, yo, yr)
hold(ax, 'on');
plot(ax, t, yo, '.', 'Color', [0 0.447 0.741],     'MarkerSize', 4);
plot(ax, t, yr, '.', 'Color', [0.851 0.325 0.098], 'MarkerSize', 4);
hold(ax, 'off');
grid(ax, 'on');
legend(ax, {'Our system', 'Reference (Electrica 2022)'}, 'Location', 'best');
end

function raMaster(dirOut, fname, items, S, Rf, t, vis, gridSz, AG, mnote)
f  = figure('Visible', vis, 'Color', 'w', 'Position', [40 40 1400 320*gridSz(1)]);
tl = tiledlayout(f, gridSz(1), gridSz(2), 'TileSpacing', 'compact', 'Padding', 'compact');
for k = 1:size(items,1)
    ax = nexttile(tl);
    raDraw(ax, t, S.(items{k,1}), Rf.(items{k,2}));
    title(ax, sprintf('%s   pt %.1f %% | curve %.1f %%', items{k,3}, AG(k,1), AG(k,2)));
    ylabel(ax, items{k,4});  xlabel(ax, 'Time (s)');
end
title(tl, strrep(fname(1:end-4), '_', ' '));
xlabel(tl, ['Note: ' mnote]);
exportgraphics(f, fullfile(dirOut, fname), 'Resolution', 150);
close(f);
end
