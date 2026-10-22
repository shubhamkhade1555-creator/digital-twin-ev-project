function out=EV_Graphs(action,varargin)
%EV_GRAPHS Single graph pipeline: normal Battery/Motor plots + N4SID validation.
% EV_Graphs('generate',Clean,runDir,P) is called automatically from the DAQ StopFcn.
% EV_Graphs('run',seconds) starts a manual simulation; EV_Graphs('help') lists options.
% PASS/FAIL verdicts are deliberately excluded from figures; keep them in text/CSV reports.
if nargin<1||isempty(action),action='generate';end
action=lower(char(action));out=struct('status','not-started','files',{{}},'warnings',{{}},'runDir','');
switch action
case 'help'
 fprintf('EV_Graphs manual options:\n EV_Graphs(''run'',0.1)\n EV_Graphs(''run'',0.2)\n EV_Graphs(''run'',0.4)\n EV_Graphs(''run'',0.5)\n EV_Graphs(''generate'')\n');return
case 'run'
 if isempty(varargin)||~isnumeric(varargin{1})||~isscalar(varargin{1})||~isfinite(varargin{1})||varargin{1}<=0,error('Use EV_Graphs(''run'',positive_seconds).');end
 mdl='BLDCSpeedControl_EV_Layout_v2';root=fileparts(mfilename('fullpath'));addpath(root);
 if ~bdIsLoaded(mdl),load_system(fullfile(root,[mdl '.slx']));end
 if ~strcmpi(get_param(mdl,'SimulationStatus'),'stopped'),error('Stop the current simulation first.');end
 set_param(mdl,'StopTime',sprintf('%.10g',varargin{1}));assignin('base','t_stop',varargin{1});
 fprintf('[EV_Graphs] Starting %.4f s manual test; StopFcn will generate plots.\n',varargin{1});
 set_param(mdl,'SimulationCommand','start');out.status='simulation-started';return
