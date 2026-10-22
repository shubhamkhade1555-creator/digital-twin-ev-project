# Fix 3 — Motor-current acceptance policy

**Branch:** `fix/dclink-measured-current-gating`  
**Decision status:** Owner-approved policy update  
**Merge status:** Not merged to `main`

## Approved criteria

| Check | Implemented project acceptance limit | Datasheet / limiter context |
|---|---:|---|
| VV-004 — motor-current RMS | 35 A | Datasheet continuous rating remains 30 A; 35 A continuous operation is unconfirmed |
| VV-008 — steady-state average motor current | 35 A | Datasheet continuous rating remains 30 A; 35 A continuous operation is unconfirmed |
| VV-023 — hold-window mean motor current | 35 A | Datasheet continuous rating remains 30 A; 35 A continuous operation is unconfirmed |
| VV-003 — peak motor current | 48 A | Retained as approved: 45 A limiter plus 3 A margin |

## Important distinction

The 35 A value is a **project acceptance threshold only**. It does not amend or validate the motor manufacturer's 30 A continuous-current rating. The datasheet status for continuous operation at 35 A is **UNCONFIRMED**.

The physical limiter, `I_cont = 30 A`, and the datasheet-based VV-022 I²t budget are intentionally unchanged. VV-003 remains 48 A. No Simulink physical model parameters are changed by this policy-only update.

## Latest-run status context

The last supplied run summary reported:
- VV-004: PASS under the previously configured 30 A criterion.
- VV-008: FAIL under the previously configured 30 A criterion because the mean exceeded 30 A.
- VV-023: NOT_AVAILABLE in the latest run.

Those are historical statuses under the prior configuration. After the code change, rerun the pipeline to calculate fresh statuses against the approved 35 A project threshold. Do not relabel historical results as newly tested results.

## Files updated

- `EV_DAQ_Builder_V7.m`: VV-004, VV-008, and VV-023 use the separate 35 A project acceptance threshold. The generated Limits report documents the 30 A rating, 35 A project limit, and 48 A peak criterion side by side.
- `RunAll.m`: the final-20-ms motor-current audit uses 35 A as the project acceptance threshold and logs the 30 A datasheet rating separately.
- `RunAll.m`'s peak-current logic and the DAQ's VV-003 criterion were not changed.

## Verification status

Source changes were inspected on the fix branch. MATLAB/Simulink execution has **not** been performed in this environment; run `RunAll.m` in MATLAB before considering the change runtime-verified.
