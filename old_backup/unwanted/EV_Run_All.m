function EV_Run_All(varargin)
% EV_Run_All  - ONE command: model fixes + DAQ setup + simulation + post-processing.
%
%   EV_Run_All                 snubber exclude (step 1, idempotent) + DAQ setup + run
%   EV_Run_All('Solver',true)  also switch the Simscape local solver to Backward Euler (step 2)
%   EV_Run_All('Tune',true)    also set the Vdc filter to 2 ms (step 4, control experiment)
%   EV_Run_All('Run',false)    apply everything but do not start the simulation
%
% Step 3 (battery-side input capacitor) is wired by hand and is NOT done here: decide it
% from VV-020 / VV-021 of this run.
% Not executed by the author. Read every printed line; backups are written as
% BLDCSpeedControl_EV_Layout_v2_before_stepN.slx next to the model.

p = inputParser;
addParameter(p,'Solver',false,@islogical);
addParameter(p,'Tune',  false,@islogical);
addParameter(p,'Run',   true, @islogical);
parse(p,varargin{:});

root = 'C:\Users\shubh\OneDrive\Documents\MATLAB\EV_DigitalTwin';
if isfolder(root), cd(root); end
addpath(pwd);
if isfolder(fullfile(pwd,'+Batteries2')), addpath(genpath(pwd)); end
MDL = 'BLDCSpeedControl_EV_Layout_v2';

fprintf('\n=== EV_Run_All ===\n');
if bdIsLoaded(MDL)
    if ~strcmpi(get_param(MDL,'SimulationStatus'),'stopped')
        error('Model is running. Press STOP, wait for Ready, then run EV_Run_All again.');
    end
    close_system(MDL,0);                       % reload from disk (no unsaved edits are kept)
end
clear functions                                % pick up the patched .m files

fprintf('--- step 1: buck snubber -> exclude (no snubber) ---\n');
EV_Model_Fixes_V8(1);
if p.Results.Solver
    fprintf('--- step 2: local solver -> Backward Euler ---\n');
    EV_Model_Fixes_V8(2);
end
if p.Results.Tune
    fprintf('--- step 4: Vdc filter T = 0.002 s ---\n');
    EV_Model_Fixes_V8(4);
end

fprintf('--- DAQ setup (patched V7.1) %s ---\n', iif(p.Results.Run,'and simulation start','only'));
EV_DAQ_Builder_V7('Run', p.Results.Run);
end

function s = iif(c,a,b)
if c, s = a; else, s = b; end
end
