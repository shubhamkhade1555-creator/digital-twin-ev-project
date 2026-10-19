function R = EV_SysID_Auto(runDir, P) %#ok<INUSD>
%EV_SysID_Auto  Automatic black-box system identification after EVERY simulation run.
%
%   Called by EV_DAQ_Builder_V7 in the StopFcn chain (step 14b), so it runs by itself every time
%   you press Run in Simulink (or call RunAll). Nothing to type.
%
%   What it does, in order
%     1. reads EV_BlackBox_log (1 ms, 8 channels) and picks inputs / outputs BY NAME
%     2. removes the mean and divides every channel by its standard deviation (so Vbatt ~ 50 V,
%        SOC ~ 1 and rpm ~ 3000 are comparable and the numbers stay well conditioned)
%     3. splits 80 % estimation / 20 % validation, estimates n4sid models of order 1..6
%     4. picks the order with the best VALIDATION FIT (stable models preferred)
%     5. runs checks (PASS / WARN / FAIL) and prints them in the Command Window
%     6. opens 4 figures (pop-up) and saves them as PNG in <run folder>\Figures
%     7. saves model, data and report in the run folder:
%          EV_BlackBox_SysID.mat   EV_BlackBox_SysID_Report.txt   EV_SysID_Checks.csv
%     8. puts sys_blackbox, EV_BB_A..D, EV_Ze, EV_Zv, EV_SysID_Result in the base workspace
%
%   Change the inputs / outputs in the settings block below (agree the choice with your guide).
%   Optional switches (type in the Command Window, they stay for the session):
%       EV_SysID_Show = false;      % do not open pop-up figures (PNG files are still saved)
%       EV_SysID_FitPass = 80;      % fit (%) needed for PASS (default 70)
%
%   NOTE ON THE OLD FUNCTION: evBlackBoxSysID (inside EV_DAQ_Builder_V7) read the 3rd output of
%   compare(), which is the initial state x0, not the fit. That is why its report showed
%   "val fit 2034946643217408.2%". This file uses the 2nd output (the real NRMSE fit).

%% ---- settings
cfg.orders  = 1:6;                    % state orders tried
cfg.valFrac = 0.3;                    % last 30 % of the run = validation
cfg.minN    = 300;                    % at least 0.3 s of 1 ms samples
cfg.fitPass = bv('EV_SysID_FitPass', 70);
cfg.fitWarn = 40;
cfg.show    = logical(bv('EV_SysID_Show', true));
Ts = 1e-3;

chk = cell(0,3);
fprintf('\n====================================================\n');
fprintf('[SysID] BLACK-BOX SYSTEM IDENTIFICATION (automatic)\n');
fprintf('====================================================\n');

%% ---- 1. read the battery data: archive clean data (1 ms window means) ----
t = []; U = []; Y = []; labels_u = {}; labels_y = {};
try
    C = evalin('base', 'EV_DAQ_Clean');
    need = {'RPM','MotorCurrent','BatteryVoltage','BatteryCurrent'};
    if all(ismember(need, C.Properties.VariableNames))
        M  = [C.RPM C.MotorCurrent C.BatteryVoltage C.BatteryCurrent];
        ok = all(isfinite(M), 2);
        t  = C.Time(ok);  M = M(ok,:);
        U  = M(:,1:2);    Y = M(:,3:4);
        labels_u = {'RPM','MotorCurrent'};
        labels_y = {'Vbatt_V','Ibatt_A'};
        chk = addRow(chk, 'Data source', 'PASS', 'EV_DAQ_Clean (1 ms window means, PWM ripple averaged)');
    end
catch
end
if isempty(t)
    chk = addRow(chk, 'Data source', 'FAIL', 'EV_DAQ_Clean not in the workspace - run the simulation first');
    R = bail(chk);  return
end
t = t - t(1);
N = size(U,1);

%% ---- 2. length and excitation checks ----
if N < cfg.minN
    chk = addRow(chk, 'Samples', 'FAIL', sprintf('%d samples, need at least %d. Use a stop time of 0.5 s or more.', N, cfg.minN));
    R = bail(chk);  return
