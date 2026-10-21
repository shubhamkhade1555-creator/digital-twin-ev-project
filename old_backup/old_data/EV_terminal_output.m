function EV_terminal_output()

fprintf('\n');
fprintf('========================================\n');
fprintf('       EV SIMULATION COMPLETED\n');
fprintf('========================================\n');

% Simulation time
try
    fprintf('Simulation Time : %.3f s\n', evalin('base','t_stop'));
catch
end

% Display available final results
try
    fprintf('Battery Voltage : %.2f V\n', evalin('base','BatteryVoltage'));
catch
end

try
    fprintf('Battery Current : %.2f A\n', evalin('base','BatteryCurrent'));
catch
end

try
    fprintf('Motor Speed     : %.2f RPM\n', evalin('base','MotorRPM'));
catch
end

try
    fprintf('Motor Current   : %.2f A\n', evalin('base','MotorCurrent'));
catch
end

try
    fprintf('SOC             : %.4f\n', evalin('base','SOC'));
catch
end

fprintf('========================================\n');
fprintf('       END OF SIMULATION\n');
fprintf('========================================\n\n');

end