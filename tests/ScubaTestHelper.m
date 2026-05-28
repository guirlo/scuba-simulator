classdef ScubaTestHelper
    % Shared utilities for scuba buoyancy simulation tests.
    % Provides selective logging setup, input creation, and signal extraction.

    properties (Constant)
        ProjectRoot = 'L:\Projects\scuba';
        ModelName = 'scuba_buoyancy_sim';
        ModelPath = 'L:\Projects\scuba\models\scuba_buoyancy_sim.slx';

        % Block paths
        Tank        = 'scuba_buoyancy_sim/GasCircuit/GasTank';
        FirstStage  = 'scuba_buoyancy_sim/GasCircuit/FirstStageReg';
        SecondStage = 'scuba_buoyancy_sim/GasCircuit/SecondStageReg';
        IPVolume    = 'scuba_buoyancy_sim/GasCircuit/IPVolume';
        Lungs       = 'scuba_buoyancy_sim/GasCircuit/Lungs';
        ExhaleValve = 'scuba_buoyancy_sim/GasCircuit/ExhaleValve';
        BCDInflate  = 'scuba_buoyancy_sim/GasCircuit/BCDInflateValve';
        BCDBladder  = 'scuba_buoyancy_sim/GasCircuit/BCDBladder';
        PurgeValve  = 'scuba_buoyancy_sim/GasCircuit/PurgeValve';
        AmbientRef  = 'scuba_buoyancy_sim/GasCircuit/AmbientRef';
        AmbPress    = 'scuba_buoyancy_sim/Mechanics/AmbientPressure';
        BuoyForce   = 'scuba_buoyancy_sim/Mechanics/BuoyancyForce';
        HydroDrag   = 'scuba_buoyancy_sim/Mechanics/HydroDrag';
        DiverMass   = 'scuba_buoyancy_sim/Mechanics/DiverMass';
    end

    methods (Static)
        function loadModel()
            if isempty(matlab.project.rootProject)
                openProject(ScubaTestHelper.ProjectRoot);
            end
            % Ensure project root is on path (needed for +scuba namespace)
            if ~contains(path, ScubaTestHelper.ProjectRoot)
                addpath(ScubaTestHelper.ProjectRoot);
            end
            libPath = fullfile(ScubaTestHelper.ProjectRoot, 'scuba_lib.slx');
            if ~bdIsLoaded('scuba_lib')
                if ~isfile(libPath)
                    oldDir = cd(ScubaTestHelper.ProjectRoot);
                    sscbuild('scuba');
                    cd(oldDir);
                end
                load_system(libPath);
            end
            if ~bdIsLoaded(ScubaTestHelper.ModelName)
                load_system(ScubaTestHelper.ModelPath);
            end
            params = scuba_params();
            gas = gas_properties(params.tank.gasMix);
            assignin('base', 'params', params);
            assignin('base', 'gas', gas);
        end

        function enableLogging(blockPath, varNames)
            oldDir = cd(ScubaTestHelper.ProjectRoot);
            restoreDir = onCleanup(@() cd(oldDir));
            tbl = simscape.instrumentation.defaultVariableTable(blockPath);
            for i = 1:numel(varNames)
                tbl(varNames(i)).Logging = true;
            end
            simscape.instrumentation.setVariableTable(blockPath, tbl);
        end

        function disableLogging(blockPath)
            oldDir = cd(ScubaTestHelper.ProjectRoot);
            restoreDir = onCleanup(@() cd(oldDir));
            tbl = simscape.instrumentation.getVariableTable(blockPath);
            keys = tbl.keys;
            for i = 1:numel(keys)
                tbl(keys(i)).Logging = false;
            end
            simscape.instrumentation.setVariableTable(blockPath, tbl);
        end

        function disableAllLogging(blockPaths)
            for i = 1:numel(blockPaths)
                try
                    ScubaTestHelper.disableLogging(blockPaths{i});
                catch
                end
            end
        end

        function ds = createInputDataset(simTime, rate, depth, inflate, purge)
            % Create Simulink.SimulationData.Dataset with constant inputs.
            % rate: breathing rate (bpm)
            % depth: breath depth scalar (1=normal)
            % inflate: inflate button (0 or 1)
            % purge: purge button (0 or 1)
            arguments
                simTime (1,1) double
                rate (1,1) double = 15
                depth (1,1) double = 1
                inflate (1,1) double = 0
                purge (1,1) double = 0
            end
            t = [0; simTime];
            ds = Simulink.SimulationData.Dataset;
            ds = ds.addElement(timeseries(rate*ones(2,1), t), 'breathing_rate');
            ds = ds.addElement(timeseries(depth*ones(2,1), t), 'breath_depth');
            ds = ds.addElement(timeseries(inflate*ones(2,1), t), 'inflate_btn');
            ds = ds.addElement(timeseries(purge*ones(2,1), t), 'purge_btn');
        end

        function ds = createProfileDataset(simTime, timeVec, rateVec, depthVec, inflateVec, purgeVec)
            % Create Dataset with time-varying inputs.
            ds = Simulink.SimulationData.Dataset;
            ds = ds.addElement(timeseries(rateVec, timeVec), 'breathing_rate');
            ds = ds.addElement(timeseries(depthVec, timeVec), 'breath_depth');
            ds = ds.addElement(timeseries(inflateVec, timeVec), 'inflate_btn');
            ds = ds.addElement(timeseries(purgeVec, timeVec), 'purge_btn');
        end

        function simIn = configureSimInput(simTime, ds, blockParams)
            % Build SimulationInput with external input and optional block param overrides.
            % blockParams: cell array of {blockPath, paramName, value} triplets
            arguments
                simTime (1,1) double
                ds Simulink.SimulationData.Dataset
                blockParams cell = {}
            end
            simIn = Simulink.SimulationInput(ScubaTestHelper.ModelName);
            simIn = simIn.setModelParameter('StopTime', string(simTime));
            simIn = simIn.setModelParameter('LoadExternalInput', 'on');
            simIn = simIn.setModelParameter('ExternalInput', 'ds');
            simIn = simIn.setModelParameter('SimulationMode', 'normal');

            assignin('base', 'ds', ds);

            for i = 1:size(blockParams, 1)
                simIn = simIn.setBlockParameter(blockParams{i,1}, ...
                    blockParams{i,2}, blockParams{i,3});
            end
        end

        function out = runSim(simIn)
            % Run simulation from the project root directory.
            oldDir = cd(ScubaTestHelper.ProjectRoot);
            restoreDir = onCleanup(@() cd(oldDir));
            out = sim(simIn);
        end

        function ts = getSignal(logsout, name, blockPath)
            % Extract timeseries from logsout by variable name.
            % If blockPath is provided, disambiguates duplicate names.
            % If name matches multiple signals and no blockPath given, returns first.
            arguments
                logsout
                name (1,1) string
                blockPath (1,1) string = ""
            end
            el = logsout.getElement(name);
            if isa(el, 'Simulink.SimulationData.Dataset')
                if blockPath ~= ""
                    for i = 1:el.numElements
                        candidate = el.getElement(i);
                        if contains(string(candidate.BlockPath.getBlock(1)), blockPath)
                            el = candidate;
                            break;
                        end
                    end
                else
                    el = el.getElement(1);
                end
            end
            ts = el.Values;
        end

        function val = getFinalValue(logsout, name)
            ts = ScubaTestHelper.getSignal(logsout, name);
            val = ts.Data(end);
        end

        function val = getInitialValue(logsout, name)
            ts = ScubaTestHelper.getSignal(logsout, name);
            val = ts.Data(1);
        end

        function P = pressureAtDepth(d)
            P = 101325 + 1025 * 9.81 * d;
        end
    end
end
