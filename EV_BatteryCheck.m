function R = EV_BatteryCheck(varargin)
%EV_BatteryCheck  Checks the battery pack files, re-compiles them and reports PASS / WARN / FAIL.
%
%   EV_BatteryCheck                 checks Batteries2.slx, Batteries2_lib.slx and the main EV model
%   EV_BatteryCheck('Compile',false) skips the compile (Update Diagram) timing tests
%   EV_BatteryCheck('Main',false)    skips the (slow) compile of the full EV model
%
%   Run it from the project folder (the one that contains the .slx files and the +Batteries2 folder).
%   Nothing is changed or saved. The result table is also put in the base workspace as EV_BatteryCheck_Result.

p = inputParser;
addParameter(p, 'Compile', true, @islogical);
addParameter(p, 'Main',    true, @islogical);
parse(p, varargin{:});
doCompile = p.Results.Compile;  doMain = p.Results.Main;

MAINMDL = 'BLDCSpeedControl_EV_Layout_v2';
rows = cell(0,3);
add = @(n,l,d) {n, l, d};
root = pwd;

fprintf('\n====================================================\n');
fprintf('[BattCheck] BATTERY CHECK  (folder: %s)\n', root);
fprintf('====================================================\n');

%% 1. products and path
try
    v = ver;  names = {v.Name};
    hasSim  = any(strcmp(names,'Simscape'));
    hasBatt = any(contains(names,'Simscape Battery'));
    rows(end+1,:) = add('Simscape installed', ifs(hasSim,'PASS','FAIL'), 'Simscape product');
    rows(end+1,:) = add('Simscape Battery installed', ifs(hasBatt,'PASS','FAIL'), 'needed for Batteries2.Modules.ModuleType1');
catch ME
    rows(end+1,:) = add('Product check', 'WARN', ME.message);
end

pkgDir = fullfile(root, '+Batteries2');
rows(end+1,:) = add('+Batteries2 folder', ifs(isfolder(pkgDir),'PASS','FAIL'), ...
    ifs(isfolder(pkgDir), pkgDir, 'missing in the current folder: this makes the block icon show "???" and can break compile'));
if isfolder(pkgDir) && isempty(strfind(path, root)) %#ok<STREMP>
    addpath(root);
    rows(end+1,:) = add('Project on path', 'WARN', 'folder was not on the MATLAB path - added for this session');
else
    rows(end+1,:) = add('Project on path', 'PASS', 'ok');
end
w = which('Batteries2.Modules.ModuleType1');
rows(end+1,:) = add('Batteries2.Modules.ModuleType1', ifs(~isempty(w),'PASS','FAIL'), ifs(~isempty(w), w, 'class not found on the path'));

%% 2. files
files = {'Batteries2.slx','Batteries2_lib.slx',[MAINMDL '.slx']};
for k = 1:numel(files)
    rows(end+1,:) = add(['File ' files{k}], ifs(isfile(fullfile(root,files{k})),'PASS','FAIL'), fullfile(root,files{k})); %#ok<AGROW>
end

%% 3. parameters of every battery module block, in each model
mdls = {'Batteries2', MAINMDL};
cellsWanted = 130;  AhWanted = 5;
for m = 1:numel(mdls)
    mdl = mdls{m};
    f = fullfile(root,[mdl '.slx']);
    if ~isfile(f), continue, end
    try
        if ~bdIsLoaded(mdl), load_system(f); end
        blks = find_system(mdl, 'LookUnderMasks','all', 'FollowLinks','on', 'BlockType','Reference');
        isMod = false(size(blks));
        for k = 1:numel(blks)
            try, isMod(k) = contains(get_param(blks{k},'SourceBlock'), 'ModuleType1'); catch, end
        end
        blks = blks(isMod);
        rows(end+1,:) = add([mdl ': battery module blocks'], ifs(~isempty(blks),'PASS','FAIL'), sprintf('%d block(s) of type ModuleType1', numel(blks))); %#ok<AGROW>
        for k = 1:numel(blks)
            b = blks{k};
            ah  = str2double(strtrim(get_param(b,'AHCell')));
            tm  = strtrim(get_param(b,'thermal_massCell'));
            icn = strtrim(get_param(b,'iCell'));
            nC  = sscanf(regexprep(icn,'[^0-9,]',' '), '%f');  nC = nC(end);
            rows(end+1,:) = add([mdl ': AHCell'], ifs(ah == AhWanted,'PASS','WARN'), ...
                sprintf('%g Ah per cell = %g Ah pack (13S10P). %s', ah, ah*10, ...
                ifs(ah == AhWanted,'matches pack_Ah = 50','differs from pack_Ah = 50 in BLDCSpeedControlData.m'))); %#ok<AGROW>
            rows(end+1,:) = add([mdl ': cells in module'], ifs(nC == cellsWanted,'PASS','WARN'), ...
                sprintf('%g cells (13S10P = 130) - every cell is a separate Simscape model: this is why compile is slow', nC)); %#ok<AGROW>
            rows(end+1,:) = add([mdl ': thermal mass'], 'INFO', sprintf('thermal_massCell = %s J/K per cell', tm)); %#ok<AGROW>
        end
    catch ME
        rows(end+1,:) = add([mdl ': parameter read'], 'WARN', ME.message); %#ok<AGROW>
    end
