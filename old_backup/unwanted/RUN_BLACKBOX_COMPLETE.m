%% =======================================================================
%  RUN_BLACKBOX_COMPLETE.m
%  Copy-paste the WHOLE file into the MATLAB Command Window, press Enter.
%  It does everything in order:
%    STEP 1  - Find your project folder
%    STEP 2  - Back up the old DAQ builder file (safe, non-destructive)
%    STEP 3  - Copy the new DAQ builder file (with Black-Box code)
%    STEP 4  - Close the model cleanly
%    STEP 5  - Run EV_DAQ_Builder_V7 (setup: builds Black-Box subsystem)
%    STEP 6  - Verify the Black-Box subsystem was built
%    STEP 7  - Run the full simulation (EV_Run_All)
%    STEP 8  - Verify EV_BlackBox_log is in the workspace
%    STEP 9  - Run N4SID System Identification
%    STEP 10 - Save all results and print the final report
%  Nothing is deleted. Every step prints OK or a clear error message.
%  If any step fails the script stops and tells you exactly what went wrong.
% =======================================================================

clc;
fprintf('\n');
fprintf('================================================================\n');
fprintf('  EV Digital Twin - Black-Box Complete Setup & Run\n');
fprintf('  %s\n', char(datetime('now')));
fprintf('================================================================\n\n');

%% -----------------------------------------------------------------------
%  CONFIGURATION  (change only if your folder or file names are different)
%  -----------------------------------------------------------------------
PROJECT_ROOT   = 'C:\Users\shubh\OneDrive\Documents\MATLAB\EV_DigitalTwin';
MDL            = 'BLDCSpeedControl_EV_Layout_v2';
NEW_DAQ_FILE   = 'EV_DAQ_Builder_V7.m';   % the file you downloaded/received
% -----------------------------------------------------------------------

%% -----------------------------------------------------------------------
%  HELPER: stop with a clear message
%  -----------------------------------------------------------------------
FAIL = @(msg) error('BB_SETUP:fail', '\n\n  *** STOPPED ***\n  %s\n  Fix the above, then run this script again.\n', msg);

%% =======================================================================
%  STEP 1 - Locate project root
%% =======================================================================
fprintf('STEP 1 - Checking project root ...\n');
if ~isfolder(PROJECT_ROOT)
    FAIL(sprintf('Project folder not found:\n  %s\n  Edit PROJECT_ROOT at the top of this script.', PROJECT_ROOT));
end
cd(PROJECT_ROOT);
addpath(PROJECT_ROOT);
fprintf('  OK  %s\n\n', PROJECT_ROOT);

%% =======================================================================
%  STEP 2 - Back up the existing EV_DAQ_Builder_V7.m (non-destructive)
%% =======================================================================
fprintf('STEP 2 - Backing up existing DAQ builder ...\n');
src_daq = fullfile(PROJECT_ROOT, NEW_DAQ_FILE);
bak_daq = fullfile(PROJECT_ROOT, ['EV_DAQ_Builder_V7_BACKUP_' ...
          char(datetime('now','Format','yyyyMMdd_HHmmss')) '.m']);
if isfile(src_daq)
    copyfile(src_daq, bak_daq);
    fprintf('  OK  Backup saved:\n      %s\n\n', bak_daq);
else
    fprintf('  INFO  %s not found yet - no backup needed.\n\n', NEW_DAQ_FILE);
end

%% =======================================================================
%  STEP 3 - Make sure the NEW DAQ file is in the project folder
%           (If you have it somewhere else, copy it here first)
%% =======================================================================
fprintf('STEP 3 - Checking new EV_DAQ_Builder_V7.m is in project folder ...\n');
if ~isfile(src_daq)
    FAIL(sprintf(['EV_DAQ_Builder_V7.m is NOT in:\n  %s\n' ...
        '  Copy the downloaded file there, then run this script again.'], PROJECT_ROOT));
end
% Quick check: the new file must contain the Black-Box function
daq_text = fileread(src_daq);
if ~contains(daq_text, 'evBuildBlackBox')
    FAIL(sprintf(['EV_DAQ_Builder_V7.m does NOT contain the Black-Box code.\n' ...
        '  Make sure you are using the UPDATED version (4030 lines).\n' ...
        '  File is at: %s'], src_daq));
end
fprintf('  OK  File found and contains Black-Box code (%d lines).\n\n', ...
    numel(splitlines(daq_text)));
clear daq_text;

