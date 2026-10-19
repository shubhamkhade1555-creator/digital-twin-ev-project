function varargout = EV_Twin_App
%EV_TWIN_APP  EV digital twin: fault scenarios, incident chain and prevention.
%   Same reduced-order model, scenarios and protection logic as the website dashboard.
%   Needs MATLAB only (no Simulink). Start with:   EV_Twin_App
%   Defaults = values of BLDCSpeedControlData.m. "Reset to defaults" restores them.
%   Reduced-order estimates for design review and teaching, not a replacement for the
%   Simulink model.

DEF = evDefaults();
SC  = evScenarios();
FLD = { 'rpmRef','Target speed','rpm',1; 'ramp','Speed ramp','rpm/s',1; 'load','Load (x 3.18 Nm)','x',1; ...
        'Ipeak','I peak limit','A',1; 'Icont','I continuous','A',1; 'Kt','Torque constant Kt','Nm/A',1; ...
        'tstop','Stop time','s',1; 'soc0','Start SOC','%',100; 'rFac','Pack resistance factor','x',1; ...
        'ktFac','Magnet strength factor','x',1; 'sensOff','Speed sensor error','%',100; 'packAh','Pack capacity','Ah',1 };
nF = size(FLD,1);
H  = struct();
ax = gobjects(1,4);

fig = uifigure('Name','EV Digital Twin - fault scenarios','Position',[40 40 1440 880]);
g   = uigridlayout(fig,[1 2],'ColumnWidth',{340,'1x'},'Padding',8,'ColumnSpacing',10);

% ---------- left: parameters, scenario and buttons
lp   = uipanel(g,'Title','Parameters (defaults = parameter file)');
rowH = [repmat({26},1,nF), {26},{26},{22},{26},{30},{30},{30},{110}];
lg   = uigridlayout(lp,[numel(rowH) 2],'RowHeight',rowH,'ColumnWidth',{'1.6x','1x'},'Padding',8,'RowSpacing',4);
for k = 1:nF
    place(uilabel(lg,'Text',sprintf('%s [%s]',FLD{k,2},FLD{k,3})),k,1);
    H.(FLD{k,1}) = uieditfield(lg,'numeric','Value',DEF.(FLD{k,1})*FLD{k,4});
    place(H.(FLD{k,1}),k,2);
end
r0 = nF;
H.limiter = uicheckbox(lg,'Text','Current limiter active','Value',DEF.limiter);
place(H.limiter,r0+1,[1 2]);
H.protect = uicheckbox(lg,'Text','Protection and BMS active (prevention)','Value',DEF.protect);
place(H.protect,r0+2,[1 2]);
place(uilabel(lg,'Text','Scenario'),r0+3,[1 2]);
H.scn = uidropdown(lg,'Items',{SC.name},'ItemsData',num2cell(1:numel(SC)),'Value',1);
place(H.scn,r0+4,[1 2]);
place(uibutton(lg,'Text','Run','ButtonPushedFcn',@onRun,'BackgroundColor',[0.2 0.45 1],'FontColor',[1 1 1]),r0+5,1);
place(uibutton(lg,'Text','Compare OFF / ON','ButtonPushedFcn',@onCompare),r0+5,2);
place(uibutton(lg,'Text','Apply scenario','ButtonPushedFcn',@onApply),r0+6,1);
place(uibutton(lg,'Text','Reset to defaults','ButtonPushedFcn',@onReset,'BackgroundColor',[0.9 0.6 0.2]),r0+6,2);
place(uibutton(lg,'Text','Scan all scenarios (OFF and ON)','ButtonPushedFcn',@onScan),r0+7,[1 2]);
H.outcome = uilabel(lg,'Text','Ready. Press Run.','WordWrap','on','FontWeight','bold','FontSize',13);
place(H.outcome,r0+8,[1 2]);

