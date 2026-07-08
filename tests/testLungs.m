classdef testLungs < matlab.unittest.TestCase
    % testLungs Tests the Simscape Lungs block under volume command variations.

    properties
        ModelName = 'lungs_test'
        BlockPath = 'lungs_test/Lungs'
        
        % Properties to store simulation results for optional plotting
        V_nom_data
        p_nom_data
        f_nom_data
        
        V_inh_data
        p_inh_data
        f_inh_data
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

            testCase.V_nom_data = ds.get('V_lungs').Values;
            testCase.f_nom_data = ds.get('f').Values;
            testCase.p_nom_data = ds.get('P_lung').Values;
            n_lungs_ts = ds.get('n_lungs').Values;

            % 1. Initial moles must match n_init = 0.104 mol specified in Lungs.ssc
            testCase.verifyEqual(n_lungs_ts.Data(1), 0.104, AbsTol=1e-3);
            
            % 2. Actual volume must match commanded nominal 1.5L
            testCase.verifyEqual(testCase.V_nom_data.Data(1), 1.5e-3, AbsTol=1e-4);

            % 3. Buoyancy force must develop according to volume: f = -rho_water * g * V_lungs
            testCase.verifyEqual(testCase.f_nom_data.Data(1), -15.08, AbsTol=1e-1);
        end

        function testInhalationPressureAndBuoyancyDynamics(testCase)
            % Verify expansion pressure drop and higher buoyancy lifting force during inhalation (3.0L)
            
            % Nominal baseline (1.5L) simulation for comparison
            in_nominal = Simulink.SimulationInput(testCase.ModelName);
            in_nominal = in_nominal.setModelParameter('StopTime', '10');
            in_nominal = in_nominal.setBlockParameter([testCase.ModelName '/ConstantVol'], 'Value', '1.5e-3');
            out_nominal = sim(in_nominal);
            testCase.p_nom_data = out_nominal.logsout.get('P_lung').Values;

            % Expanded inhalation (3.0L) simulation
            in_inhale = Simulink.SimulationInput(testCase.ModelName);
            in_inhale = in_inhale.setModelParameter('StopTime', '10');
            in_inhale = in_inhale.setBlockParameter([testCase.ModelName '/ConstantVol'], 'Value', '3.0e-3');

            out_inhale = sim(in_inhale);
            ds_inhale = out_inhale.logsout;

            testCase.V_inh_data = ds_inhale.get('V_lungs').Values;
            testCase.p_inh_data = ds_inhale.get('P_lung').Values;
            testCase.f_inh_data = ds_inhale.get('f').Values;

            % 1. Verify volume matches commanded 3.0L
            testCase.verifyEqual(testCase.V_inh_data.Data(1), 3.0e-3, AbsTol=1e-4);

            % 2. Verify expansion pressure drop (pressure is lower than nominal volume baseline)
            testCase.verifyLessThan(testCase.p_inh_data.Data(1), testCase.p_nom_data.Data(1));

            % 3. Verify buoyancy lifting force increases proportionally with volume
            testCase.verifyEqual(testCase.f_inh_data.Data(1), -30.16, AbsTol=1e-1);
        end
    end

    methods
        function plotResults(testCase)
            % Plot the already-cached simulation results instantly
            if isempty(testCase.p_nom_data) || isempty(testCase.p_inh_data) || isempty(testCase.f_nom_data) || isempty(testCase.f_inh_data)
                error('No simulation results found. Please run the tests first to populate results!');
            end

            % Create Figure & Plot
            figure('Name', 'Lungs Dynamics Test Results', 'NumberTitle', 'off');
            
            subplot(2, 1, 1);
            plot(testCase.p_nom_data.Time, testCase.p_nom_data.Data / 1e5, 'LineWidth', 1.5, 'Color', [0 0.44 0.74]);
            hold on;
            plot(testCase.p_inh_data.Time, testCase.p_inh_data.Data / 1e5, 'LineWidth', 1.5, 'Color', [0.85 0.33 0.1]);
            grid on;
            title('Lungs Expansion Dynamics');
            ylabel('Pressure (bar)');
            legend('Nominal (1.5L)', 'Inhalation (3.0L)');
            
            subplot(2, 1, 2);
            plot(testCase.f_nom_data.Time, testCase.f_nom_data.Data, 'LineWidth', 1.5, 'Color', [0 0.44 0.74]);
            hold on;
            plot(testCase.f_inh_data.Time, testCase.f_inh_data.Data, 'LineWidth', 1.5, 'Color', [0.85 0.33 0.1]);
            grid on;
            ylabel('Buoyancy Force (N)');
            xlabel('Time (s)');
            legend('Nominal (1.5L)', 'Inhalation (3.0L)');
        end
    end
end
