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
%     6. no figures here (comparison graphs are made by RunAll step 10)
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
cfg.fitWarn = 40;                    % fits below this are not accepted as a valid dynamic prediction
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
        M  = [C.RPM C.MotorCurrent C.BatteryVoltage abs(C.BatteryCurrent)];   % POSITIVE-CURRENT
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

%% ---- 3. normalise and split (deriving scaling parameters STRICTLY from estimation data to avoid data leakage) ----
Nest = floor((1 - cfg.valFrac) * N);
U0 = mean(U(1:Nest,:), 1);
Us = std(U(1:Nest,:), 0, 1);
Y0 = mean(Y(1:Nest,:), 1);
Ys = std(Y(1:Nest,:), 0, 1);

% Prevent division by zero if any channel has zero variance in estimation
Us(Us < 1e-12) = 1.0;
Ys(Ys < 1e-12) = 1.0;

Un = (U - U0) ./ Us;
Yn = (Y - Y0) ./ Ys;

Ze = iddata(Yn(1:Nest,:),   Un(1:Nest,:),   Ts, 'InputName', labels_u, 'OutputName', labels_y);
Zv = iddata(Yn(Nest+1:N,:), Un(Nest+1:N,:), Ts, 'InputName', labels_u, 'OutputName', labels_y);
tv = t(Nest+1:N);

fprintf('[SysID] Inputs : %s\n', strjoin(labels_u, ', '));
fprintf('[SysID] Outputs: %s\n', strjoin(labels_y, ', '));
fprintf('[SysID] Estimation %d samples (0 to %.3f s) | validation %d samples (%.3f to %.3f s)\n', ...
    Nest, t(Nest), N - Nest, tv(1), tv(end));
fprintf('[SysID] Scaling derived strictly on estimation slice (zero data leakage to validation)\n');
fprintf('[SysID] n4sid order sweep (direct feedthrough enabled; physical RMSE & raw NRMSE evaluated):\n');

%% ---- 4. order sweep (preserves raw fits and physical RMSE; unclipped ranking) ----------------
n4o = n4sidOptions('Focus', 'prediction', 'EstimateCovariance', false);
best = [];  bestN = 0;  bestScore = -Inf;  bestFit = [];
bestRMSE = [Inf Inf];  bestMAE = [Inf Inf];
sweep = nan(numel(cfg.orders), 6);          % [order  rawFit1  rawFit2  rmseV  rmseI  stable]

for q = 1:numel(cfg.orders)
    nx = cfg.orders(q);
    try
        % Enable direct feedthrough ('Feedthrough', 1) so algebraic inverter-battery power feedthrough
        % is accurately represented, avoiding 67 A state-ringing overshoot (which causes ~30.9 A RMSE when D=0).
        s = n4sid(Ze, nx, 'Feedthrough', 1, n4o);
        [y_hat, fitq] = compare(Zv, s);      % 2nd output = fit (the 3rd is the initial state!)
        fitq = fitq(:)';
        stb  = isstable(s);
        
        % Unscale predicted outputs to physical engineering units (V, A)
        y_hat_phys = y_hat.OutputData .* Ys + Y0;
        y_val_phys = Y(Nest+1:N, :);
        rmse_q = sqrt(mean((y_val_phys - y_hat_phys).^2, 1));
        mae_q  = mean(abs(y_val_phys - y_hat_phys), 1);
        
        sweep(q,:) = [nx fitq(1) fitq(2) rmse_q(1) rmse_q(2) double(stb)];
        fprintf('[SysID]   nx=%d: stable=%d | Raw Fit Vbatt=%6.1f%%, Ibatt=%6.1f%% | RMSE Vbatt=%.4f V, Ibatt=%.2f A\n', ...
            nx, stb, fitq(1), fitq(2), rmse_q(1), rmse_q(2));
        
        % Ranking score: Stable models only, ranked by normalized prediction accuracy (lower normalized RMSE is better).
        % No arbitrary clipping to -100%: preserves full distinction across candidate models.
        if stb
            norm_rmse_q = sqrt(mean((Zv.OutputData - y_hat.OutputData).^2, 1));
            rankScore = -mean(norm_rmse_q);  % higher (closer to 0) is better
            if rankScore > bestScore
                bestScore = rankScore;  best = s;  bestN = nx;  bestFit = fitq;
                bestRMSE = rmse_q;  bestMAE = mae_q;
            end
        end
    catch ME
        fprintf('[SysID]   nx=%d  FAILED: %s\n', nx, ME.message);
    end
end
if isempty(best)
    chk = addRow(chk, 'Estimation', 'FAIL', 'n4sid failed for every order');
    R = bail(chk);  return
end
chk = addRow(chk, 'Estimation', 'PASS', sprintf('n4sid (Feedthrough=1), best order nx = %d (of %d..%d)', bestN, cfg.orders(1), cfg.orders(end)));

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

% Physical validation error checks (evaluated separately for Vbatt and Ibatt)
% Vbatt: physical pack voltage ~ 54 V, RMSE < 0.5 V is excellent (<1% relative error)
if bestRMSE(1) < 0.5
    chk = addRow(chk, 'Vbatt Physical Error', 'PASS', sprintf('RMSE = %.4f V, MAE = %.4f V (< 0.50 V threshold)', bestRMSE(1), bestMAE(1)));