% ---------- right: four plots and a tab group
rp = uipanel(g,'BorderType','none');
rg = uigridlayout(rp,[3 2],'RowHeight',{'1x','1x','1.3x'},'ColumnWidth',{'1x','1x'},'Padding',0,'RowSpacing',8,'ColumnSpacing',8);
titles = {'Speed [rpm]','Motor current, filtered [A]','Battery voltage [V]','Projected temperature [deg C]'};
for a = 1:4
    ax(a) = uiaxes(rg);
    ax(a).Layout.Row = ceil(a/2); ax(a).Layout.Column = mod(a-1,2)+1;
    title(ax(a),titles{a}); grid(ax(a),'on'); box(ax(a),'on'); xlabel(ax(a),'Time [s]');
end
tg   = uitabgroup(rg); tg.Layout.Row = 3; tg.Layout.Column = [1 2];
tTL  = uitab(tg,'Title','Incident timeline');
tCA  = uitab(tg,'Title','Calculation');
tPR  = uitab(tg,'Title','Prevention and help');
tCM  = uitab(tg,'Title','Protection OFF vs ON');
tRL  = uitab(tg,'Title','Run logs');
taTL = uitextarea(uigridlayout(tTL,[1 1]),'Editable','off','FontName','Consolas');
taCA = uitextarea(uigridlayout(tCA,[1 1]),'Editable','off','FontName','Consolas');
taPR = uitextarea(uigridlayout(tPR,[1 1]),'Editable','off');
taCM = uitextarea(uigridlayout(tCM,[1 1]),'Editable','off','FontName','Consolas');

% Run logs UI
gRL  = uigridlayout(tRL,[2 2],'RowHeight',{32,'1x'},'ColumnWidth',{'1.1x','1x'},'Padding',6,'RowSpacing',6,'ColumnSpacing',6);
ddRun = uidropdown(gRL,'Items',{'Choose a run...'},'ValueChangedFcn',@onPickRun);
ddRun.Layout.Row = 1; ddRun.Layout.Column = 1;
btnRef = uibutton(gRL,'Text','Refresh list','ButtonPushedFcn',@(~,~) refreshRunList(ddRun, pwd));
btnRef.Layout.Row = 1; btnRef.Layout.Column = 2;
taLog = uitextarea(gRL,'Editable','off','FontName','Consolas');
taLog.Layout.Row = 2; taLog.Layout.Column = 1;

gAxRL = uigridlayout(gRL,[2 2],'RowHeight',{'1x','1x'},'ColumnWidth',{'1x','1x'},'Padding',0,'RowSpacing',4,'ColumnSpacing',4);
gAxRL.Layout.Row = 2; gAxRL.Layout.Column = 2;
axRL  = gobjects(1,4);
colTitles = {'RPM','MotorCurrent','BatteryVoltage','BatteryCurrent'};
for iax = 1:4
    axRL(iax) = uiaxes(gAxRL);
    axRL(iax).Layout.Row = ceil(iax/2); axRL(iax).Layout.Column = mod(iax-1,2)+1;
    title(axRL(iax), colTitles{iax}); grid(axRL(iax),'on'); box(axRL(iax),'on'); xlabel(axRL(iax),'Time [s]');
end

refreshRunList(ddRun, pwd);
tg.SelectionChangedFcn = @onTabChanged;