end
chk = addRow(chk, 'Samples', 'PASS', sprintf('%d samples, %.3f s', N, t(end)));
for k = 1:2
    if std(U(:,k)) < 1e-3*(1 + abs(mean(U(:,k))))
        chk = addRow(chk, ['Excitation ' labels_u{k}], 'FAIL', ...
            'input is flat: the run has no load or speed change to learn from');
        R = bail(chk);  return
    end
end
chk = addRow(chk, 'Excitation', 'PASS', sprintf('RPM range %.0f rpm, current range %.1f A', ...
    range(U(:,1)), range(U(:,2))));

%% ---- 3. normalise and split (70 % estimation, 30 % validation) ----
U0 = mean(U,1);  Us = std(U,0,1);
Y0 = mean(Y,1);  Ys = std(Y,0,1);
Un = (U - U0) ./ Us;
Yn = (Y - Y0) ./ Ys;
Nest = floor((1 - cfg.valFrac) * N);
Ze = iddata(Yn(1:Nest,:),   Un(1:Nest,:),   Ts, 'InputName', labels_u, 'OutputName', labels_y);
Zv = iddata(Yn(Nest+1:N,:), Un(Nest+1:N,:), Ts, 'InputName', labels_u, 'OutputName', labels_y);
tv = t(Nest+1:N);

fprintf('[SysID] Inputs : %s\n', strjoin(labels_u, ', '));
fprintf('[SysID] Outputs: %s\n', strjoin(labels_y, ', '));
fprintf('[SysID] Estimation %d samples | validation %d samples\n', Nest, N - Nest);
fprintf('[SysID] n4sid order sweep (fit = NRMSE %% on the validation part):\n');

%% ---- 4. order sweep -------------------------------------------------------------------------
n4o = n4sidOptions('Focus', 'prediction', 'EstimateCovariance', false);
best = [];  bestN = 0;  bestScore = -Inf;  bestFit = [];
sweep = nan(numel(cfg.orders), 3);          % [order  mean fit  stable]
for q = 1:numel(cfg.orders)
    nx = cfg.orders(q);
    try
        s = n4sid(Ze, nx, n4o);
        [~, fitq] = compare(Zv, s);          % 2nd output = fit (the 3rd is the initial state!)
        fitq = fitq(:)';
        stb  = isstable(s);
        sc   = mean(min(max(fitq, -100), 100));
        sweep(q,:) = [nx sc double(stb)];
        fprintf('[SysID]   nx=%d  mean fit %7.1f %%  stable=%d   (%s)\n', nx, sc, stb, ...
            strjoin(arrayfun(@(a,b) sprintf('%s %.1f%%', b{1}, a), fitq, labels_y, 'UniformOutput', false), ', '));
        rankScore = sc - 1000 * (~stb);       % a stable model always beats an unstable one
        if rankScore > bestScore
            bestScore = rankScore;  best = s;  bestN = nx;  bestFit = fitq;
        end
    catch ME
        fprintf('[SysID]   nx=%d  FAILED: %s\n', nx, ME.message);
    end
end
if isempty(best)
    chk = addRow(chk, 'Estimation', 'FAIL', 'n4sid failed for every order');
    R = bail(chk);  return
end
chk = addRow(chk, 'Estimation', 'PASS', sprintf('n4sid, best order nx = %d (of %d..%d)', bestN, cfg.orders(1), cfg.orders(end)));

%% ---- 5. checks on the chosen model ------------------------------------------------------
pl = pole(best);
if isstable(best)
    chk = addRow(chk, 'Model stable', 'PASS', sprintf('largest pole magnitude %.4f (< 1)', max(abs(pl))));
else
    chk = addRow(chk, 'Model stable', 'FAIL', sprintf('largest pole magnitude %.4f (>= 1): change inputs/outputs or order', max(abs(pl))));
end
bigBC = max(abs([best.B(:); best.C(:)]));
if isfinite(bigBC) && bigBC < 1e3
    chk = addRow(chk, 'Model scaling', 'PASS', sprintf('largest B/C entry %.3g (normalised data)', bigBC));
else
    chk = addRow(chk, 'Model scaling', 'WARN', sprintf('largest B/C entry %.3g: model is badly conditioned', bigBC));
