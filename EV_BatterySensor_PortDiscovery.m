function EV_BatterySensor_PortDiscovery()
% Inspect the existing battery and DC-DC converter ports.
% Read-only inspection: does not alter or save the model.

mdl = 'BLDCSpeedControl_EV_Layout_v2';

if ~bdIsLoaded(mdl)
    load_system(mdl);
end

fprintf('\n=== EV BATTERY SENSOR PORT DISCOVERY ===\n');
fprintf('Model: %s\n', mdl);
fprintf('File: %s\n', get_param(mdl, 'FileName'));
fprintf('Stop Time: %s s\n', get_param(mdl, 'StopTime'));

% Locate likely top-level blocks.
allBlocks = find_system(mdl, ...
    'SearchDepth', 1, ...
    'Type', 'Block');

for k = 1:numel(allBlocks)
    try
        nm = get_param(allBlocks{k}, 'Name');
        if contains(lower(nm), 'battery') || ...
           contains(lower(nm), 'buck') || ...
           contains(lower(nm), 'sensor') || ...
           contains(lower(nm), 'converter')
            fprintf('\nBLOCK: %s\n', allBlocks{k});
            fprintf('  BlockType: %s\n', ...
                get_param(allBlocks{k}, 'BlockType'));

            % ReferenceBlock exists only on library-linked blocks (not SubSystems),
            % so read it separately to avoid skipping the port listing.
            try
                fprintf('  ReferenceBlock: %s\n', ...
                    get_param(allBlocks{k}, 'ReferenceBlock'));
            catch
                fprintf('  ReferenceBlock: (none)\n');
            end

            ph = get_param(allBlocks{k}, 'PortHandles');
            portGroups = {'LConn','RConn','Inport','Outport'};

            for g = 1:numel(portGroups)
                field = portGroups{g};
                if ~isfield(ph, field)
                    continue;
                end

                for j = 1:numel(ph.(field))
                    p = ph.(field)(j);
                    fprintf('  %s(%d), handle=%g', field, j, p);

                    try
                        line = get_param(p, 'Line');
                        if isnumeric(line) && line > 0
                            fprintf(', line=%g', line);
                        else
                            fprintf(', unconnected');
                        end
                    catch
                    end

                    fprintf('\n');
                end
            end
        end
    catch ME
        fprintf('Inspection warning: %s\n', ME.message);
    end
end

% Report physical sensor and converter library paths.
fprintf('\n=== LIBRARY BLOCK SEARCH ===\n');

libs = {'ee_lib', 'fl_lib', 'nesl_utility'};

for k = 1:numel(libs)
    try
        load_system(libs{k});
        fprintf('\nLibrary loaded: %s\n', libs{k});

        candidates = find_system(libs{k}, ...
            'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', ...
            'Type', 'Block');

        for j = 1:numel(candidates)
            nm = get_param(candidates{j}, 'Name');

            if contains(lower(nm), 'current sensor') || ...
               contains(lower(nm), 'voltage sensor') || ...
               contains(lower(nm), 'ps-simulink converter')
                fprintf('  %s\n', candidates{j});
            end
        end
    catch ME
        fprintf('Could not inspect %s: %s\n', libs{k}, ME.message);
    end
end

fprintf('\n=== END OF READ-ONLY DISCOVERY ===\n');
fprintf('No blocks were added, removed, connected, or saved.\n');
end