%% ---------------- nested callbacks ----------------
    function p = readP()
        p = DEF;
        for idx = 1:nF
            p.(FLD{idx,1}) = H.(FLD{idx,1}).Value / FLD{idx,4};
        end
        p.limiter = logical(H.limiter.Value);
        p.protect = logical(H.protect.Value);
    end

    function writeP(p)
        for idx = 1:nF
            H.(FLD{idx,1}).Value = p.(FLD{idx,1}) * FLD{idx,4};
        end
        H.limiter.Value = p.limiter;
        H.protect.Value = p.protect;
    end

    function r = prep(r, s)
        r.name = s.name; r.id = s.id; r.cause = s.cause; r.help = s.help;
    end

    function onRun(~,~)
        s = SC(H.scn.Value);
        r = prep(evSim(readP()), s);
        drawRuns({r},{'this run'});
        showRun(r);
    end

    function onCompare(~,~)
        s = SC(H.scn.Value); p = readP();
        p.protect = false; rOff = prep(evSim(p), s); rOff.name = [s.name ' - protection OFF'];
        p.protect = true;  rOn  = prep(evSim(p), s); rOn.name  = [s.name ' - protection ON'];
        drawRuns({rOff,rOn},{'OFF','ON'});
        showRun(rOn);
        taCM.Value = compareText({rOff,rOn});
    end

    function onApply(~,~)
        s = SC(H.scn.Value);
        p = mergeP(DEF, s.p);
        p.protect = logical(H.protect.Value);
        writeP(p);
    end

    function onReset(~,~)
        writeP(DEF);
        H.scn.Value = 1;
        H.outcome.Text = 'Defaults restored: baseline (healthy system).';
        H.outcome.FontColor = [0 0 0];
    end

    function onScan(~,~)
        L = {sprintf('%-40s %-16s %-16s','Scenario','Protection OFF','Protection ON')};
        for s = 1:numel(SC)
            pOff = mergeP(DEF, SC(s).p); pOff.protect = false;
            pOn  = mergeP(DEF, SC(s).p); pOn.protect  = true;
            rA = evSim(pOff); rB = evSim(pOn);
            L{end+1} = sprintf('%-40.40s %-16s %-16s', SC(s).name, rA.outcome, rB.outcome); %#ok<AGROW>
            L{end+1} = sprintf('     OFF: peak I %.1f A, min V %.2f V, motor %.0f C, speed end %.0f rpm', rA.sum.Ipk, rA.sum.Vmin, rA.sum.Tmax, rA.sum.finalRpm); %#ok<AGROW>
            L{end+1} = sprintf('     ON : peak I %.1f A, min V %.2f V, motor %.0f C, speed end %.0f rpm', rB.sum.Ipk, rB.sum.Vmin, rB.sum.Tmax, rB.sum.finalRpm); %#ok<AGROW>
        end
        taCM.Value = L;
    end

    function showRun(r)
        H.outcome.Text = sprintf('%s:  %s', r.name, r.outcome);
        H.outcome.FontColor = outColor(r.outcome);
        taTL.Value = timelineText(r);
        taCA.Value = explainRun(r);
        taPR.Value = helpText(r);
    end

    function drawRuns(runs, names)
        for ia = 1:4
            cla(ax(ia)); hold(ax(ia),'on');
        end
        cols = {[0 0.447 0.741],[0.85 0.325 0.098]};
        for q = 1:numel(runs)
            r = runs{q}; c = cols{min(q,2)};
            if q == 1, ls = '-'; else, ls = '--'; end
            plot(ax(1), r.t, r.d.rpm, ls, 'Color',c, 'LineWidth',1.5, 'DisplayName',['true speed, ' names{q}]);
            plot(ax(2), r.t, r.d.i,   ls, 'Color',c, 'LineWidth',1.5);
            plot(ax(3), r.t, r.d.vb,  ls, 'Color',c, 'LineWidth',1.5);
            plot(ax(4), r.t, r.d.tm,  ls, 'Color',c, 'LineWidth',1.5, 'DisplayName',['motor, ' names{q}]);
            plot(ax(4), r.t, r.d.tb,  ':', 'Color',c, 'LineWidth',1.2, 'DisplayName',['battery, ' names{q}]);
        end
        r1 = runs{1};
        plot(ax(1), r1.t, r1.d.ref, 'k:', 'LineWidth',1, 'DisplayName','target');
        yline(ax(2), r1.p.Icont, '--', 'Icont');
        yline(ax(2), r1.p.Ipeak, 'r--', 'Ipeak');
        yline(ax(3), 45.4, 'r--', '45.4 V');
        yline(ax(3), 46, '--', '46 V');
        yline(ax(4), 120, 'r--', '120 C');
        yline(ax(4), 60, '--', '60 C');
        legend(ax(1),'show','Location','southeast');
        legend(ax(4),'show','Location','northwest');
    end

    function onTabChanged(~, event)
        if strcmp(event.NewValue.Title, 'Run logs')
            refreshRunList(ddRun, pwd);
            if ~isempty(ddRun.Value)
                showRunLog(ddRun.Value, taLog, axRL);
            end
        end
    end

    function onPickRun(~,~)
        if ~isempty(ddRun.Value)
            showRunLog(ddRun.Value, taLog, axRL);
        end
    end

    if nargout > 0
        varargout{1} = fig;
    end