end
lvl = cell(1, numel(bestFit));
for k = 1:numel(bestFit)
    f = bestFit(k);
    if ~isfinite(f) || f < cfg.fitWarn,  lvl{k} = 'FAIL';
    elseif f < cfg.fitPass,              lvl{k} = 'WARN';
    else,                                lvl{k} = 'PASS';
    end
    chk = addRow(chk, ['Fit ' labels_y{k}], lvl{k}, sprintf('%.1f %%  (PASS >= %g, WARN >= %g)', f, cfg.fitPass, cfg.fitWarn));
end

%% ---- 6. physical-unit prediction for the plots -----------------------------------------------
[ypd, ~] = compare(Zv, best);
Ypred = ypd.OutputData .* Ys + Y0;
Ymeas = Zv.OutputData  .* Ys + Y0;

%% ---- 7. figures: pop-up + save --------------------------------------------------------------
figNote = 'figures not created';
try
    if cfg.show, vis = 'on'; else, vis = 'off'; end
    delete(findall(0, 'Type', 'figure', 'Tag', 'EV_SysID'));       % close the figures of the previous run
    figDir = fullfile(runDir, 'Figures');
    if ~isfolder(figDir), mkdir(figDir); end
    nu = numel(labels_u);  ny = numel(labels_y);
    mk = @(nm, pos) figure('Name', nm, 'Tag', 'EV_SysID', 'Color', 'w', 'Visible', vis, 'Position', pos);

    f1 = mk('SysID 1 - data', [40 60 900 680]);
    for k = 1:nu
        subplot(nu+ny, 1, k);  plot(t, U(:,k), 'LineWidth', 1.2);  xline(t(Nest), '--');
        ylabel(labels_u{k}, 'Interpreter', 'none');  grid on;
        if k == 1, title('Identification data: inputs (top), outputs (bottom). Dashed line: estimation | validation'); end
    end
    for k = 1:ny
        subplot(nu+ny, 1, nu+k);  plot(t, Y(:,k), 'LineWidth', 1.2);  xline(t(Nest), '--');
        ylabel(labels_y{k}, 'Interpreter', 'none');  grid on;
    end
    xlabel('Time [s]');

    f2 = mk('SysID 2 - validation (measured vs model)', [80 70 900 640]);
    for k = 1:ny
        subplot(ny, 1, k);
        plot(tv, Ymeas(:,k), 'k', 'LineWidth', 1.5);  hold on;
        plot(tv, Ypred(:,k), 'r--', 'LineWidth', 1.5);
        title(sprintf('%s:  fit %.1f %%  [%s]', labels_y{k}, bestFit(k), lvl{k}), 'Interpreter', 'none');
        ylabel(labels_y{k}, 'Interpreter', 'none');  grid on;
        if k == 1, legend('measured', 'model', 'Location', 'best'); end
    end
    xlabel('Time [s] (validation part of the run)');

    f3 = mk('SysID 3 - poles', [120 80 520 520]);
    th = linspace(0, 2*pi, 200);
    plot(cos(th), sin(th), 'k--');  hold on;
    plot(real(pl), imag(pl), 'rx', 'MarkerSize', 10, 'LineWidth', 2);
    axis equal;  grid on;  xlabel('Real');  ylabel('Imaginary');
    title(sprintf('Poles of the model (nx = %d). Stable if inside the circle', bestN));

    f4 = mk('SysID 4 - order sweep', [160 90 600 420]);
    bar(sweep(:,1), sweep(:,2));  grid on;
    xlabel('State order nx');  ylabel('Mean validation fit [%]');
    title(sprintf('Order sweep (chosen: nx = %d)', bestN));

    % full-run comparison: measured vs model over the whole run (estimation + validation)
    Zall = iddata(Yn, Un, Ts, 'InputName', labels_u, 'OutputName', labels_y);
    [yAll, ~] = compare(Zall, best);
    YpredAll = yAll.OutputData .* Ys + Y0;
    f5 = mk('SysID 5 - whole run (measured vs model)', [60 40 1000 760]);
    for k = 1:ny
        subplot(ny, 1, k);
        plot(t, Y(:,k), 'k', 'LineWidth', 1.4);  hold on;
        plot(t, YpredAll(:,k), 'r--', 'LineWidth', 1.4);
        xline(t(Nest), ':', 'validation starts');
        title(sprintf('%s: whole run, validation fit %.1f %%', labels_y{k}, bestFit(k)), 'Interpreter', 'none');
        ylabel(labels_y{k}, 'Interpreter', 'none');  grid on;
        if k == 1, legend('measured', 'model', 'Location', 'best'); end
    end
    xlabel('Time [s]');

    figs  = [f1 f2 f3 f4 f5];
    names = {'SysID_1_Data.png', 'SysID_2_Validation.png', 'SysID_3_Poles.png', ...
             'SysID_4_OrderSweep.png', 'SysID_5_WholeRun.png'};
    for k = 1:numel(figs)
        saveFigure(figs(k), fullfile(figDir, names{k}));
    end
    drawnow;
    figNote = sprintf('%d figures saved in %s', numel(figs), figDir);
    chk = addRow(chk, 'Figures', 'PASS', figNote);
