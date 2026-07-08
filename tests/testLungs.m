classdef testLungs < matlab.unittest.TestCase
    % testLungs Tests the Simscape Lungs block under volume command variations.

    properties
        ModelName = 'lungs_test'
        BlockPath = 'lungs_test/Lungs'
    end

    methods(TestMethodSetup)
        function loadModelAndConfigureLogging(testCase)
            % Ensure the model is loaded but not open
            load_system(testCase.ModelName);
            testCase.addTeardown(@() close_system(testCase.ModelName, 0));

            % Configure selective logging programmatically
            tbl = simscape.instrumentation.defaultVariableTable(testCase.BlockPath);
            tbl("V_lungs").Logging = true;
            tbl("P_lung").Logging = true;
            tbl("f").Logging = true;
            tbl("n_lungs").Logging = true;
            simscape.instrumentation.setVariableTable(testCase.BlockPath, tbl);
        end
    end

    methods(Test)
        function testNominalLungsState(testCase)
            % Verify the initial physical state under nominal lung volume of 1.5L
            in = Simulink.SimulationInput(testCase.ModelName);
            in = in.setModelParameter('StopTime', '10');
            in = in.setBlockParameter([testCase.ModelName '/ConstantVol'], 'Value', '1.5e-3');

            % Run simulation
            out = sim(in);
            ds = out.logsout;

            V_lungs_ts = ds.get('V_lungs').Values;
            f_ts = ds.get('f').Values;
            n_lungs_ts = ds.get('n_lungs').Values;

            % 1. Initial moles must match n_init = 0.104 mol specified in Lungs.ssc
            testCase.verifyEqual(n_lungs_ts.Data(1), 0.104, AbsTol=1e-3);
            
            % 2. Actual volume must match commanded nominal 1.5L
            testCase.verifyEqual(V_lungs_ts.Data(1), 1.5e-3, AbsTol=1e-4);

            % 3. Buoyancy force must develop according to volume: f = -rho_water * g * V_lungs
            testCase.verifyEqual(f_ts.Data(1), -15.08, AbsTol=1e-1);
        end

        function testInhalationPressureAndBuoyancyDynamics(testCase)
            % Verify expansion pressure drop and higher buoyancy lifting force during inhalation (3.0L)
            
            % Nominal baseline (1.5L) simulation for comparison
            in_nominal = Simulink.SimulationInput(testCase.ModelName);
            in_nominal = in_nominal.setModelParameter('StopTime', '10');
            in_nominal = in_nominal.setBlockParameter([testCase.ModelName '/ConstantVol'], 'Value', '1.5e-3');
            out_nominal = sim(in_nominal);
            P_nominal_ts = out_nominal.logsout.get('P_lung').Values;

            % Expanded inhalation (3.0L) simulation
            in_inhale = Simulink.SimulationInput(testCase.ModelName);
            in_inhale = in_inhale.setModelParameter('StopTime', '10');
            in_inhale = in_inhale.setBlockParameter([testCase.ModelName '/ConstantVol'], 'Value', '3.0e-3');

            out_inhale = sim(in_inhale);
            ds_inhale = out_inhale.logsout;

            V_inhale = ds_inhale.get('V_lungs').Values;
            P_inhale = ds_inhale.get('P_lung').Values;
            f_inhale = ds_inhale.get('f').Values;

            % 1. Verify volume matches commanded 3.0L
            testCase.verifyEqual(V_inhale.Data(1), 3.0e-3, AbsTol=1e-4);

            % 2. Verify expansion pressure drop (pressure is lower than nominal volume baseline)
            testCase.verifyLessThan(P_inhale.Data(1), P_nominal_ts.Data(1));

            % 3. Verify buoyancy lifting force increases proportionally with volume
            testCase.verifyEqual(f_inhale.Data(1), -30.16, AbsTol=1e-1);
        end
    end

    methods
        function plotResults(testCase)
            % Optional helper to simulate and plot Lungs behavior visually
            load_system(testCase.ModelName);
            
            % 1. Simulate Nominal (1.5L)
            in_nom = Simulink.SimulationInput(testCase.ModelName);
            in_nom = in_nom.setModelParameter('StopTime', '5');
            in_nom = in_nom.setBlockParameter([testCase.ModelName '/ConstantVol'], 'Value', '1.5e-3');
            out_nom = sim(in_nom);
            ds_nom = out_nom.logsout;
            
            % 2. Simulate Inhalation (3.0L)
            in_inh = Simulink.SimulationInput(testCase.ModelName);
            in_inh = in_inh.setModelParameter('StopTime', '5');
            in_inh = in_inh.setBlockParameter([testCase.ModelName '/ConstantVol'], 'Value', '3.0e-3');
            out_inh = sim(in_inh);
            ds_inh = out_inh.logsout;
            
            p_nom = ds_nom.get('P_lung').Values;
            f_nom = ds_nom.get('f').Values;
            
            p_inh = ds_inh.get('P_lung').Values;
            f_inh = ds_inh.get('f').Values;

            % 3. Create Figure & Plot
            figure('Name', 'Lungs Dynamics Test Results', 'NumberTitle', 'off');
            
            subplot(2, 1, 1);
            plot(p_nom.Time, p_nom.Data / 1e5, 'LineWidth', 1.5, 'Color', [0 0.44 0.74]);
            hold on;
            plot(p_inh.Time, p_inh.Data / 1e5, 'LineWidth', 1.5, 'Color', [0.85 0.33 0.1]);
            grid on;
            title('Lungs Expansion Dynamics');
            ylabel('Pressure (bar)');
            legend('Nominal (1.5L)', 'Inhalation (3.0L)');
            
            subplot(2, 1, 2);
            plot(f_nom.Time, f_nom.Data, 'LineWidth', 1.5, 'Color', [0 0.44 0.74]);
            hold on;
            plot(f_inh.Time, f_inh.Data, 'LineWidth', 1.5, 'Color', [0.85 0.33 0.1]);
            grid on;
            ylabel('Buoyancy Force (N)');
            xlabel('Time (s)');
            legend('Nominal (1.5L)', 'Inhalation (3.0L)');
            
            close_system(testCase.ModelName, 0);
        end
    end
end
