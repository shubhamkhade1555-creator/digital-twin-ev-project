import pandas as pd
import numpy as np

df = pd.read_csv('Simulation Logs/EV_RUN_20261022_031850/EV_DAQ_Clean_11_05.csv')
times = [round(i * 0.005, 5) for i in range(61)]
sub = df[df['Time'].round(5).isin(times)].copy()

header = [
    "| Time_s | Battery_Voltage_V | Battery_Current_A | SOC_percent | Battery_Power_W | DC_Link_Voltage_V | RPM_Reference_rpm | Motor_RPM_rpm | Motor_Torque_Nm | Motor_Current_A | Wheel_Speed_as_logged | Mechanical_Power_W | Efficiency_percent |",
    "|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|"
]

rows = []
for idx, r in sub.iterrows():
    t_str = f"{r['Time']:.5f}"
    vb_str = f"{r['BatteryVoltage']:.2f}"
    ib_str = f"{r['BatteryCurrent']:.2f}"
    soc_str = f"{r['SOC']*100:.4f}"
    pb_str = f"{r['BatteryPower']:.2f}"
    vdc_str = f"{r['DCLinkVoltage']:.2f}"
    rpm_ref_str = f"{r['RPMReference']:.1f}"
    rpm_str = f"{r['RPM']:.1f}"
    tq_str = f"{r['MotorTorque']:.3f}"
    im_str = f"{r['MotorCurrent']:.2f}"
    ws_str = f"{r['WheelSpeed']:.6f}"
    pm_str = f"{r['MotorMechanicalPower']:.2f}"
    eff_str = f"{r['Efficiency']:.2f}"
    row = f"| {t_str} | {vb_str} | {ib_str} | {soc_str} | {pb_str} | {vdc_str} | {rpm_ref_str} | {rpm_str} | {tq_str} | {im_str} | {ws_str} | {pm_str} | {eff_str} |"
    rows.append(row)

output = "\n".join(header + rows)
with open("scratch/table2_markdown.txt", "w", encoding="utf-8") as f:
    f.write(output)

print(f"Generated {len(rows)} rows successfully.")