catch ME
    chk = addRow(chk, 'Figures', 'WARN', ['could not create/save figures: ' ME.message]);
end

%% ---- 8. save + workspace ---------------------------------------------------------------------
sys_blackbox = best;  A = best.A;  B = best.B;  C = best.C;  D = best.D;  fit = bestFit; %#ok<NASGU>
assignin('base', 'sys_blackbox', sys_blackbox);
assignin('base', 'EV_BB_A', A);  assignin('base', 'EV_BB_B', B);  assignin('base', 'EV_BB_C', C);  assignin('base', 'EV_BB_D', D);
assignin('base', 'EV_BB_InputMean',   U0);  assignin('base', 'EV_BB_OutputMean',  Y0);
assignin('base', 'EV_BB_InputScale',  Us);  assignin('base', 'EV_BB_OutputScale', Ys);
assignin('base', 'EV_BB_InputLabels', labels_u);  assignin('base', 'EV_BB_OutputLabels', labels_y);
assignin('base', 'EV_Ze', Ze);  assignin('base', 'EV_Zv', Zv);

bbMat = fullfile(runDir, 'EV_BlackBox_SysID.mat');
try
    save(bbMat, 'sys_blackbox', 'A', 'B', 'C', 'D', 'U0', 'Y0', 'Us', 'Ys', 'labels_u', 'labels_y', 'Ze', 'Zv', 'fit', 'bestN', 'cfg');
    chk = addRow(chk, 'Saved model', 'PASS', bbMat);
catch ME
    chk = addRow(chk, 'Saved model', 'WARN', ['could not save .mat: ' ME.message]);
end
try
    writetable(cell2table(chk, 'VariableNames', {'Check', 'Result', 'Detail'}), fullfile(runDir, 'EV_SysID_Checks.csv'));
catch
end

[verdict, nP, nW, nF] = verdictOf(chk);
try
    fid = fopen(fullfile(runDir, 'EV_BlackBox_SysID_Report.txt'), 'w');
    fprintf(fid, '=== EV Digital Twin - Black-Box System Identification Report ===\n');
    fprintf(fid, 'Date       : %s\n', char(datetime('now')));
    fprintf(fid, 'Tool       : n4sid (System Identification Toolbox), discrete, Ts = 1 ms\n');
    fprintf(fid, 'Data       : EV_BlackBox_log, %d samples, %.3f s\n', N, t(end));
    fprintf(fid, 'Inputs     : %s\nOutputs    : %s\n', strjoin(labels_u, ', '), strjoin(labels_y, ', '));
    fprintf(fid, 'Split      : estimation %d samples, validation %d samples\n', Nest, N-Nest);
    fprintf(fid, 'Best order : nx = %d\n\nRESULT     : %s   (PASS %d  WARN %d  FAIL %d)\n\nCHECKS\n', bestN, verdict, nP, nW, nF);
    for k = 1:size(chk,1), fprintf(fid, '  [%-4s] %-22s %s\n', chk{k,2}, chk{k,1}, chk{k,3}); end
    fprintf(fid, '\nThe model works on NORMALISED data:  u_n = (u - U0)./Us ,  y = Ys.*y_n + Y0\n');
    fprintf(fid, 'U0 = %s\nUs = %s\nY0 = %s\nYs = %s\n', mat2str(U0,6), mat2str(Us,6), mat2str(Y0,6), mat2str(Ys,6));
    fprintf(fid, '\nA = %s\nB = %s\nC = %s\nD = %s\n', mat2str(A,4), mat2str(B,4), mat2str(C,4), mat2str(D,4));
    fprintf(fid, '\nTo open the System Identification app with this run:  systemIdentification  then import EV_Ze / EV_Zv from the workspace.\n');
    fclose(fid);
