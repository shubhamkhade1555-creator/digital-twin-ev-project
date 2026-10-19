const { simulate, checks } = require("../model.js");
const num = (v, d, lo, hi) => { v = Number(v); return Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : d; };
module.exports = (req, res) => {
  const q = req.method === "POST" ? (req.body || {}) : req.query;
  const p = { rpmRef: num(q.rpmRef, 2950, 100, 3500), ramp: num(q.ramp, 13000, 100, 50000),
    load: num(q.load, 1, 0, 3), Ipeak: num(q.Ipeak, 45, 5, 100), tstop: num(q.tstop, 0.3, 0.1, 1) };
  const run = simulate(p);
  res.status(200).json({ ...run, checks: checks(run) });
};