end  % EV_Twin_App

%% =====================================================================
%  local functions
%% =====================================================================
function place(h, r, c)
h.Layout.Row = r; h.Layout.Column = c;
end

function DEF = evDefaults()
DEF = struct('rpmRef',2950,'ramp',13000,'load',1,'Ipeak',45,'Icont',30,'Kt',0.107,'tstop',0.3, ...
    'soc0',1,'rFac',1,'ktFac',1,'sensOff',0,'packAh',50,'limiter',true,'protect',true);
end

function p = mergeP(base, delta)
p = base; fn = fieldnames(delta);
for k = 1:numel(fn), p.(fn{k}) = delta.(fn{k}); end
end

function SC = evScenarios()
mk = @(id,name,p,cause,help) struct('id',id,'name',name,'p',p,'cause',cause,'help',{help});
SC = [ ...
 mk('nom','Baseline - healthy system', struct(), ...
    'No fault. Parameter-file values (the reference run).', ...
    {'Keep the monthly check of pack resistance, speed sensor and torque per amp.', ...
     'Use this run as the reference for every other scenario.'}), ...
 mk('ovl','Overload - hill climb at 1.8 x load', struct('load',1.8), ...
    'The vehicle demands 5.7 Nm instead of 3.18 Nm.', ...
    {'The current limiter (I peak 45 A) holds the motor: the rider loses speed instead of the motor overheating.', ...
     'Warn the driver when the current stays above I continuous for more than 1 s.', ...
     'Power map: lower the maximum load in the controller for steep climbs.'}), ...
 mk('aged','Aged battery - pack resistance x4', struct('rFac',4), ...
    'Cell ageing or a loose busbar: the internal resistance rises.', ...
    {'BMS resistance trend: alarm when pack resistance is above twice its new value.', ...
     'Battery over-temperature derate (projected 60 C) limits the current before the cells are damaged.', ...
     'Service: check busbars and connectors, replace the weak module.'}), ...
 mk('lowsoc','Low charge - start SOC 8 %', struct('soc0',0.08), ...
    'The pack was not charged; its voltage is close to the 45.4 V minimum.', ...
    {'Undervoltage cut-off at 46 V: derate the drive before the pack reaches its minimum.', ...
     'Charge warning below 15 % SOC.', ...
     'Limp-home mode keeps the vehicle moving at low power instead of stopping suddenly.'}), ...
 mk('demag','Magnet weakening - Kt -30 %', struct('ktFac',0.7), ...
    'Overheating or ageing weakens the permanent magnets.', ...
    {'Torque-per-amp monitor: the back-EMF gives Kt; alarm at 10 % deviation.', ...
     'Service: magnet check. The motor now needs more current for the same torque.', ...
     'Keep motor temperature limits so the magnets are not overheated.'}), ...
 mk('sens','Speed sensor drift +8 %', struct('sensOff',0.08), ...
    'Hall or encoder drift: the sensor reads 8 % high, so the controller under-drives the motor.', ...
    {'Plausibility check: sensor speed against the back-EMF estimate (threshold 6 %).', ...
     'Sensorless fallback: the controller uses the estimate, so the true speed stays at target.', ...
     'Driver warning: sensor fault, limp mode. Without this the dashboard shows the target as reached.'}), ...
 mk('lim','Current limiter failure', struct('limiter',false), ...
    'Software or PI limiter stops working: no current clamp.', ...
    {'Hardware over-current trip: 0.1 ms above 1.1 x I peak switches the inverter off. A software check at 5 ms is too slow.', ...
     'Self-test of the limiter at each start-up.', ...
     'Fuse or contactor in the DC link as the last barrier.'}), ...
 mk('combo','Combined - aged pack + overload', struct('rFac',4,'load',1.8), ...
    'Two faults at the same time: the realistic worst case on a hill.', ...
    {'Both protections act: battery derate for the pack, current limit for the motor.', ...
     'Vehicle goes to limp-home; the event is written to the Black Box.', ...
     'Do not drive on until the battery has been inspected.'}) ];