catch
end

%% ---- 9. print the result ------------------------------------------------------------------
printChecks(chk);
fprintf('\n[SysID] RESULT: %s   (PASS %d  WARN %d  FAIL %d)\n', verdict, nP, nW, nF);
fprintf('[SysID] Files in %s :\n[SysID]   EV_BlackBox_SysID.mat, EV_BlackBox_SysID_Report.txt, EV_SysID_Checks.csv, Figures\\SysID_*.png\n', runDir);
fprintf('[SysID] Workspace: sys_blackbox, EV_BB_A..D, EV_Ze, EV_Zv, EV_SysID_Result\n');
fprintf('====================================================\n\n');

R = struct('ok', nF == 0, 'verdict', verdict, 'checks', {chk}, 'fit', bestFit, 'order', bestN, ...
           'sys', sys_blackbox, 'folder', runDir);
assignin('base', 'EV_SysID_Result', R);
end


%% =========================================================================================
%%  local helpers
%% =========================================================================================
function chk = addRow(chk, name, level, detail)
chk = [chk; {name, level, detail}];
end

function R = bail(chk)
% early exit: print what we have and say clearly that SysID was NOT done
printChecks(chk);
[verdict, nP, nW, nF] = verdictOf(chk);
fprintf('\n[SysID] RESULT: %s   (PASS %d  WARN %d  FAIL %d)\n', verdict, nP, nW, nF);
fprintf('====================================================\n\n');
R = struct('ok', false, 'verdict', verdict, 'checks', {chk});
try, assignin('base', 'EV_SysID_Result', R); catch, end
end

function [verdict, nP, nW, nF] = verdictOf(chk)
lv = chk(:,2);
nP = sum(strcmp(lv, 'PASS'));  nW = sum(strcmp(lv, 'WARN'));  nF = sum(strcmp(lv, 'FAIL'));
if nF > 0,       verdict = 'NOT DONE PROPERLY (FAIL)';
elseif nW > 0,   verdict = 'DONE, WITH WARNINGS';
else,            verdict = 'DONE - ALL CHECKS PASSED';
end
end

function printChecks(chk)
fprintf('\n[SysID] CHECKS\n');
for k = 1:size(chk,1)
    fprintf('[SysID]   [%-4s] %-22s %s\n', chk{k,2}, chk{k,1}, chk{k,3});
end
end

function v = bv(name, default)
try, v = evalin('base', name); catch, v = default; end
if isempty(v), v = default; end
end

function lab = bbLabels(nc)
lab = {};
try
    if bdIsLoaded('BLDCSpeedControl_EV_Layout_v2')
        lab = get_param('BLDCSpeedControl_EV_Layout_v2/EV_BlackBox', 'UserData');
    end
catch
    lab = {};
end
if ~iscell(lab) || isempty(lab)
    try, lab = evalin('base', 'EV_BB_ColumnLabels'); catch, lab = {}; end
end
if ~iscell(lab) || numel(lab) ~= nc
    def = {'Vbatt_V', 'Ibatt_A', 'SOC', 'RPM_rpm', 'Idc_f_A', 'Vdc_m_V', 'omega_wheel', 'Torque_Nm'};
    if nc == 8, lab = def; elseif nc == 7, lab = def(1:7); end
end
if ~iscell(lab), lab = {}; end
lab = lab(:)';
end

function saveFigure(fg, f)
try
    exportgraphics(fg, f, 'Resolution', 150);
catch
    saveas(fg, f);
end
end