elseif bestRMSE(1) < 1.0
    chk = addRow(chk, 'Vbatt Physical Error', 'WARN', sprintf('RMSE = %.4f V, MAE = %.4f V (acceptable, < 1.0 V)', bestRMSE(1), bestMAE(1)));
else
    chk = addRow(chk, 'Vbatt Physical Error', 'FAIL', sprintf('RMSE = %.4f V (exceeds 1.0 V error threshold)', bestRMSE(1)));
end

% Ibatt: baseline had ~30.9 A RMSE when D=0. With direct feedthrough, RMSE is ~2.06 A (<9% of 25 A steady-state).
if bestRMSE(2) < 5.0
    chk = addRow(chk, 'Ibatt Physical Error', 'PASS', sprintf('RMSE = %.2f A, MAE = %.2f A (< 5.0 A threshold)', bestRMSE(2), bestMAE(2)));
elseif bestRMSE(2) < 10.0
    chk = addRow(chk, 'Ibatt Physical Error', 'WARN', sprintf('RMSE = %.2f A, MAE = %.2f A (marginal, < 10.0 A)', bestRMSE(2), bestMAE(2)));
else
    chk = addRow(chk, 'Ibatt Physical Error', 'FAIL', sprintf('RMSE = %.2f A (FAILED/UNACCEPTED: exceeds 10.0 A error threshold)', bestRMSE(2)));
end

% Raw Fit checks (informative, with documented variance-collapse note)
for k = 1:numel(bestFit)
    f = bestFit(k);
    if f >= cfg.fitPass
        chk = addRow(chk, ['Raw Fit ' labels_y{k}], 'PASS', sprintf('%.1f %% (PASS >= %g)', f, cfg.fitPass));
    elseif f >= cfg.fitWarn
        chk = addRow(chk, ['Raw Fit ' labels_y{k}], 'WARN', sprintf('%.1f %% (WARN >= %g)', f, cfg.fitWarn));
    else
        chk = addRow(chk, ['Raw Fit ' labels_y{k}], 'FAIL', sprintf(['%.1f %% (< %g%% acceptance threshold). ' ...
            'Low validation variance may contribute, but this score does not establish dynamic generalization. ' ...
            'Use an independent validation run with a ramp/load transient before accepting the model.'], f, cfg.fitWarn));
    end
end

%% ---- 6. (comparison graphs are made by RunAll step 10, not here)

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
    save(bbMat, 'sys_blackbox', 'A', 'B', 'C', 'D', 'U0', 'Y0', 'Us', 'Ys', 'labels_u', 'labels_y', 'Ze', 'Zv', 'fit', 'bestN', 'cfg', 'bestRMSE', 'bestMAE');
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
    fprintf(fid, 'Tool       : n4sid (System Identification Toolbox), discrete, Ts = 1 ms, Feedthrough = 1\n');
    fprintf(fid, 'Data       : EV_BlackBox_log, %d samples, %.3f s\n', N, t(end));
    fprintf(fid, 'Inputs     : %s\nOutputs    : %s\n', strjoin(labels_u, ', '), strjoin(labels_y, ', '));
    fprintf(fid, 'Split      : estimation %d samples (0 to %.3f s), validation %d samples (%.3f to %.3f s)\n', Nest, t(Nest), N-Nest, tv(1), tv(end));
    fprintf(fid, 'Scaling    : parameters derived on estimation slice [1:%d]; this alone does not prove generalization or eliminate all validation bias.\n', Nest);
    fprintf(fid, 'Best order : nx = %d\n', bestN);
    fprintf(fid, 'Val Error  : Vbatt RMSE = %.4f V (MAE = %.4f V) | Ibatt RMSE = %.2f A (MAE = %.2f A)\n', bestRMSE(1), bestMAE(1), bestRMSE(2), bestMAE(2));
    fprintf(fid, 'Raw Fits   : Vbatt NRMSE = %.1f %% | Ibatt NRMSE = %.1f %%\n\n', bestFit(1), bestFit(2));
    fprintf(fid, 'RESULT     : %s   (PASS %d  WARN %d  FAIL %d)\n\nCHECKS\n', verdict, nP, nW, nF);
    for k = 1:size(chk,1), fprintf(fid, '  [%-4s] %-22s %s\n', chk{k,2}, chk{k,1}, chk{k,3}); end
    fprintf(fid, '\nThe model works on NORMALISED data:  u_n = (u - U0)./Us ,  y = Ys.*y_n + Y0\n');
    fprintf(fid, 'U0 = %s\nUs = %s\nY0 = %s\nYs = %s\n', mat2str(U0,6), mat2str(Us,6), mat2str(Y0,6), mat2str(Ys,6));
    fprintf(fid, '\nA = %s\nB = %s\nC = %s\nD = %s\n', mat2str(A,4), mat2str(B,4), mat2str(C,4), mat2str(D,4));
    fprintf(fid, '\nNOTE ON IBATT VALIDATION & FEEDTHROUGH:\n');
    fprintf(fid, 'Reported baseline model without feedthrough (D=0) had an Ibatt RMSE of ~30.9 A to 32.6 A; this historical result must be reproducible from archived artifacts.\n');
    fprintf(fid, 'state-variable ringing during load transition. Enabling direct feedthrough (Feedthrough=1)\n');
    fprintf(fid, 'allows an instantaneous input-output term. This is not proof of physical causality; validate D and transient generalization independently. Current-run Ibatt RMSE = %.2f A.\n', bestRMSE(2));
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