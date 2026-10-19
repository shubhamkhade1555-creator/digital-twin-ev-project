(function(root){
const KEYS=["rpm","ref","i","T","vb","ib","soc","vdc","ww"],f=(x,d=1)=>isFinite(x)?(+x).toFixed(d):"-";
/* ---------- reduced-order physics model (mirrors BLDCSpeedControlData.m) ---------- */
function simulate(p){const dt=1e-5,N=Math.round(p.tstop/dt),Kt=.107,R=.2,Lm=2e-4,J=.002+.5*1.5*.25*.25/121,Kpw=.05,Kiw=10,Vdc=48,Rp=.011,Ah=50;
 const d={};KEYS.forEach(k=>d[k]=[]);const t=[];let w=0,i=0,ig=0,soc=1,ib=0,vb=54.5,If=0,vc=0;
 const voc=s=>45.4+9.1*s,load=tt=>tt<.23?0:tt>=.28?p.load*3.18:p.load*3.18*(tt-.23)/.05;
 for(let k=0;k<=N;k++){const tt=k*dt,rpm=w*60/6.2832,ref=Math.min(p.rpmRef,p.ramp*tt);
  if(k%100==0){t.push(+tt.toFixed(4));d.rpm.push(rpm);d.ref.push(ref);d.i.push(If);d.T.push(Kt*i);d.vb.push(vb);d.ib.push(ib);d.soc.push(soc);d.vdc.push(vc);d.ww.push(w/11)}
  const e=ref-rpm;ig=Math.max(0,Math.min(Vdc,ig+Kiw*e*dt));vc=Math.max(0,Math.min(Vdc,Kpw*e+ig));
  const vmax=Kt*w+R*p.Ipeak+.2*(p.Ipeak-i);if(vc>vmax)vc=Math.max(vmax,0);
  i=Math.max(0,i+(vc-Kt*w-R*i)/Lm*dt);w+=(Kt*i-load(tt)-1e-4*w)*dt/J;If+=(i-If)*dt/2e-3;
  ib=vc*i/(.97*vb);vb=voc(soc)-Rp*ib;soc-=ib*dt/(Ah*3600)}
 return{t,d,p,src:"model"}}
/* ---------- checks (same rules as RunAll step 9) ---------- */
const mean=(a,n)=>{const s=a.slice(-n);return s.reduce((x,y)=>x+y,0)/s.length};
function checks(r){const p=r.p,d=r.d,n=r.t.length,C=[],add=(a,b,c,s)=>C.push({n:a,r:b,v:c,s});
 const bad=v=>v==null||!isFinite(v),miss=KEYS.filter(k=>k!="ref"&&d[k].every(bad)),nan=KEYS.filter(k=>k!="ref"&&!miss.includes(k)).some(k=>d[k].some(bad)),sk=(...ks)=>ks.some(k=>miss.includes(k));
 add("Black-box size","1 ms, "+(p.tstop*1000+1)+" samples",n+" samples",n==Math.round(p.tstop*1000)+1?"PASS":"FAIL");
 add("No NaN values","all channels valid",nan?"NaN in data":miss.length?"missing: "+miss.join(", "):"clean",nan?"FAIL":miss.length?"WARN":"PASS");
 add("Reached t_stop","last time = "+p.tstop+" s",f(r.t[n-1],3)+" s",Math.abs(r.t[n-1]-p.tstop)<1e-3?"PASS":"FAIL");
 const ok0=d.soc[0]>.999&&Math.abs(d.rpm[0])<1&&d.vb[0]>45&&d.vb[0]<55;
 add("Initial state","SOC>99.9 %, 0 rpm, 45–55 V",`${f(d.soc[0]*100,2)} %, ${f(d.rpm[0],0)} rpm, ${f(d.vb[0])} V`,ok0?"PASS":"FAIL");
 const fr=d.rpm[n-1];add("Final speed","2900–3000 rpm",f(fr,1)+" rpm",fr>=2900&&fr<=3000?"PASS":"FAIL");
 const tpa=mean(d.T,10)/mean(d.i,10);add("Torque per amp","0.107 N·m/A ±5 %",sk("T","i")?"no data":f(tpa,4),sk("T","i")?"SKIP":Math.abs(tpa/.107-1)<=.05?"PASS":"WARN");
 const pk=Math.max(...d.i);add("Peak motor current","≤ 1.1 × I_peak = "+f(1.1*p.Ipeak)+" A",f(pk)+" A",pk<=1.1*p.Ipeak?"PASS":"FAIL");
 const mc=mean(d.i,20);add("Motor current vs I_cont","mean last 20 ms ≤ 30 A",f(mc)+" A",mc<=30?"PASS":"WARN");
 const need=(.002+.5*1.5*.0625/121)*(p.ramp*.10472)/.107;add("Ramp current demand","≤ I_cont (30 A)",f(need)+" A",need<=30?"PASS":"WARN");
 const ch=d.ib.reduce((a,b)=>a+b,0)*1e-3/(50*3600),dS=d.soc[0]-d.soc[n-1],q=ch>0?dS/ch:1;add("SOC vs coulomb count","ratio 0.8–1.25",sk("ib")?"no data":f(q,2),sk("ib")?"SKIP":q>=.8&&q<=1.25?"PASS":"WARN");
 const pr=mean(d.vdc.map((v,j)=>v*d.i[j]),20)/mean(d.vb.map((v,j)=>v*d.ib[j]),20);add("Power balance Pdc/Pbatt","0.85–1.02",sk("vdc","ib")?"no data":f(pr,3),sk("vdc","ib")?"SKIP":pr>=.85&&pr<=1.02?"PASS":"WARN");
 const vmin=Math.min(...d.vb);add("Battery voltage window","45.4–54.5 V",f(vmin,2)+" V min",vmin>=45.4?"PASS":"FAIL");
 return C}

const api={simulate,checks,KEYS};
if(typeof module!=="undefined"&&module.exports)module.exports=api;else root.EVModel=api;
})(typeof self!=="undefined"?self:this);