case 'generate'
 C=[];runDir='';P=struct();if numel(varargin)>=1,C=varargin{1};end;if numel(varargin)>=2,runDir=varargin{2};end;if numel(varargin)>=3&&isstruct(varargin{3}),P=varargin{3};end %#ok<NASGU>
 if isempty(C),try,C=evalin('base','EV_DAQ_Clean');catch,end,end
 if isempty(runDir),try,runDir=evalin('base','EV_DAQ_RunDir');catch,end,end
 if isempty(runDir),runDir=fullfile(fileparts(mfilename('fullpath')),'Simulation Logs','EV_RUN_manual');end
 runDir=char(runDir);out.runDir=runDir;
 if ~istable(C)||height(C)<2,out.status='skipped-no-data';out.warnings={'EV_DAQ_Clean missing or too short'};try,assignin('base','EV_Graphs_Result',out);catch,end;return,end
 if ~isfolder(runDir),mkdir(runDir);end;root=fullfile(runDir,'Figures');groups={'Battery','Motor','N4SID_Battery','N4SID_Motor'};
 for k=1:numel(groups),if ~isfolder(fullfile(root,groups{k})),mkdir(fullfile(root,groups{k}));end,end
 t=col(C,{'Time'});if isempty(t),t=(0:height(C)-1)'*1e-3;end;t=t(:);
 % Category 1: normal battery plots
 out=single(C,t,root,'Battery',out,{'BatteryVoltage','Vbatt_V'},'Battery pack voltage','Voltage (V)','B01_Battery_Voltage');
 out=single(C,t,root,'Battery',out,{'BatteryCurrent','Ibatt_A'},'Battery pack current','Current (A)','B02_Battery_Current');
 out=single(C,t,root,'Battery',out,{'SOC','StateOfCharge'},'Battery state of charge','SOC (logged units)','B03_Battery_SOC');
 out=single(C,t,root,'Battery',out,{'BatteryTemperature','Tbatt_C','Temperature'},'Battery temperature','Temperature (degC)','B04_Battery_Temperature');
 out=single(C,t,root,'Battery',out,{'BatteryTemperatureMax'},'Maximum battery cell temperature','Temperature (degC)','B08_Battery_Temperature_Max');
 vn=C.Properties.VariableNames;ix=find(contains(vn,'CellVoltage','IgnoreCase',true)|contains(vn,'Cell_Voltage','IgnoreCase',true)|contains(vn,'Vcell_','IgnoreCase',true));
 if ~isempty(ix),out=multi(C,t,root,out,ix,'Battery','Cell/group voltages','Voltage (V)','B05_Cell_Voltage');else,out.warnings{end+1}='Cell voltage: no cell-level columns logged';end
 V=col(C,{'BatteryVoltage','Vbatt_V'});I=col(C,{'BatteryCurrent','Ibatt_A'});if ~isempty(V)&&~isempty(I),out=draw(t,V(:).*I(:),root,'Battery','Battery power','Power (W)','B06_Battery_Power',out);out=batteryMonitor(t,V,I,root,out);end
 % Category 2: normal motor plots
 out=pair(C,t,root,out,{'RPMReference','RPM_Reference','rpm_ref'},{'RPM','MotorRPM','RPM_rpm'},'Motor RPM reference vs actual','Motor','Speed (rpm)','M01_RPM_Tracking');
 out=single(C,t,root,'Motor',out,{'MotorCurrent','Idc_f_A'},'Motor current (logged signal)','Current (A)','M02_Motor_Current');
 out=single(C,t,root,'Motor',out,{'MotorTemperature','Tmotor_C'},'Motor housing temperature','Temperature (degC)','M12_Motor_Temperature');
 out=motorCurrentLimits(C,t,root,out,P);
 out=single(C,t,root,'Motor',out,{'MotorTorque','Torque_Nm','Torque','Tq_meas'},'Motor torque','Torque (N m)','M03_Motor_Torque');
 out=single(C,t,root,'Motor',out,{'DCLinkVoltage','Vdc_m_V','Vdc'},'DC-link voltage','Voltage (V)','M04_DC_Link_Voltage');
 out=single(C,t,root,'Motor',out,{'MotorTerminalVoltage','MotorVoltage'},'Motor terminal voltage','Voltage (V)','M05_Motor_Terminal_Voltage');
 phases={{'PhaseAVoltage','Va','V_phase_A'},{'PhaseBVoltage','Vb','V_phase_B'},{'PhaseCVoltage','Vc','V_phase_C'}};
 for k=1:3,out=single(C,t,root,'Motor',out,phases{k},sprintf('Motor phase %c voltage','A'+k-1),'Voltage (V)',sprintf('M0%d_Phase_%c',5+k,'A'+k-1));end
 out=single(C,t,root,'Motor',out,{'LineVoltageAB','Vab','V_A_B'},'Line voltage A-B','Voltage (V)','M09_Line_Voltage_AB');
 out=torqueLoad(C,t,root,out);
 Pm=col(C,{'MotorMechanicalPower'});if isempty(Pm),Tq=col(C,{'MotorTorque','Torque_Nm','Tq_meas'});rpm=col(C,{'RPM','MotorRPM'});if ~isempty(Tq)&&~isempty(rpm),Pm=abs(Tq(:).*rpm(:)*2*pi/60);end,end
 if ~isempty(Pm),out=draw(t,Pm,root,'Motor','Motor mechanical power','Power (W)','M10_Motor_Mechanical_Power',out);end
 out=batteryID(runDir,root,out);out=motorID(C,t,runDir,root,out);
 try,f=fopen(fullfile(root,'Graph_Inventory.txt'),'w');fprintf(f,'EV Digital Twin graph inventory\n%s\n',char(datetime('now')));for k=1:numel(out.files),fprintf(f,'%s\n',out.files{k});end;fprintf(f,'\nSkipped/unavailable:\n');for k=1:numel(out.warnings),fprintf(f,'- %s\n',out.warnings{k});end;fclose(f);catch,end
 out.status='complete';try,assignin('base','EV_Graphs_Result',out);catch,end
 fprintf('[EV_Graphs] Saved %d PNG graph files to %s. Figures contain no PASS/FAIL verdicts.\n',numel(out.files),root);