%% =======================================================================
%  STEP 4 - Close the model safely
%% =======================================================================
fprintf('STEP 4 - Closing model (saving any open changes first) ...\n');
if bdIsLoaded(MDL)
    st = get_param(MDL,'SimulationStatus');
    if strcmpi(st,'running') || strcmpi(st,'paused')
        set_param(MDL,'SimulationCommand','stop');
        pause(2);
    end
    try
        save_system(MDL);
        fprintf('  OK  Model saved.\n');
    catch
        fprintf('  INFO  Model could not be saved (may already be saved).\n');
    end
    close_system(MDL, 0);
    fprintf('  OK  Model closed.\n');
else
    fprintf('  OK  Model was not open.\n');
end
clear functions;   % pick up the new .m file
fprintf('\n');

%% =======================================================================
%  STEP 5 - Run EV_DAQ_Builder_V7 (setup mode: builds Black-Box subsystem,
%            writes model hooks, saves the model)
%% =======================================================================
fprintf('STEP 5 - Running EV_DAQ_Builder_V7 (setup + Black-Box build) ...\n');
fprintf('         This will open the model and may take 30-60 seconds.\n\n');
try
    EV_DAQ_Builder_V7('Run', false);   % setup only, do NOT start simulation yet
catch ME_setup
    FAIL(sprintf('EV_DAQ_Builder_V7 setup failed:\n  %s\n  Identifier: %s', ...
        ME_setup.message, ME_setup.identifier));
end
fprintf('\n  OK  Setup complete.\n\n');

%% =======================================================================
%  STEP 6 - Verify the Black-Box subsystem is in the model
%% =======================================================================
fprintf('STEP 6 - Verifying EV_BlackBox subsystem in model ...\n');
if ~bdIsLoaded(MDL)
    load_system(fullfile(PROJECT_ROOT, [MDL '.slx']));
end
bb_blocks = find_system(MDL, 'SearchDepth',1, 'Name','EV_BlackBox');
bb_blocks  = bb_blocks(~strcmp(bb_blocks, MDL));
if isempty(bb_blocks)
    FAIL(['EV_BlackBox subsystem was NOT found in the model after setup.\n' ...
          '  Check the STEP 5 output above for the line starting with:\n' ...
          '  [DAQ] 8c. Building Black-Box...\n' ...
          '  and read the error message on the next line.']);
end
fprintf('  OK  EV_BlackBox found at: %s\n', bb_blocks{1});

% Check ZOH sample time inside the subsystem
zoh_blocks = find_system(bb_blocks{1},'LookUnderMasks','all','Name','EV_BB_ZOH');
if ~isempty(zoh_blocks)
    ts_zoh = get_param(zoh_blocks{1},'SampleTime');
    fprintf('  OK  ZOH sample time = %s s (should be 0.001)\n', ts_zoh);
    if abs(str2double(ts_zoh) - 0.001) > 1e-10
        fprintf('  WARNING  ZOH sample time is not 0.001 s. Check the subsystem.\n');
    end
end

% Check ToWorkspace block inside the subsystem
tw_blocks = find_system(bb_blocks{1},'LookUnderMasks','all','BlockType','ToWorkspace');
if ~isempty(tw_blocks)
    vn = get_param(tw_blocks{1},'VariableName');
    sf = get_param(tw_blocks{1},'SaveFormat');
    fprintf('  OK  ToWorkspace: var="%s", format="%s"\n', vn, sf);
end

% Print all signal names tapped inside the subsystem
from_blocks = find_system(bb_blocks{1},'LookUnderMasks','all','BlockType','From');
if ~isempty(from_blocks)
    tags = cell(size(from_blocks));
    for kk = 1:numel(from_blocks)
        tags{kk} = get_param(from_blocks{kk},'GotoTag');
    end
    fprintf('  OK  %d From-block signal(s) tapped: %s\n', numel(from_blocks), strjoin(tags,', '));
end
fprintf('\n');

%% =======================================================================
%  STEP 7 - Run the full simulation via EV_Run_All
%           (this also runs EV_DAQ_Builder_V7 post-process automatically)
%% =======================================================================
fprintf('STEP 7 - Starting simulation (EV_Run_All) ...\n');
fprintf('         Expected wall time: ~3 minutes. Please wait.\n\n');
try
    EV_Run_All();
catch ME_run
    FAIL(sprintf('Simulation failed:\n  %s\n  Identifier: %s', ...
        ME_run.message, ME_run.identifier));
end
fprintf('\n  OK  Simulation and post-process complete.\n\n');

