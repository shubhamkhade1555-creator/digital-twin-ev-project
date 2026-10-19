# EV Digital Twin - website (Vercel)
index.html (UI, one screen with tabs) - model.js (shared model and checks) - api/simulate.js, api/runs.js (backend) - data/EV_real_run_from_SysID.csv (real run, 4 channels)

## Deploy (once)
1. Push the project folder to GitHub. In Vercel: Import Project, set **Root Directory = website**. (Or run `npx vercel` inside this folder.)
2. Vercel > Storage > create a **Blob** store and connect it to the project (adds BLOB_READ_WRITE_TOKEN). Without it runs are kept in memory and disappear.
3. Vercel > Settings > Environment Variables: add RUNS_API_KEY = a long random secret. Redeploy.
4. In MATLAB open EV_Website_Config.m (made by Setup_All) and type the site URL and the same key.

## Use
RunAll_and_Push (MATLAB) simulates and uploads. The run appears under Run history within 15 s.
Import CSV accepts columns Vbatt_V, Ibatt_A, SOC, RPM_rpm, Idc_f_A, Vdc_m_V, omega_wheel, Torque_Nm. Missing channels give a WARN and their checks show SKIP.

## API
GET /api/simulate?load=1.5&tstop=0.3 | GET /api/runs | GET /api/runs?id=ID | POST /api/runs (MATLAB needs header x-api-key)