otherwise,error('Unknown action. Use EV_Graphs(''help'').');
end
end
function y=col(T,n)
y=[];v=T.Properties.VariableNames;for k=1:numel(n),i=find(strcmpi(v,n{k}),1);if ~isempty(i),y=T{:,i};break,end,end
if isempty(y),for k=1:numel(n),i=find(contains(v,n{k},'IgnoreCase',true),1);if ~isempty(i),y=T{:,i};break,end,end,end
if ~isempty(y),y=double(y);if ~isvector(y),y=mean(y,2,'omitnan');end;y=y(:);end
end
function out=single(T,t,r,g,out,a,ttl,ylab,nm),y=col(T,a);if isempty(y),out.warnings{end+1}=[nm ': signal unavailable'];return,end;out=draw(t,y,r,g,ttl,ylab,nm,out);end
function out=draw(t,y,r,g,ttl,ylab,nm,out)
n=min(numel(t),numel(y));t=t(1:n);y=y(1:n);q=isfinite(t)&isfinite(y);t=t(q);y=y(q);if numel(t)<2,out.warnings{end+1}=[nm ': too few finite samples'];return,end
f=figure('Visible','off','Color','w','Position',[100 100 1400 820]);a=axes(f);plot(a,t,y,'LineWidth',1.8);grid(a,'on');box(a,'on');xlabel(a,'Time (s)');ylabel(a,ylab);title(a,ttl,'FontWeight','bold');set(a,'FontName','Arial','FontSize',12);out=saveFig(f,r,g,nm,out);
end
function out=pair(T,t,r,out,a1,a2,ttl,g,ylab,nm)
x=col(T,a1);y=col(T,a2);if isempty(x)||isempty(y),out.warnings{end+1}=[nm ': reference/actual signal unavailable'];return,end
n=min([numel(t),numel(x),numel(y)]);f=figure('Visible','off','Color','w','Position',[100 100 1400 820]);a=axes(f);plot(a,t(1:n),x(1:n),'LineWidth',1.8);hold(a,'on');plot(a,t(1:n),y(1:n),'--','LineWidth',1.8);grid(a,'on');xlabel(a,'Time (s)');ylabel(a,ylab);title(a,ttl,'FontWeight','bold');legend(a,{'Reference','Actual'},'Location','best');out=saveFig(f,r,g,nm,out);
end
function out=multi(T,t,r,out,ix,g,ttl,ylab,nm)
f=figure('Visible','off','Color','w','Position',[100 100 1400 820]);a=axes(f);plot(a,t,T{:,ix},'LineWidth',1.2);grid(a,'on');xlabel(a,'Time (s)');ylabel(a,ylab);title(a,ttl,'FontWeight','bold');legend(a,T.Properties.VariableNames(ix),'Interpreter','none','Location','eastoutside');out=saveFig(f,r,g,nm,out);
end
function out=batteryMonitor(t,V,I,r,out)
n=min([numel(t),numel(V),numel(I)]);f=figure('Visible','off','Color','w','Position',[100 100 1400 820]);a=axes(f);
yyaxis(a,'left');plot(a,t(1:n),V(1:n),'LineWidth',1.8);ylabel(a,'Battery voltage (V)');
yyaxis(a,'right');plot(a,t(1:n),I(1:n),'LineWidth',1.8);ylabel(a,'Battery current (A)');
grid(a,'on');xlabel(a,'Time (s)');title(a,'Battery voltage and current monitoring','FontWeight','bold');
out=saveFig(f,r,'Battery','B07_Battery_Monitoring',out);
end
function out=motorCurrentLimits(T,t,r,out,P)
I=col(T,{'MotorCurrent','Idc_f_A'});if isempty(I),return,end
if ~isfield(P,'I_cont'),try,P.I_cont=evalin('base','I_cont');catch,end,end
if ~isfield(P,'I_peak'),try,P.I_peak=evalin('base','I_peak');catch,end,end
n=min(numel(t),numel(I));f=figure('Visible','off','Color','w','Position',[100 100 1400 820]);a=axes(f);
plot(a,t(1:n),I(1:n),'LineWidth',1.7,'DisplayName','Logged motor current');hold(a,'on');
if isfield(P,'I_cont')&&isnumeric(P.I_cont)&&isscalar(P.I_cont)&&isfinite(P.I_cont),yline(a,P.I_cont,'--','Continuous limit');yline(a,-P.I_cont,'--','HandleVisibility','off');end
if isfield(P,'I_peak')&&isnumeric(P.I_peak)&&isscalar(P.I_peak)&&isfinite(P.I_peak),yline(a,P.I_peak,':','Peak limit');yline(a,-P.I_peak,':','HandleVisibility','off');end
grid(a,'on');xlabel(a,'Time (s)');ylabel(a,'Current (A)');title(a,'Motor current and configured limits','FontWeight','bold');legend(a,'Location','best');
out=saveFig(f,r,'Motor','M02b_Motor_Current_Limits',out);
end
function out=torqueLoad(T,t,r,out)
a=col(T,{'MotorTorque','Torque_Nm','Torque','Tq_meas'});b=col(T,{'LoadTorque','TorqueReference','LoadTorqueReference','LoadTorqueRef'});
if isempty(a)||isempty(b),out.warnings{end+1}='Motor torque/load comparison: load torque reference not logged';return,end
n=min([numel(t),numel(a),numel(b)]);f=figure('Visible','off','Color','w','Position',[100 100 1400 820]);ax=axes(f);
plot(ax,t(1:n),a(1:n),'LineWidth',1.8,'DisplayName','Motor torque');hold(ax,'on');plot(ax,t(1:n),b(1:n),'--','LineWidth',1.8,'DisplayName','Load/reference torque');
grid(ax,'on');xlabel(ax,'Time (s)');ylabel(ax,'Torque (N m)');title(ax,'Motor torque vs load/reference torque','FontWeight','bold');legend(ax,'Location','best');
out=saveFig(f,r,'Motor','M11_Torque_Load_Comparison',out);
end
function out=batteryID(runDir,r,out)
f=fullfile(runDir,'EV_BlackBox_SysID.mat');if ~isfile(f),out.warnings{end+1}='Battery N4SID: run-specific model/validation data unavailable';return,end
S=load(f);if ~all(isfield(S,{'sys_blackbox','Zv','Ys','Y0'})),out.warnings{end+1}='Battery N4SID: saved model missing validation fields';return,end
try
 [p1,fit1]=compare(S.Zv,S.sys_blackbox,1);[pf,fitf]=compare(S.Zv,S.sys_blackbox,Inf);y=S.Zv.OutputData.*S.Ys+S.Y0;y1=p1.OutputData.*S.Ys+S.Y0;yf=pf.OutputData.*S.Ys+S.Y0;
 tt=S.Zv.SamplingInstants;if isempty(tt),tt=(0:size(y,1)-1)'*S.Zv.Ts;end;tt=tt(:);if isfield(S,'Ze')&&~isempty(tt)&&tt(1)<S.Zv.Ts,tt=tt+size(S.Ze.OutputData,1)*S.Zv.Ts;end;nm={'Battery voltage','Battery current'};un={'V','A'};
 for k=1:min(2,size(y,2))
  out=three(tt,y(:,k),y1(:,k),yf(:,k),r,'N4SID_Battery',[nm{k} ' measured vs N4SID predictions'],sprintf('S%d_Compare',k),un{k},out);
  e=y(:,k)-yf(:,k);out=draw(tt,e,r,'N4SID_Battery',[nm{k} ' free-run residual'],['Residual (' un{k} ')'],sprintf('S%d_Residuals',k+2),out);
  out=parity(y(:,k),yf(:,k),r,'N4SID_Battery',[nm{k} ' validation parity'],sprintf('S%d_Parity',k+4),un{k},out);
  out=inputCorr(e,S.Zv.InputData,r,'N4SID_Battery',[nm{k} ' residual-input correlation'],sprintf('S%d_Residual_Input_Correlation',k),out);
  if numel(e)>=10,[ac,lags]=xcorr(e-mean(e),min(40,floor(numel(e)/4)),'coeff');ff=figure('Visible','off','Color','w');aa=axes(ff);stem(aa,lags,ac,'filled');grid(aa,'on');xlabel(aa,'Lag (samples)');ylabel(aa,'Autocorrelation');title(aa,[nm{k} ' residual autocorrelation']);out=saveFig(ff,r,'N4SID_Battery',sprintf('S%d_Residual_Autocorrelation',k),out);end
 end
 if isfield(S,'sweep')&&size(S.sweep,2)>=8,sw=S.sweep;ff=figure('Visible','off','Color','w');aa=axes(ff);plot(aa,sw(:,1),sw(:,7),'o-','LineWidth',1.8);hold(aa,'on');plot(aa,sw(:,1),sw(:,8),'s-','LineWidth',1.8);grid(aa,'on');xlabel(aa,'State order');ylabel(aa,'Free-run RMSE');title(aa,'Battery N4SID model-order comparison');legend(aa,{'Voltage RMSE (V)','Current RMSE (A)'});out=saveFig(ff,r,'N4SID_Battery','S05_Model_Order',out);end
 fprintf('[EV_Graphs] Battery N4SID fit one-step=%s; free-run=%s\n',mat2str(fit1,3),mat2str(fitf,3));
 out=fitPlot(fit1,fitf,r,'N4SID_Battery','Battery N4SID validation fit','S06_Validation_Fit',{'Voltage','Current'},out);