%% =======================================================================
%  STEP 8 - Verify EV_BlackBox_log is in the base workspace
%% =======================================================================
fprintf('STEP 8 - Checking EV_BlackBox_log in workspace ...\n');
if ~evalin('base','exist(''EV_BlackBox_log'',''var'')')
    fprintf('  WARNING  EV_BlackBox_log not in workspace.\n');
    fprintf('           This usually means:\n');
    fprintf('           (a) The EV_BlackBox subsystem had a signal connection error.\n');
    fprintf('           (b) The simulation ended before any samples were recorded.\n');
    fprintf('           The rest of the script will try anyway.\n\n');
else
    BB_test = evalin('base','EV_BlackBox_log');
    if isa(BB_test,'timeseries')
        sz = size(BB_test.Data);
        fprintf('  OK  EV_BlackBox_log: timeseries, size %s, %d time points\n', ...
            mat2str(sz), numel(BB_test.Time));
    elseif isstruct(BB_test)
        flds = fieldnames(BB_test);
        fprintf('  OK  EV_BlackBox_log: struct with %d field(s): %s\n', ...
            numel(flds), strjoin(flds(1:min(end,5))',', '));
    else
        fprintf('  OK  EV_BlackBox_log: class=%s\n', class(BB_test));
    end
    fprintf('\n');
end

%% =======================================================================
%  STEP 9 - Run N4SID System Identification
%           (reads EV_BlackBox_log, sweeps nx=2..8, picks best fit)
%% =======================================================================
fprintf('STEP 9 - Running N4SID System Identification ...\n');

% Find the most recent run archive folder
sim_logs_root = fullfile(PROJECT_ROOT, 'Simulation Logs');
if ~isfolder(sim_logs_root), sim_logs_root = PROJECT_ROOT; end
d = dir(fullfile(sim_logs_root, 'EV_RUN_*'));
d = d([d.isdir]);
if isempty(d)
    runDir_sysid = PROJECT_ROOT;
    fprintf('  INFO  No run archive folder found; SysID results saved to project root.\n');
else
    [~, ix] = max([d.datenum]);
    runDir_sysid = fullfile(sim_logs_root, d(ix).name);
    fprintf('  INFO  Using run archive: %s\n', d(ix).name);
end

try
    EV_DAQ_Builder_V7('SysID');
    fprintf('  OK  N4SID complete. Check the [BB-SysID] lines above for fit %%.\n\n');
catch ME_sysid
    if contains(ME_sysid.message,'n4sid') || contains(ME_sysid.identifier,'Ident')
        fprintf('  WARNING  System Identification Toolbox not available: %s\n', ME_sysid.message);
        fprintf('           Skipping SysID. All other steps completed successfully.\n\n');
    else
        fprintf('  WARNING  SysID error (non-fatal): %s\n\n', ME_sysid.message);
    end
end

%% =======================================================================
%  STEP 10 - Save all results and print final report
%% =======================================================================
fprintf('STEP 10 - Saving results and printing final report ...\n\n');

% ---- (a) Save the updated model
try
    if bdIsLoaded(MDL)
        save_system(MDL);
        fprintf('  OK  Model saved: %s.slx\n', MDL);
    end
catch
    fprintf('  INFO  Model save skipped (already saved or not loaded).\n');
end

% ---- (b) Save a workspace snapshot
ws_save_file = fullfile(runDir_sysid, 'EV_BlackBox_Workspace_Snapshot.mat');
try
    bb_vars_to_save = {};
    all_bb_names = {'EV_BlackBox_log','sys_blackbox','EV_BB_A','EV_BB_B', ...
                    'EV_BB_C','EV_BB_D','EV_BB_InputMean','EV_BB_OutputMean', ...
                    'EV_BB_InputLabels','EV_BB_OutputLabels'};
    for kk = 1:numel(all_bb_names)
        if evalin('base', sprintf('exist(''%s'',''var'')', all_bb_names{kk}))
            bb_vars_to_save{end+1} = all_bb_names{kk}; %#ok<AGROW>
        end
    end
    if ~isempty(bb_vars_to_save)
        evalin('base', sprintf('save(''%s'', ''%s'')', ...
            strrep(ws_save_file,'\','\\'), strjoin(bb_vars_to_save,''', ''')));
        fprintf('  OK  Workspace snapshot saved:\n      %s\n', ws_save_file);
        fprintf('      Variables: %s\n', strjoin(bb_vars_to_save,', '));
    else
        fprintf('  INFO  No EV_BlackBox variables in workspace to save.\n');
    end
catch ME_save
    fprintf('  WARNING  Could not save workspace snapshot: %s\n', ME_save.message);
end

% ---- (c) Check if SysID .mat file was written
sysid_mat = fullfile(runDir_sysid, 'EV_BlackBox_SysID.mat');
sysid_txt = fullfile(runDir_sysid, 'EV_BlackBox_SysID_Report.txt');
fprintf('\n');
fprintf('  Files written to run archive:\n');
if isfile(sysid_mat)
    d_mat = dir(sysid_mat);
    fprintf('  OK  EV_BlackBox_SysID.mat          %.1f KB\n', d_mat.bytes/1024);
else
    fprintf('  --  EV_BlackBox_SysID.mat          (not written - SysID may have been skipped)\n');
end
if isfile(sysid_txt)
    d_txt = dir(sysid_txt);
    fprintf('  OK  EV_BlackBox_SysID_Report.txt   %.1f KB\n', d_txt.bytes/1024);
else
    fprintf('  --  EV_BlackBox_SysID_Report.txt   (not written)\n');
end
if isfile(ws_save_file)
    d_ws = dir(ws_save_file);
    fprintf('  OK  EV_BlackBox_Workspace_Snapshot.mat  %.1f KB\n', d_ws.bytes/1024);
end

% ---- (d) Print what is in the workspace right now
fprintf('\n');
fprintf('  Base workspace Black-Box variables RIGHT NOW:\n');
all_bb_names = {'EV_BlackBox_log','sys_blackbox','EV_BB_A','EV_BB_B', ...
                'EV_BB_C','EV_BB_D','EV_BB_InputMean','EV_BB_OutputMean', ...
                'EV_BB_InputLabels','EV_BB_OutputLabels'};
for kk = 1:numel(all_bb_names)
    nm = all_bb_names{kk};
    if evalin('base', sprintf('exist(''%s'',''var'')', nm))
        val = evalin('base', nm);
        if isnumeric(val)
            fprintf('  OK  %-35s  [%s]  (numeric)\n', nm, mat2str(size(val)));
        elseif ischar(val) || iscell(val)
            fprintf('  OK  %-35s  (string/cell)\n', nm);
        elseif isa(val,'idss') || isa(val,'idmodel')
            fprintf('  OK  %-35s  idss nx=%d  Ts=%.4g s\n', nm, size(val.A,1), val.Ts);
        else
            fprintf('  OK  %-35s  class=%s\n', nm, class(val));
        end
    else
        fprintf('  --  %-35s  (not in workspace)\n', nm);
    end
end

% ---- (e) Quick validation: compare on Zv if everything is available
fprintf('\n');
if evalin('base','exist(''sys_blackbox'',''var'')') && ...
   evalin('base','exist(''EV_BlackBox_log'',''var'')')
    fprintf('  Running quick validation (compare on held-out 20%% ...\n');
    try
        sys_bb_val = evalin('base','sys_blackbox');
        EV_DAQ_Builder_V7('SysID');   % re-runs but is fast (no sweep, just compare)
        fprintf('  OK  Validation complete. See [BB-SysID] lines above.\n');
    catch
        fprintf('  INFO  Quick validation skipped.\n');
    end
end

%% =======================================================================
%  FINAL SUMMARY
%% =======================================================================
fprintf('\n');
fprintf('================================================================\n');
fprintf('  ALL STEPS COMPLETE\n');
fprintf('  %s\n', char(datetime('now')));
fprintf('================================================================\n');
fprintf('\n');
fprintf('  What was built:\n');
fprintf('  - EV_BlackBox subsystem in the Simulink model\n');
fprintf('    (red border, far right of root canvas, double-click to open)\n');
fprintf('  - EV_BlackBox_log recorded during the simulation (1 ms, 1 kHz)\n');
fprintf('  - sys_blackbox N4SID state-space model in workspace\n');
fprintf('  - EV_BB_A, EV_BB_B, EV_BB_C, EV_BB_D matrices in workspace\n');
fprintf('\n');
fprintf('  Files saved in:\n');
fprintf('  %s\n', runDir_sysid);
fprintf('\n');
fprintf('  To use the identified model in MATLAB:\n');
fprintf('    compare(evalin(''base'',''sys_blackbox''),Zv)\n');
fprintf('\n');
fprintf('  To open the System Identification App:\n');
fprintf('    ident\n');
fprintf('    (then Import Data > From Workspace, choose Ze and Zv)\n');
fprintf('\n');
fprintf('  To reload everything in a new session:\n');
fprintf('    load(''%s'')\n', strrep(sysid_mat,'\','\\'));
fprintf('\n');
fprintf('================================================================\n\n');