end

function r = evSim(p)
dt = 1e-5; N = round(p.tstop/dt); REC = 100;
Rw = 0.2; Lm = 2e-4; J = 0.002 + 0.5*1.5*0.0625/121; Kpw = 0.05; Kiw = 10; Vdc = 48;
IH = 120; Rth = 0.1; Rbth = 1.5;
Kt = p.Kt*p.ktFac; KtC = p.Kt; Rp = 0.011*p.rFac; Ah = p.packAh;
voc   = @(s) 45.4 + 9.1*s;
loadF = @(tt) p.load*3.18*min(max((tt-0.23)/0.05,0),1);
keys = {'rpm','ref','i','T','vb','ib','soc','vdc','ww','est','tm','tb'};
nR = floor(N/REC) + 1;
D = struct('t',zeros(nR,1));
for q = 1:numel(keys), D.(keys{q}) = zeros(nR,1); end
ev   = struct('t',{},'msg',{},'kind',{});
seen = containers.Map('KeyType','char','ValueType','logical');
w=0; i=0; ig=0; soc=p.soc0; ib=0; ibF=0; vb=voc(p.soc0); If=0; vc=0; west=0;
uvT=0; ocT=0; sensT=0; ktT=0; fb=false; derate=false; trip=false;
tmax=0; tbmax=0; Vmin=1e9; Tm=25; Tb=25; qi=0;
for k = 0:N
    tt = k*dt; rpm = w*60/(2*pi); meas = rpm*(1+p.sensOff);
    refR = min(p.rpmRef, p.ramp*tt);
    west = west + ((vc - Rw*If)/KtC - west)*dt/2e-3;
    est  = west*60/(2*pi);
    if p.protect && ~fb && tt > 0.1
        if abs(meas-est) > 0.06*max(est,500)
            sensT = sensT + dt;
            if sensT > 0.02
                [ev,seen] = addEv(ev,seen,tt,'Speed sensor and back-EMF estimate differ by more than 6 %','warn');
                fb = true;
                [ev,seen] = addEv(ev,seen,tt,'Sensorless fallback: controller uses the back-EMF estimate','act');
            end
        else
            sensT = 0;
        end
    end
    if tt > 0.15 && w > 200
        ktE = (vc - Rw*If)/w;
        if abs(ktE-KtC)/KtC > 0.1
            ktT = ktT + dt;
            if ktT > 0.02
                [ev,seen] = addEv(ev,seen,tt,'Torque-per-amp check: back-EMF gives Kt more than 10 % off the datasheet','warn');
            end
        else
            ktT = 0;
        end
    end
    if vb < 46
        uvT = uvT + dt;
        if uvT > 0.01 && p.protect && ~derate
            derate = true;
            [ev,seen] = addEv(ev,seen,tt,'BMS undervoltage cut-off: pack below 46 V, drive derated to 50 % current','act');
        end
    else
        uvT = 0;
    end
    if vb < 45.4
        [ev,seen] = addEv(ev,seen,tt,'Battery below 45.4 V minimum: deep-discharge damage risk','fail');
    end
    Tm = 25 + Rth*1.5*If*If*Rw;
    Tb = 25 + Rbth*ibF*ibF*Rp;
    tmax = max(tmax,Tm); tbmax = max(tbmax,Tb); Vmin = min(Vmin,vb);
    if (Tm > 120 || Tb > 60) && p.protect && ~derate
        derate = true;
        [ev,seen] = addEv(ev,seen,tt,'Thermal protection: projected temperature above limit, drive derated to 50 % current','act');
    end
    if Tm > 120 && ~p.protect
        [ev,seen] = addEv(ev,seen,tt,'Motor projected above 120 C: winding and magnet damage','fail');
    end
    if Tb > 60 && ~p.protect
        [ev,seen] = addEv(ev,seen,tt,'Battery projected above 60 C: cell damage risk','fail');
    end
    Ilim = p.Ipeak; if derate, Ilim = 0.5*p.Icont; end
    if i > 1.1*p.Ipeak
        ocT = ocT + dt;
        if ~p.protect && ocT > 5e-3
            [ev,seen] = addEv(ev,seen,tt,'Over-current: motor current above 1.1 x I peak with no protection: inverter and winding stress','fail');
        end
        if p.protect && ~p.limiter && ocT > 1e-4 && ~trip
            trip = true;
            [ev,seen] = addEv(ev,seen,tt,'Hardware over-current trip (0.1 ms): drive switched off, safe state','act');
        end
    else
        ocT = 0;
    end
    ctrl = meas; if p.protect && fb, ctrl = est; end
    e  = refR - ctrl;
    ig = min(max(ig + Kiw*e*dt,0),Vdc);
    vc = min(max(Kpw*e + ig,0),Vdc);
    if p.limiter
        vmax = KtC*w + Rw*Ilim + 0.2*(Ilim - i);
        if vc > vmax, vc = max(vmax,0); end
    end
    if trip, vc = 0; end
    i = max(0, i + (vc - Kt*w - Rw*i)/Lm*dt);
    if ~p.limiter && i > IH
        i = IH;
        [ev,seen] = addEv(ev,seen,tt,'Hardware over-current: 120 A inverter limit reached, power devices at risk','fail');
    end
    w  = w + (Kt*i - loadF(tt) - 1e-4*w)*dt/J;
    If = If + (i - If)*dt/2e-3;
    ib = vc*i/(0.97*vb);
    ibF = ibF + (ib - ibF)*dt/5e-3;
    vb = voc(soc) - Rp*ib;
    soc = soc - ib*dt/(Ah*3600);
    if mod(k,REC) == 0
        qi = qi + 1;
        D.t(qi)=tt; D.rpm(qi)=rpm; D.ref(qi)=refR; D.i(qi)=If; D.T(qi)=Kt*If;
        D.vb(qi)=vb; D.ib(qi)=ib; D.soc(qi)=soc; D.vdc(qi)=vc; D.ww(qi)=w/11;
        D.est(qi)=est; D.tm(qi)=Tm; D.tb(qi)=Tb;
    end