catch ME,out.warnings{end+1}=['Battery N4SID plot issue: ' ME.message];end
end
function out=motorID(T,t,runDir,r,out)
u1=col(T,{'RPMReference','RPM_Reference','rpm_ref'});u2=col(T,{'BatteryVoltage','Vbatt_V'});y1=col(T,{'RPM','MotorRPM','RPM_rpm'});y2=col(T,{'MotorCurrent','Idc_f_A'});y3=col(T,{'MotorTorque','Torque_Nm','Tq_meas'});
if isempty(u1)||isempty(u2)||isempty(y1)||isempty(y2)||isempty(y3),out.warnings{end+1}='Motor N4SID: required input/output channels missing';return,end
Y=[y1(:),y2(:),y3(:)];U=[u1(:),u2(:)];n=min([size(Y,1),size(U,1),numel(t)]);Y=Y(1:n,:);U=U(1:n,:);tt=t(1:n);ok=all(isfinite(Y),2)&all(isfinite(U),2)&isfinite(tt);Y=Y(ok,:);U=U(ok,:);tt=tt(ok);
if size(Y,1)<120||any(std(U,0,1)<1e-8)||any(std(Y,0,1)<1e-8),out.warnings{end+1}='Motor N4SID: insufficient samples/excitation; no predictions claimed';return,end
N=size(Y,1);Ne=floor(.7*N);Ts=median(diff(tt));if ~isfinite(Ts)||Ts<=0,Ts=1e-3;end;u0=mean(U(1:Ne,:),1);us=std(U(1:Ne,:),0,1);y0=mean(Y(1:Ne,:),1);ys=std(Y(1:Ne,:),0,1);us(us<1e-12)=1;ys(ys<1e-12)=1;
Un=(U-u0)./us;Yn=(Y-y0)./ys;Ze=iddata(Yn(1:Ne,:),Un(1:Ne,:),Ts);Zv=iddata(Yn(Ne+1:end,:),Un(Ne+1:end,:),Ts);best=[];bestScore=Inf;ord=0;sw=nan(6,4);
for nx=1:6,try,m=n4sid(Ze,nx,n4sidOptions('Focus','prediction','EstimateCovariance',false));[pp,~]=compare(Zv,m,1);yp=pp.OutputData.*ys+y0;er=Y(Ne+1:end,:)-yp;rm=sqrt(mean(er.^2,1));sw(nx,:)=[nx rm];sc=mean(rm./max(ys,1e-9));if isstable(m)&&isfinite(sc)&&sc<bestScore,best=m;bestScore=sc;ord=nx;end;catch,end,end
if isempty(best),out.warnings{end+1}='Motor N4SID: no stable candidate model';return,end
[p1,fit1]=compare(Zv,best,1);[pf,fitf]=compare(Zv,best,Inf);yt=Zv.OutputData.*ys+y0;a=p1.OutputData.*ys+y0;bb=pf.OutputData.*ys+y0;tv=tt(Ne+1:end);nm={'Motor RPM','Motor current','Motor torque'};un={'rpm','A','N m'};short={'RPM','Current','Torque'};
for k=1:3,out=three(tv,yt(:,k),a(:,k),bb(:,k),r,'N4SID_Motor',[nm{k} ' measured vs N4SID predictions'],sprintf('S%d_%s_Compare',10+k,short{k}),un{k},out);er=yt(:,k)-bb(:,k);out=draw(tv,er,r,'N4SID_Motor',[nm{k} ' free-run residual'],['Residual (' un{k} ')'],sprintf('S%d_%s_Residual',13+k,short{k}),out);out=parity(yt(:,k),bb(:,k),r,'N4SID_Motor',[nm{k} ' validation parity'],sprintf('S%d_%s_Parity',16+k,short{k}),un{k},out);out=inputCorr(er,Zv.InputData,r,'N4SID_Motor',[nm{k} ' residual-input correlation'],sprintf('S%d_%s_Residual_Input_Correlation',19+k,short{k}),out);end
ff=figure('Visible','off','Color','w');aa=axes(ff);plot(aa,sw(:,1),sw(:,2),'o-');hold(aa,'on');plot(aa,sw(:,1),sw(:,3),'s-');plot(aa,sw(:,1),sw(:,4),'^-');grid(aa,'on');xlabel(aa,'State order');ylabel(aa,'Validation RMSE');title(aa,'Motor N4SID model-order comparison');legend(aa,{'RPM','Current','Torque'});out=saveFig(ff,r,'N4SID_Motor','S17_Model_Order',out);
try,save(fullfile(runDir,'EV_Motor_N4SID.mat'),'best','ord','u0','us','y0','ys','Ze','Zv','fit1','fitf','sw');catch,end
out=fitPlot(fit1,fitf,r,'N4SID_Motor','Motor N4SID validation fit','S18_Validation_Fit',{'RPM','Current','Torque'},out);
 fprintf('[EV_Graphs] Motor N4SID order=%d; one-step fit=%s; free-run fit=%s\n',ord,mat2str(fit1,3),mat2str(fitf,3));
