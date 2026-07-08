classdef testTank < matlab.unittest.TestCase
    % testTank Tests the Simscape GasTank block under constant discharge.

    properties
        ModelName = 'tank_test'
        BlockPath = 'tank_test/GasTank'
    end

    methods(TestMethodSetup)
        function loadModelAndConfigureLogging(testCase)
            % Ensure the model is loaded but not open
            load_system(testCase.ModelName);
            testCase.addTeardown(@() close_system(testCase.ModelName, 0));

            % Configure selective logging programmatically using Simscape Instrumentation
            % 1. Get the default variable table for the Gas Tank
            tbl = simscape.instrumentation.defaultVariableTable(testCase.BlockPath);

            % 2. Select variables to log
            % These correspond to the variables defined in GasTank.ssc
            tbl("n_tank").Logging = true;    % Gas moles in tank
            tbl("f").Logging = true;         % Weight force (translational)
            tbl("A.p").Logging = true;       % Port A pressure

            % 3. Apply the modified table to the block
            simscape.instrumentation.setVariableTable(testCase.BlockPath, tbl);
        end
    end

    methods(Test)
        function testTankDischargeDynamics(testCase)
            % Setup SimulationInput
            in = Simulink.SimulationInput(testCase.ModelName);
            in = in.setModelParameter('StopTime', '10'); % 10-second test

            % Run simulation
            out = sim(in);

            % Discover and extract selectively logged data from logsout
            ds = out.logsout;
            
            % Retrieve timeseries for moles (n_tank), pressure (A.p), and weight force (f)
            n_tank_ts = ds.get('n_tank').Values;
            f_ts = ds.get('f').Values;
            p_ts = ds.get('A.p').Values;

            % --- Assertions ---
            % 1. Ensure initial moles match the parameter spec (n_init = 98.47 mol)
            testCase.verifyEqual(n_tank_ts.Data(1), 98.47, AbsTol=1e-3);

            % 2. Verify that moles decrease continuously as gas flows out
            testCase.verifyLessThan(n_tank_ts.Data(end), n_tank_ts.Data(1));

            % 3. Verify that pressure decreases continuously
            testCase.verifyLessThan(p_ts.Data(end), p_ts.Data(1));

            % 4. Verify that the weight force f decreases as the gas leaves
            testCase.verifyLessThan(f_ts.Data(end), f_ts.Data(1));
            
            % 5. Verify weight force is directly proportional to moles
            % f == n_tank * M_gas * gravity
            % Since M_gas = 0.029, gravity = 9.80665: ratio should be constant
            expected_ratio = 0.029 * 9.80665;
            actual_ratio = f_ts.Data ./ n_tank_ts.Data;
            testCase.verifyEqual(actual_ratio, repmat(expected_ratio, size(actual_ratio)), AbsTol=1e-2);
        end
    end
end
