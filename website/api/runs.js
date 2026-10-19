// GET /api/runs -> list | GET /api/runs?id=X -> one run | POST /api/runs -> save a run
// Storage: Vercel Blob when BLOB_READ_WRITE_TOKEN exists, else memory (lost on cold start).
const { checks, KEYS } = require("../model.js");
let blob = null; try { blob = require("@vercel/blob"); } catch (e) {}
const useBlob = () => blob && process.env.BLOB_READ_WRITE_TOKEN;
const mem = globalThis.__evruns || (globalThis.__evruns = new Map());
const getJson = async (prefix) => { const { blobs } = await blob.list({ prefix }); return Promise.all(blobs.map(b => fetch(b.url).then(r => r.json()))); };

async function listRuns() {
  const m = useBlob() ? await getJson("meta/") : [...mem.values()].map(r => r.meta);
  return m.sort((a, b) => (a.ts < b.ts ? 1 : -1)).slice(0, 50);
}
async function getRun(id) {
  if (!useBlob()) return mem.get(id) || null;
  const r = await getJson(`runs/${id}.json`); return r[0] || null;
}
async function putRun(run) {
  if (!useBlob()) { mem.set(run.id, run); if (mem.size > 50) mem.delete(mem.keys().next().value); return; }
  const o = { access: "public", addRandomSuffix: false, contentType: "application/json" };
  await blob.put(`runs/${run.id}.json`, JSON.stringify(run), o);
  await blob.put(`meta/${run.id}.json`, JSON.stringify(run.meta), o);
}

module.exports = async (req, res) => {
  try {
    if (req.method === "GET") {
      if (req.query.id) {
        const id = String(req.query.id); if (!/^[\w-]+$/.test(id)) return res.status(400).json({ error: "bad id" });
        const r = await getRun(id); return r ? res.status(200).json(r) : res.status(404).json({ error: "not found" });
      }
      return res.status(200).json(await listRuns());
    }
    if (req.method !== "POST") return res.status(405).json({ error: "method not allowed" });
    const b = req.body || {}, key = process.env.RUNS_API_KEY;
    const matlab = b.source === "matlab";
    if (matlab && (!key || req.headers["x-api-key"] !== key)) return res.status(401).json({ error: "bad or missing x-api-key" });
    if (!Array.isArray(b.t) || b.t.length < 5 || b.t.length > (matlab ? 20001 : 2001) || typeof b.d !== "object")
      return res.status(400).json({ error: "need t[] (5..2000 samples) and d{}" });
    const n = b.t.length, tstop = Number(b.t[n - 1]) || 0.3, bp = b.p || {};
    const p = { rpmRef: +bp.rpmRef || 2950, ramp: +bp.ramp || 13000, load: bp.load == null ? 1 : +bp.load, Ipeak: +bp.Ipeak || 45, tstop: +tstop.toFixed(3) };
    const d = {};
    KEYS.forEach(k => { d[k] = Array.isArray(b.d[k]) && b.d[k].length === n ? b.d[k].map(v => (v == null ? null : +v))
      : k === "ref" ? b.t.map(x => Math.min(p.rpmRef, p.ramp * x)) : Array(n).fill(null); });
    const run = { t: b.t.map(Number), d, p };
    const chk = checks({ ...run, d: Object.fromEntries(KEYS.map(k => [k, d[k].map(v => (v == null ? NaN : v))])) });
    const result = chk.some(c => c.s === "FAIL") ? "FAIL" : chk.some(c => c.s === "WARN") ? "WARN" : "PASS";
    const id = new Date().toISOString().replace(/\D/g, "").slice(0, 14) + "-" + Math.random().toString(36).slice(2, 5);
    const last = a => a[a.length - 1];
    const meta = { id, ts: new Date().toISOString(), source: matlab ? "matlab" : (b.source === "csv" ? "csv" : "web"), name: String(b.name || "").slice(0, 60),
      setup: `${p.rpmRef} rpm, load x${p.load}, ${p.tstop} s`, finalRpm: last(d.rpm), peak: Math.max(...d.i.filter(v => v != null)), result };
    await putRun({ ...meta, ...run, meta, checks: chk });
    return res.status(200).json({ id, result, storage: useBlob() ? "blob" : "memory" });
  } catch (e) { return res.status(500).json({ error: e.message }); }
};