end
function out=three(t,y,a,b,r,g,ttl,nm,unit,out)
n=min([numel(t),numel(y),numel(a),numel(b)]);f=figure('Visible','off','Color','w','Position',[100 100 1400 820]);ax=axes(f);plot(ax,t(1:n),y(1:n),'LineWidth',2);hold(ax,'on');plot(ax,t(1:n),a(1:n),'--','LineWidth',1.8);plot(ax,t(1:n),b(1:n),':','LineWidth',2);grid(ax,'on');xlabel(ax,'Validation time (s)');ylabel(ax,unit);title(ax,ttl,'FontWeight','bold');legend(ax,{'Measured','N4SID one-step','N4SID free-run'},'Location','best');out=saveFig(f,r,g,nm,out);
end
function out=parity(y,yp,r,g,ttl,nm,unit,out)
n=min(numel(y),numel(yp));y=y(1:n);yp=yp(1:n);q=isfinite(y)&isfinite(yp);y=y(q);yp=yp(q);if numel(y)<2,out.warnings{end+1}=[nm ': too few samples'];return,end;lo=min([y;yp]);hi=max([y;yp]);if hi<=lo,hi=lo+1;end
f=figure('Visible','off','Color','w');ax=axes(f);scatter(ax,y,yp,22,'filled');hold(ax,'on');plot(ax,[lo hi],[lo hi],'k--');grid(ax,'on');axis(ax,'square');xlabel(ax,['Measured (' unit ')']);ylabel(ax,['Predicted (' unit ')']);title(ax,ttl);out=saveFig(f,r,g,nm,out);
end
function out=inputCorr(e,U,r,g,ttl,nm,out)
e=e(:);n=min(size(U,1),numel(e));e=e(1:n);U=U(1:n,:);ok=isfinite(e)&all(isfinite(U),2);e=e(ok);U=U(ok,:);
if numel(e)<10,out.warnings{end+1}=[nm ': too few samples'];return,end
lag=min(30,floor(numel(e)/4));f=figure('Visible','off','Color','w','Position',[100 100 1300 760]);a=axes(f);hold(a,'on');
for q=1:size(U,2)
 u=U(:,q)-mean(U(:,q));ee=e-mean(e);[c,l]=xcorr(u,ee,lag,'coeff');plot(a,l,c,'LineWidth',1.4,'DisplayName',sprintf('Input %d',q));
