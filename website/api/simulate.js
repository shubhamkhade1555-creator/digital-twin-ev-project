const { simulate, checks } = require("../model.js");
const num=(v,d,lo,hi)=>{v=Number(v);return Number.isFinite(v)?Math.min(hi,Math.max(lo,v)):d};
const bool=(v,d)=>v===undefined?d:(v===true||v==="true"||v==="1");
module.exports=(req,res)=>{
  const q=req.method==="POST"?(req.body||{}):req.query;
  const p={rpmRef:num(q.rpmRef,2950,100,3500),ramp:num(q.ramp,13000,100,50000),load:num(q.load,1,0,3),
    Ipeak:num(q.Ipeak,45,5,100),Icont:num(q.Icont,30,5,100),Kt:num(q.Kt,0.107,0.01,1),tstop:num(q.tstop,0.3,0.1,1),
    soc0:num(q.soc0,1,0,1),rFac:num(q.rFac,1,0.2,10),ktFac:num(q.ktFac,1,0.3,1.5),sensOff:num(q.sensOff,0,-0.3,0.3),
    limiter:bool(q.limiter,true),protect:bool(q.protect,true)};
  const run=simulate(p);
  res.status(200).json({...run,checks:checks(run)});
};
