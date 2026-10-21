function EV_Model_Fixes_V8(step)
% EV_Model_Fixes_V8(step)  - model-side changes, ONE STEP PER RUN, model must be stopped.
%   1  buck RC snubber -> exclude            (enum members: exclude / include; hypothesis for the Nyquist ringing, to be verified by the run)
%   2  Simscape local solver -> Backward Euler (only if step 1 did not remove the ringing)
%   3  prints the input-capacitor recipe     (only if step 1/2 leave real 10 kHz ripple above limits)
%   4  Vdc feedback filter T = 0.01 -> 0.002 s (control tuning experiment, optional)
% Every step: backup copy, change, read-back, save. NOTHING here has been executed by the author -
% read the printed read-back lines and run the V&V (EV_DAQ_Builder_V7) after each step.
MDL = 'BLDCSpeedControl_EV_Layout_v2';
if ~bdIsLoaded(MDL), load_system(MDL); end
assert(strcmpi(get_param(MDL,'SimulationStatus'),'stopped'), 'Stop the model first.');
f = which([MDL '.slx']);
bak = strrep(f,'.slx',sprintf('_before_step%d.slx',step));
if ~isfile(bak), copyfile(f,bak); end
switch step
    case 1
        % V8.1: the members of ee.enum.converters.snubber are 'exclude' and 'include' (there is NO 'none'). The old code stored the
        % unresolvable string '...snubber.none' (MATLAB only warned), the readback compared against '1' and reported success,
        % and the model then failed to compile. Now: valid member only, readback must match, compile check, revert on failure.
        blk  = [MDL '/DC-DC Buck Converter'];
        want = 'ee.enum.converters.snubber.exclude';
        members = arrayfun(@char, enumeration('ee.enum.converters.snubber'), 'UniformOutput', false);
        if ~any(strcmp(members, 'exclude')), error('snubber enumeration has no member "exclude": %s', strjoin(members', ', ')); end
        old = get_param(blk,'snubber_type');
        fprintf('snubber_type before: %s (Cs=%s, Rs=%s)  [valid members: %s]\n', old, get_param(blk,'Cs'), get_param(blk,'Rs'), strjoin(members', ', '));
        if strcmp(old, want)
            fprintf('snubber_type already %s - nothing to change.\n', want);
        else
            lastwarn('');
            set_param(blk,'snubber_type',want);
            [wm, ~] = lastwarn;
            got = get_param(blk,'snubber_type');
            if ~strcmp(got, want) || ~isempty(wm)
                set_param(blk,'snubber_type',old);
                error('snubber_type NOT set (readback "%s", warning "%s"). Original restored.', got, wm);
            end
            try
                set_param(MDL,'SimulationCommand','update');            % compile check
            catch ME
                set_param(blk,'snubber_type',old);
                error('Model does not compile with snubber_type = exclude, original restored: %s', ME.message);
            end
            fprintf('snubber_type now   : %s (compile check passed)\n', get_param(blk,'snubber_type'));
        end
    case 2
        sc = [MDL '/Solver' newline 'Configuration'];
        fprintf('LocalSolverChoice before: %s\n', get_param(sc,'LocalSolverChoice'));
        set_param(sc,'LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER');
        fprintf('LocalSolverChoice now   : %s\n', get_param(sc,'LocalSolverChoice'));
    case 3
        fprintf(['Input capacitor (do by hand, wiring cannot be scripted safely without the port layout):\n' ...
            '  Add Simscape > Foundation > Electrical > Elements > Capacitor (C = 2.2 mF, series resistance 10 mOhm)\n' ...
            '  directly across the buck converter input terminals 1+ / 1- (battery side).\n' ...
            '  Starting value only: ripple ~ I*D*(1-D)/(f*C) = 30*0.21/(1e4*2.2e-3) = 0.29 V (ESR adds I*ESR).\n' ...
            '  Re-run and read VV-020 / VV-021; adjust C / ESR from the raw ripple, do not trust this number.\n']);
        return
    case 4
        b = [MDL '/Speed//RPM Controller/Vdc filter'];
        fprintf('T before: %s\n', get_param(b,'T'));  set_param(b,'T','0.002');  fprintf('T now: %s\n', get_param(b,'T'));
    otherwise
        error('step must be 1..4');
end
save_system(MDL);  fprintf('saved. backup: %s\n', bak);
end