end
bound=1.96/sqrt(numel(e));yline(a,bound,'k--');yline(a,-bound,'k--');grid(a,'on');xlabel(a,'Lag (samples)');ylabel(a,'Cross-correlation');title(a,ttl,'FontWeight','bold');legend(a,'Location','best');
out=saveFig(f,r,g,nm,out);
end
function out=fitPlot(f1,ff,r,g,ttl,nm,labels,out)
f1=f1(:)';ff=ff(:)';n=min([numel(f1),numel(ff),numel(labels)]);if n<1,return,end
f=figure('Visible','off','Color','w','Position',[100 100 1100 720]);a=axes(f);bar(a,[f1(1:n);ff(1:n)]');grid(a,'on');xlabel(a,'Output channel');ylabel(a,'Validation fit (%)');title(a,ttl,'FontWeight','bold');set(a,'XTick',1:n,'XTickLabel',labels(1:n));legend(a,{'One-step','Free-run'},'Location','best');
out=saveFig(f,r,g,nm,out);
end
function out=saveFig(f,r,g,nm,out)
d=fullfile(r,g);if ~isfolder(d),mkdir(d);end;try,p=fullfile(d,[nm '.png']);exportgraphics(f,p,'Resolution',300);out.files{end+1}=p;catch ME,out.warnings{end+1}=[nm ': PNG export failed ' ME.message];end;close(f);
end