end
hasF = any(strcmp({ev.kind},'fail'));
hasA = any(strcmp({ev.kind},'act'));
hasW = any(strcmp({ev.kind},'warn'));
hidden = p.sensOff ~= 0 && ~fb;
Ifin = D.i(end);
if hasF,        outc = 'INCIDENT';
elseif hidden,  outc = 'HIDDEN FAULT';
elseif hasA,    outc = 'PREVENTED';
elseif hasW || Ifin > p.Icont || Vmin < 46 || tmax > 100, outc = 'WARNING';
else
    outc = 'NORMAL';
end

ILend = p.Ipeak; if derate, ILend = 0.5*p.Icont; end
S = struct('finalRpm',D.rpm(end),'refFinal',D.ref(end),'Ipk',max(D.i),'Ifin',Ifin, ...
    'Vb',D.vb(end),'Ib',D.ib(end),'Vmin',Vmin,'SOCdrop',D.soc(1)-D.soc(end), ...
    'Tmax',tmax,'Tbmax',tbmax,'Tload',loadF(p.tstop),'Ilim',ILend, ...
    'derate',derate,'trip',trip,'fb',fb);
r = struct('t',D.t,'d',D,'p',p,'ev',ev,'outcome',outc,'sum',S, ...
    'name','run','id','','cause','','help',{{}});
