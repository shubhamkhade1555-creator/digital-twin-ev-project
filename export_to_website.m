function export_to_website(runDir)
%EXPORT_TO_WEBSITE  Copy one run's logs and replay data into website/data/runs.
%   export_to_website            newest EV_RUN_ folder in Simulation Logs
%   export_to_website(runDir)    a given EV_RUN_ folder
%   Then commit and push the website folder so the Simulation logs tab shows the run.

root = fileparts(mfilename('fullpath'));
if nargin < 1 || isempty(runDir)
    d = dir(fullfile(root,'Simulation Logs','EV_RUN_*'));
    d = d([d.isdir]);
    if isempty(d), error('export_to_website:none','No EV_RUN_ folder found in Simulation Logs.'); end
    [~, ix] = sort({d.name});
    runDir = fullfile(d(ix(end)).folder, d(ix(end)).name);
end
[~, runID] = fileparts(runDir);
outDir = fullfile(root,'website','data','runs',runID);
if ~isfolder(outDir), mkdir(outDir); end

% 1. log files
logs = struct('cmd','10_Command_Log.txt','sim','11_Simulation_Log.txt','sys','EV_BlackBox_SysID_Report.txt');
fn = fieldnames(logs);
for k = 1:numel(fn)
    src = fullfile(runDir, logs.(fn{k}));
    if isfile(src)
        copyfile(src, fullfile(outDir, logs.(fn{k})));
    else
        warning('export_to_website:missing','%s not found in %s', logs.(fn{k}), runDir);
    end
end

% 2. replay data: 1 ms cleaned table of this run (same run as the logs)
xl = fullfile(runDir,'03_Cleaned_Data.xlsx');
if ~isfile(xl), error('export_to_website:noData','%s not found.', xl); end
C = readtable(xl, 'Sheet', 'Cleaned_Data');
writetable(C, fullfile(outDir,'replay.csv'));

% 3. result and time from the command log
result = 'UNKNOWN';
cmdFile = fullfile(runDir, logs.cmd);
if isfile(cmdFile)
    tok = regexp(fileread(cmdFile), 'FINAL V&V STATUS\s*:\s*(\S+)', 'tokens', 'once');
    if ~isempty(tok), result = tok{1}; end
end
when = runID;
tt = regexp(runID, 'EV_RUN_(\d{8})_(\d{6})', 'tokens', 'once');
if ~isempty(tt)
    when = datestr(datenum([tt{1} tt{2}], 'yyyymmddHHMMSS'), 'dd-mmm-yyyy HH:MM:SS');
end
entry = struct('id', runID, 'date', when, ...
    'settings', sprintf('stop %.3g s, %d samples', C.Time(end), height(C)), ...
    'result', result, ...
    'files', struct('cmd', logs.cmd, 'sim', logs.sim, 'sys', logs.sys, 'replay', 'replay.csv'));

% 4. index.json: one entry per run, the same run replaces its old entry
idxFile = fullfile(root,'website','data','runs','index.json');
entries = {};
if isfile(idxFile)
    old = jsondecode(fileread(idxFile));
    if iscell(old)
        entries = old(:)';
    elseif isstruct(old)
        entries = num2cell(old(:))';
    end
end
keep = true(1, numel(entries));
for k = 1:numel(entries)
    keep(k) = ~strcmp(entries{k}.id, runID);
end
entries = [entries(keep), {entry}];
fid = fopen(idxFile, 'w');
fprintf(fid, '%s\n', jsonencode(entries, 'PrettyPrint', true));
fclose(fid);

fprintf('Exported %s to website/data/runs/%s\n', runID, runID);
fprintf('Index updated: %d run(s) listed in %s\n', numel(entries), idxFile);
fprintf('Next: commit and push the website folder to GitHub.\n');
end