end

%% 4. parameter file consistency
try
    BLDCSpeedControlData;  %#ok<VUNUS>
catch
end
cs = evB('cells_series',NaN);  cp = evB('cells_parallel',NaN);  pk = evB('pack_Ah',NaN);
rows(end+1,:) = add('Parameter file pack', ifs(cs==13 && cp==10 && pk==50,'PASS','WARN'), sprintf('%gS%gP, %g Ah', cs, cp, pk));
vFull = 13*4.19;  vEmpty = 13*3.49;
rows(end+1,:) = add('Pack voltage window', 'INFO', sprintf('%.1f V (empty) ... %.1f V (full); Vdc = %g V', vEmpty, vFull, evB('Vdc',NaN)));

%% 5. compile timing
if doCompile
    tests = {'Batteries2'};
    if doMain, tests{end+1} = MAINMDL; end %#ok<AGROW>
    for k = 1:numel(tests)
        mdl = tests{k};
        if ~isfile(fullfile(root,[mdl '.slx'])), continue, end
        fprintf('[BattCheck] Compile test (Update Diagram): %s ... \n', mdl);
        try
            if ~bdIsLoaded(mdl), load_system(fullfile(root,[mdl '.slx'])); end
            if bdIsLibrary(mdl)
                rows(end+1,:) = add(['Compile ' mdl], 'INFO', 'is a library: it cannot be simulated alone, it is compiled as part of the EV model'); %#ok<AGROW>
                continue
            end
            t0 = tic;
            set_param(mdl, 'SimulationCommand', 'update');
            tc = toc(t0);
            lvl = 'PASS';  if tc > 120, lvl = 'WARN'; end
            rows(end+1,:) = add(['Compile ' mdl], lvl, sprintf('%.1f s (Update Diagram, no simulation)', tc)); %#ok<AGROW>
        catch ME
            rows(end+1,:) = add(['Compile ' mdl], 'FAIL', strtrim(ME.message)); %#ok<AGROW>
            try
                for c = 1:numel(ME.cause), rows(end+1,:) = add(['  cause ' num2str(c)], 'FAIL', strtrim(ME.cause{c}.message)); end %#ok<AGROW>
            catch
            end
        end
    end
end

%% 5b. mask icon images used by the pack blocks (the "???" icon)
imgs = {'moduleAssembly_1.JPG','pack_2.JPG'};
for k = 1:numel(imgs)
    ok = ~isempty(which(imgs{k}));
    rows(end+1,:) = add(['Icon image ' imgs{k}], ifs(ok,'PASS','WARN'), ifs(ok, which(imgs{k}), 'not on the path: the block icon shows ??? (cosmetic only). Copy the file into the project folder')); %#ok<AGROW>
end

%% 6. print
fprintf('\n[BattCheck] RESULT\n');
nF = 0; nW = 0;
for k = 1:size(rows,1)
    fprintf('[BattCheck]   [%-4s] %-34s %s\n', rows{k,2}, rows{k,1}, rows{k,3});
    nF = nF + strcmp(rows{k,2},'FAIL');  nW = nW + strcmp(rows{k,2},'WARN');
end
fprintf('\n[BattCheck] %d FAIL, %d WARN\n====================================================\n\n', nF, nW);
R = cell2table(rows, 'VariableNames', {'Check','Result','Detail'});
assignin('base', 'EV_BatteryCheck_Result', R);
try, writetable(R, fullfile(root,'EV_BatteryCheck.csv')); catch, end
end

function s = ifs(c, a, b)
if c, s = a; else, s = b; end
end

function v = evB(name, d)
try, v = evalin('base', name); catch, try, v = evalin('caller', name); catch, v = d; end, end
if isempty(v), v = d; end
end