end

function [ev,seen] = addEv(ev,seen,tt,msg,kind)
if isKey(seen,msg), return; end
seen(msg) = true;
ev(end+1) = struct('t',round(tt,4),'msg',msg,'kind',kind);
end

function L = explainRun(r)
p = r.p; s = r.sum;
Kt = p.Kt*p.ktFac; Rp = 0.011*p.rFac; w = s.finalRpm*2*pi/60;
Pm = s.Tload*w; Pb = Pm/0.97; socE = r.d.soc(end);
Tme = 25 + 0.1*1.5*s.Ifin^2*0.2;
Tbe = 25 + 1.5*s.Ib^2*Rp;
L = {};
L{end+1} = sprintf('1. Load torque at end:      T = %g x 3.18 = %.2f Nm', p.load, s.Tload);
L{end+1} = sprintf('2. Torque constant in use:  Kt = %g x %g = %.4f Nm/A (datasheet %g)', p.Kt, p.ktFac, Kt, p.Kt);
L{end+1} = sprintf('3. Current needed:          I = T/Kt = %.2f / %.4f = %.1f A (limit now %g A)', s.Tload, Kt, s.Tload/Kt, s.Ilim);
L{end+1} = sprintf('4. Speed:                    true %.0f rpm, target %.0f rpm (%+.1f %%)', s.finalRpm, s.refFinal, 100*(s.finalRpm-s.refFinal)/s.refFinal);
L{end+1} = sprintf('5. Mechanical power:         P = T x w = %.2f x %.1f = %.2f kW', s.Tload, w, Pm/1000);
L{end+1} = sprintf('6. Battery power:            P_bat = P / 0.97 = %.2f kW', Pb/1000);
L{end+1} = sprintf('7. Battery current:          I_bat = P_bat / V_bat = %.0f / %.2f = %.1f A', Pb, s.Vb, s.Ib);
L{end+1} = sprintf('8. Pack voltage:             V_bat = (45.4 + 9.1 x SOC) - R_pack x I_bat = (45.4 + 9.1 x %.4f) - %.4f x %.1f = %.2f V', socE, Rp, s.Ib, s.Vb);
L{end+1} = sprintf('9. Charge used:              dSOC = integral(I_bat dt) / (3600 x %g Ah) = %.4f %% of capacity', p.packAh, 100*s.SOCdrop);
L{end+1} = sprintf('10. Motor temperature:       T_m = 25 + 0.1 x 1.5 x I^2 x 0.2 = %.0f C at end, peak %.0f C (limit 120 C)', Tme, s.Tmax);
L{end+1} = sprintf('11. Battery temperature:     T_b = 25 + 1.5 x I_bat^2 x R_pack = %.0f C at end, peak %.0f C (limit 60 C)', Tbe, s.Tbmax);
L{end+1} = sprintf('12. Protection state:        limiter %s, protection %s, derate %s, trip %s, sensor fallback %s', ...
    onoff(p.limiter), onoff(p.protect), yn(s.derate), yn(s.trip), yn(s.fb));
end

function L = timelineText(r)
if isempty(r.ev)
    L = {'No events. All monitored limits held.'};
    return
