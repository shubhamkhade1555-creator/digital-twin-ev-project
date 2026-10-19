(function(root){
"use strict";
const KEYS=["rpm","ref","i","T","vb","ib","soc","vdc","ww","est","tm","tb"];
const f=(x,d=1)=>isFinite(x)?(+x).toFixed(d):"-";
const DEF={rpmRef:2950,ramp:13000,load:1,Ipeak:45,Icont:30,Kt:0.107,tstop:0.3,soc0:1,rFac:1,ktFac:1,sensOff:0,packAh:50,limiter:true,protect:true};
const SCEN=[
{id:"nom",name:"Baseline - healthy system",p:{},cause:"No fault. Parameter-file values (the reference run).",
 help:["Keep the monthly check of pack resistance, speed sensor and torque per amp.","Use this run as the reference for every other scenario."]},
{id:"ovl",name:"Overload - hill climb at 1.8 x load",p:{load:1.8},cause:"The vehicle demands 5.7 Nm instead of 3.18 Nm.",
 help:["The current limiter (I peak 45 A) holds the motor: the rider loses speed instead of the motor overheating.","Warn the driver when the current stays above I continuous for more than 1 s.","Power map: lower the maximum load in the controller for steep climbs."]},
{id:"aged",name:"Aged battery - pack resistance x4",p:{rFac:4},cause:"Cell ageing or a loose busbar: the internal resistance rises.",
 help:["BMS resistance trend: alarm when pack resistance is above twice its new value.","Battery over-temperature derate (projected 60 C) limits the current before the cells are damaged.","Service: check busbars and connectors, replace the weak module."]},
{id:"lowsoc",name:"Low charge - start SOC 8 %",p:{soc0:0.08},cause:"The pack was not charged; its voltage is close to the 45.4 V minimum.",
 help:["Undervoltage cut-off at 46 V: derate the drive before the pack reaches its minimum.","Charge warning below 15 % SOC.","Limp-home mode keeps the vehicle moving at low power instead of stopping suddenly."]},
{id:"demag",name:"Magnet weakening - Kt -30 %",p:{ktFac:0.7},cause:"Overheating or ageing weakens the permanent magnets.",
 help:["Torque-per-amp monitor: the back-EMF gives Kt; alarm at 10 % deviation.","Service: magnet check. The motor now needs more current for the same torque.","Keep motor temperature limits so the magnets are not overheated."]},
{id:"sens",name:"Speed sensor drift +8 %",p:{sensOff:0.08},cause:"Hall or encoder drift: the sensor reads 8 % high, so the controller under-drives the motor.",
 help:["Plausibility check: sensor speed against the back-EMF estimate (threshold 6 %).","Sensorless fallback: the controller uses the estimate, so the true speed stays at target.","Driver warning: sensor fault, limp mode. Without this the dashboard shows the target as reached."]},
{id:"lim",name:"Current limiter failure",p:{limiter:false},cause:"Software or PI limiter stops working: no current clamp.",
 help:["Hardware over-current trip: 0.1 ms above 1.1 x I peak switches the inverter off. A software check at 5 ms is too slow.","Self-test of the limiter at each start-up.","Fuse or contactor in the DC link as the last barrier."]},
{id:"combo",name:"Combined - aged pack + overload",p:{rFac:4,load:1.8},cause:"Two faults at the same time: the realistic worst case on a hill.",
 help:["Both protections act: battery derate for the pack, current limit for the motor.","Vehicle goes to limp-home; the event is written to the Black Box.","Do not drive on until the battery has been inspected."]}
];

function simulate(q){
 const p=Object.assign({},DEF,q||{});
 const dt=1e-5,N=Math.round(p.tstop/dt),REC=100;
 const Rw=0.2,Lm=2e-4,J=0.002+0.5*1.5*0.0625/121,Kpw=0.05,Kiw=10,Vdc=48,IH=120,Rth=0.1,Rbth=1.5;
 const Kt=p.Kt*p.ktFac,KtC=p.Kt,Rp=0.011*p.rFac,Ah=p.packAh;
 const voc=s=>45.4+9.1*s;
 const loadF=tt=>p.load*3.18*Math.min(Math.max((tt-0.23)/0.05,0),1);
 const d={};KEYS.forEach(k=>d[k]=[]);
 const t=[],ev=[],seen={};
 const add=(tt,msg,kind)=>{if(seen[msg])return;seen[msg]=1;ev.push({t:+tt.toFixed(4),msg:msg,kind:kind})};
 let w=0,i=0,ig=0,soc=p.soc0,ib=0,ibF=0,vb=voc(p.soc0),If=0,vc=0,west=0,uvT=0,ocT=0,sensT=0,ktT=0;
 let fb=false,derate=false,trip=false,tmax=0,tbmax=0,Vmin=1e9,Tm=25,Tb=25;
 for(let k=0;k<=N;k++){
  const tt=k*dt,rpm=w*60/6.2832,meas=rpm*(1+p.sensOff);
  const refR=Math.min(p.rpmRef,p.ramp*tt);
  west+=((vc-Rw*If)/KtC-west)*dt/2e-3;
  const est=west*60/6.2832;
  const tRamp=p.rpmRef/Math.max(p.ramp,1);
  if(p.protect&&!fb&&tt>0.1&&tt>tRamp+0.02){
   if(Math.abs(meas-est)>0.06*Math.max(est,500)){
    sensT+=dt;
    if(sensT>0.02){add(tt,"Speed sensor and back-EMF estimate differ by more than 6 %","warn");fb=true;add(tt,"Sensorless fallback: controller uses the back-EMF estimate","act")}
   } else sensT=0;
  }
  if(tt>0.15&&w>200){
   const ktE=(vc-Rw*If)/w;
   if(Math.abs(ktE-KtC)/KtC>0.1){ktT+=dt;if(ktT>0.02)add(tt,"Torque-per-amp check: back-EMF gives Kt more than 10 % off the datasheet","warn")}
   else ktT=0;
  }
  if(vb<46){uvT+=dt;if(uvT>0.01&&p.protect&&!derate){derate=true;add(tt,"BMS undervoltage cut-off: pack below 46 V, drive derated to 50 % current","act")}}
  else uvT=0;
  if(vb<45.4)add(tt,"Battery below 45.4 V minimum: deep-discharge damage risk","fail");
  Tm=25+Rth*1.5*If*If*Rw; Tb=25+Rbth*ibF*ibF*Rp;
  if(Tm>tmax)tmax=Tm; if(Tb>tbmax)tbmax=Tb; if(vb<Vmin)Vmin=vb;
  if((Tm>120||Tb>60)&&p.protect&&!derate){derate=true;add(tt,"Thermal protection: projected temperature above limit, drive derated to 50 % current","act")}
  if(Tm>120&&!p.protect)add(tt,"Motor projected above 120 C: winding and magnet damage","fail");
  if(Tb>60&&!p.protect)add(tt,"Battery projected above 60 C: cell damage risk","fail");
  const Ilim=derate?0.5*p.Icont:p.Ipeak;
  if(i>1.1*p.Ipeak){
   ocT+=dt;
   if(!p.protect&&ocT>5e-3)add(tt,"Over-current: motor current above 1.1 x I peak with no protection: inverter and winding stress","fail");
   if(p.protect&&!p.limiter&&ocT>1e-4&&!trip){trip=true;add(tt,"Hardware over-current trip (0.1 ms): drive switched off, safe state","act")}
  } else ocT=0;
  const ctrl=(p.protect&&fb)?est:meas, e=refR-ctrl;
  ig=Math.max(0,Math.min(Vdc,ig+Kiw*e*dt));
  vc=Math.max(0,Math.min(Vdc,Kpw*e+ig));
  if(p.limiter){const vmax=KtC*w+Rw*Ilim+0.2*(Ilim-i);if(vc>vmax)vc=Math.max(vmax,0)}
  if(trip)vc=0;
  i=Math.max(0,i+(vc-Kt*w-Rw*i)/Lm*dt);
  if(!p.limiter&&i>IH){i=IH;add(tt,"Hardware over-current: 120 A inverter limit reached, power devices at risk","fail")}
  w+=(Kt*i-loadF(tt)-1e-4*w)*dt/J;
  If+=(i-If)*dt/2e-3;
  ib=vc*i/(0.97*vb);
  ibF+=(ib-ibF)*dt/5e-3;
  vb=voc(soc)-Rp*ib;
  soc-=ib*dt/(Ah*3600);
  if(k%REC===0){t.push(+tt.toFixed(4));d.rpm.push(rpm);d.ref.push(refR);d.i.push(If);d.T.push(Kt*If);d.vb.push(vb);d.ib.push(ib);d.soc.push(soc);d.vdc.push(vc);d.ww.push(w/11);d.est.push(est);d.tm.push(Tm);d.tb.push(Tb)}
 }
 const L=t.length-1;
 const sum={finalRpm:d.rpm[L],refFinal:d.ref[L],Ipk:Math.max(...d.i),Ifin:d.i[L],Vb:d.vb[L],Ib:d.ib[L],Vmin:Vmin,
  SOCdrop:d.soc[0]-d.soc[L],Tmax:tmax,Tbmax:tbmax,Tload:loadF(p.tstop),Ilim:derate?0.5*p.Icont:p.Ipeak,derate:derate,trip:trip,fb:fb};
 const hasF=ev.some(e=>e.kind==="fail"),hasA=ev.some(e=>e.kind==="act"),hasW=ev.some(e=>e.kind==="warn");
 const hidden=p.sensOff!==0&&!fb;
 let outcome;
 if(hasF)outcome="INCIDENT";else if(hidden)outcome="HIDDEN FAULT";else if(hasA)outcome="PREVENTED";
 else if(hasW||sum.Ifin>p.Icont*1.02||Vmin<46||tmax>100||sum.finalRpm>3000)outcome="WARNING";else outcome="NORMAL";
 return{t:t,d:d,p:p,ev:ev,outcome:outcome,sum:sum,fb:fb,hidden:hidden};
}

function explain(r){
 const p=r.p,s=r.sum,d=r.d,Kt=p.Kt*p.ktFac,Rp=0.011*p.rFac,w=s.finalRpm*2*Math.PI/60,Pm=s.Tload*w,Pb=Pm/0.97,soc=d.soc[d.soc.length-1];
 const Tme=25+0.1*1.5*s.Ifin*s.Ifin*0.2,Tbe=25+1.5*s.Ib*s.Ib*Rp;
 return[
 "1. Load torque at end:      T = "+p.load+" x 3.18 = "+s.Tload.toFixed(2)+" N*m",
 "2. Torque constant in use:  Kt = "+p.Kt+" x "+p.ktFac+" = "+Kt.toFixed(4)+" N*m/A",
 "3. Current needed:          I = T / Kt = "+s.Tload.toFixed(2)+" / "+Kt.toFixed(4)+" = "+(s.Tload/Kt).toFixed(1)+" A   (limit now "+s.Ilim+" A)",
 "4. Speed:                   true "+s.finalRpm.toFixed(0)+" rpm, target "+s.refFinal.toFixed(0)+" rpm ("+((s.finalRpm-s.refFinal)/s.refFinal*100).toFixed(1)+" %)",
 "5. Mechanical power:        P = T x w = "+s.Tload.toFixed(2)+" x "+w.toFixed(1)+" = "+(Pm/1000).toFixed(2)+" kW",
 "6. Battery power:           P_bat = P / 0.97 = "+(Pb/1000).toFixed(2)+" kW",
 "7. Battery current:         I_bat = P_bat / V_bat = "+Pb.toFixed(0)+" / "+s.Vb.toFixed(2)+" = "+s.Ib.toFixed(1)+" A",
 "8. Pack voltage:            V_bat = (45.4 + 9.1 x SOC) - R_pack x I_bat = (45.4 + 9.1 x "+soc.toFixed(4)+") - "+Rp.toFixed(4)+" x "+s.Ib.toFixed(1)+" = "+s.Vb.toFixed(2)+" V",
 "9. Charge used:             dSOC = integral(I_bat dt) / (3600 x "+p.packAh+" Ah) = "+(s.SOCdrop*100).toFixed(4)+" % of capacity",
 "10. Motor temperature:      T_m = 25 + 0.1 K/W x 1.5 x I^2 x 0.2 ohm = "+Tme.toFixed(0)+" C at end, peak "+s.Tmax.toFixed(0)+" C (limit 120 C)",
 "11. Battery temperature:    T_b = 25 + 1.5 K/W x I_bat^2 x R_pack = "+Tbe.toFixed(0)+" C at end, peak "+s.Tbmax.toFixed(0)+" C (limit 60 C)",
 "12. Protection state:       limiter "+(p.limiter?"on":"OFF")+", protection "+(p.protect?"on":"OFF")+", derate "+(s.derate?"yes":"no")+", trip "+(s.trip?"yes":"no")+", sensor fallback "+(s.fb?"yes":"no")
 ];
}

function checks(r){
 const p=r.p,d=r.d,n=r.t.length,C=[],add=(a,b,c,s)=>C.push({n:a,r:b,v:c,s:s});
 const g=k=>d[k]||[],bad=v=>v==null||!isFinite(v);
 const mean=(a,m)=>{const s=a.slice(-m);return s.reduce((x,y)=>x+y,0)/s.length};
 const mx=a=>Math.max(...a.filter(v=>isFinite(v)));
 const K=["rpm","i","vb","ib","soc"],miss=K.filter(k=>g(k).length===0||g(k).every(bad)),nan=K.some(k=>g(k).some(bad));
 add("Black-box size","1 ms, "+(Math.round(p.tstop*1000)+1)+" samples",n+" samples",n===Math.round(p.tstop*1000)+1?"PASS":"FAIL");
 add("No NaN values","all channels valid",nan?"NaN in data":miss.length?"missing: "+miss.join(", "):"clean",nan?"FAIL":miss.length?"WARN":"PASS");
 add("Reached t_stop","last time = "+p.tstop+" s",f(r.t[n-1],3)+" s",Math.abs(r.t[n-1]-p.tstop)<1e-3?"PASS":"FAIL");
 const rEnd=g("rpm")[n-1];
 add("Final speed (true)","target "+p.rpmRef+" rpm +/-2 %",f(rEnd,0)+" rpm",Math.abs(rEnd-p.rpmRef)<=0.02*p.rpmRef?"PASS":"FAIL");
 const tpa=mean(g("T"),10)/mean(g("i"),10);
 add("Torque per amp (Kt)",p.Kt+" N*m/A +/-5 %",f(tpa,4),Math.abs(tpa/p.Kt-1)<=0.05?"PASS":"WARN");
 const pk=mx(g("i"));
 add("Peak motor current","<= 1.1 x I peak = "+f(1.1*p.Ipeak)+" A",f(pk)+" A",pk<=1.1*p.Ipeak?"PASS":"FAIL");
 const mc=mean(g("i"),20);
 add("Motor current vs I_cont","mean last 20 ms <= "+p.Icont+" A",f(mc)+" A",mc<=p.Icont?"PASS":"WARN");
 const ch=g("ib").reduce((a,b)=>a+b,0)*1e-3/(p.packAh*3600),dS=g("soc")[0]-g("soc")[n-1],q=ch>0?dS/ch:1;
 add("SOC vs coulomb count","ratio 0.8-1.25",f(q,2),q>=0.8&&q<=1.25?"PASS":"WARN");
 const pr=mean(g("vdc").map((v,j)=>v*g("i")[j]),20)/mean(g("vb").map((v,j)=>v*g("ib")[j]),20);
 add("Power balance Pdc/Pbatt","0.85-1.02",f(pr,3),pr>=0.85&&pr<=1.02?"PASS":"WARN");
 const vmin=mx(g("vb").map(v=>-v));
 const vlo=-vmin;
 add("Battery voltage minimum","not below 45.4 V",f(vlo,2)+" V",vlo>=45.4?"PASS":"FAIL");
 const tmm=mx(g("tm"));
 add("Motor projected temperature","<= 120 C",f(tmm,0)+" C",tmm<=120?"PASS":"FAIL");
 const tbm=mx(g("tb"));
 add("Battery projected temperature","<= 60 C",f(tbm,0)+" C",tbm<=60?"PASS":"FAIL");
 return C;
}

const api={simulate:simulate,checks:checks,explain:explain,SCEN:SCEN,DEF:DEF,KEYS:KEYS};
if(typeof module!=="undefined"&&module.exports)module.exports=api;else root.EVModel=api;
})(typeof self!=="undefined"?self:this);