end
L = cell(numel(r.ev),1);
for q = 1:numel(r.ev)
    e = r.ev(q);
    switch e.kind
        case 'fail', tag = 'FAIL  ';
        case 'act',  tag = 'ACTION';
        otherwise,   tag = 'WARN  ';
    end
    L{q} = sprintf('%7.3f s  %s  %s', e.t, tag, e.msg);
end
end

function L = helpText(r)
L = {sprintf('Scenario: %s', r.name), ['Cause: ' r.cause], '', 'What helps (prevention and service):'};
for q = 1:numel(r.help)
    L{end+1} = ['  - ' r.help{q}]; %#ok<AGROW>
end
L{end+1} = '';
L{end+1} = sprintf('Protection switch: %s. Outcome: %s.', onoff(r.p.protect), r.outcome);
end

function L = compareText(runs)
L = {sprintf('%-30s %-14s %9s %9s %10s %10s','Run','Outcome','Peak I A','Min V','Motor C','Speed rpm')};
for q = 1:numel(runs)
    r = runs{q};
    L{end+1} = sprintf('%-30.30s %-14s %9.1f %9.2f %10.0f %10.0f', r.name, r.outcome, r.sum.Ipk, r.sum.Vmin, r.sum.Tmax, r.sum.finalRpm); %#ok<AGROW>
end
L{end+1} = '';
for q = 1:numel(runs)
    r = runs{q};
    L{end+1} = sprintf('%s - timeline:', r.name); %#ok<AGROW>
    tl = timelineText(r);
    for z = 1:numel(tl)
        L{end+1} = ['   ' tl{z}]; %#ok<AGROW>
    end
end
end

function c = outColor(o)
switch o
    case {'INCIDENT','HIDDEN FAULT'}, c = [0.85 0.1 0.1];
    case 'WARNING',                   c = [0.8 0.5 0];
    otherwise,                        c = [0 0.5 0.2];
end
end

function s = onoff(x)
if x, s = 'on'; else, s = 'OFF'; end
end

function s = yn(x)
if x, s = 'yes'; else, s = 'no'; end
end

function refreshRunList(ddown, root)
d = dir(fullfile(root,'Simulation Logs','EV_RUN_*'));
d = d([d.isdir]);
if isempty(d)
    ddown.Items = {'(no runs yet)'};
    ddown.ItemsData = {''};
    return;
end
[~,ix] = sort(string({d.name}),'descend');
d = d(ix);
items = cell(numel(d),1);
for kDir = 1:numel(d)
    tok = regexp(d(kDir).name,'EV_RUN_(\d{8})_(\d{6})','tokens','once');
    when = d(kDir).name;
    if ~isempty(tok)
        when = datestr(datenum([tok{1} tok{2}],'yyyymmddHHMMSS'),'dd-mmm-yyyy HH:MM:SS');
    end
    items{kDir} = [when '   |   ' d(kDir).name];
end
ddown.Items = items;
ddown.ItemsData = fullfile(root,'Simulation Logs',{d.name});
end

function showRunLog(runDir, taLog, axs)
% command log and cleaned data of one archived run
if isempty(runDir) || ~isfolder(runDir), return, end
logF = fullfile(runDir,'10_Command_Log.txt');
if isfile(logF)
    taLog.Value = splitlines(fileread(logF));
else
    taLog.Value = {'no command log in this run'};
end
cF = fullfile(runDir,'03_Cleaned_Data.xlsx');
if ~isfile(cF), return, end
try
    T = readtable(cF,'Sheet','Cleaned_Data');
    cols = {'RPM','MotorCurrent','BatteryVoltage','BatteryCurrent'};
    for aAx = 1:4
        cla(axs(aAx)); plot(axs(aAx), T.Time, T.(cols{aAx}), 'LineWidth',1.2);
        title(axs(aAx), cols{aAx}, 'Interpreter','none'); grid(axs(aAx),'on'); xlabel(axs(aAx),'Time [s]');
    end
catch
end
end
