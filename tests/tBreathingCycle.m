classdef tBreathingCycle < matlab.unittest.TestCase
    % Test 1.5: Lung volume oscillation and molar consumption per breath.

    properties
        LoggedBlocks cell
    end

    methods (TestClassSetup)
        function setupModel(testCase)
            ScubaTestHelper.loadModel();
        end
    end

    methods (TestMethodSetup)
        function enableLogs(testCase)
            ScubaTestHelper.enableLogging(ScubaTestHelper.Lungs, ...
                ["V_lungs", "n_lungs", "n_dot_in", "n_dot_out"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.Tank, ...
                ["n_tank"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.AmbPress, ...
                ["depth"]);
            testCase.LoggedBlocks = {
                ScubaTestHelper.Lungs
                ScubaTestHelper.Tank
                ScubaTestHelper.AmbPress
            };
        end
    end

    methods (TestMethodTeardown)
        function disableLogs(testCase)
            ScubaTestHelper.disableAllLogging(testCase.LoggedBlocks);
        end
    end

    methods (Test)
        function testLungVolumeOscillation(testCase)
            % Test 1.5: Lung volume oscillates with tidal volume determined
            % by regulator flow dynamics (breath_effort amplitude / R_open).
            simTime = 20;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            V_lungs = ScubaTestHelper.getSignal(out.logsout, 'V_lungs');

            % Use stable cycles only (avoid transient and late instability)
            mask = V_lungs.Time > 5 & V_lungs.Time < 18;
            V_data = V_lungs.Data(mask);

            V_peak = max(V_data);
            V_trough = min(V_data);
            V_tidal_measured = V_peak - V_trough;

            % Expected tidal volume from regulator model:
            % Inhale flow = (effort - P_crack)/R_open when effort > P_crack
            % With 200 Pa peak effort, P_crack=100, R_open=6000 -> ~0.1 L at 20m
            testCase.verifyGreaterThan(V_tidal_measured, 0.05e-3, ...
                'Tidal volume should be measurable');
            testCase.verifyLessThan(V_tidal_measured, 0.3e-3, ...
                sprintf('Tidal volume %.4f L exceeds physical expectation', V_tidal_measured*1000));
        end

        function testMolesPerBreath(testCase)
            % Verify moles consumed per breath matches regulator model prediction.
            % Flow integral: integral of (200*sin - 100)/6000 over active period.
            simTime = 20;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            n_tank = ScubaTestHelper.getSignal(out.logsout, 'n_tank');

            % Measure over stable window
            mask = n_tank.Time > 5 & n_tank.Time < 17;
            t_range = n_tank.Time(mask);
            n_range = n_tank.Data(mask);

            total_consumed = n_range(1) - n_range(end);
            duration = t_range(end) - t_range(1);
            breaths_in_window = duration * 15 / 60;
            mol_per_breath = total_consumed / breaths_in_window;

            % Expected from regulator physics:
            % Inhale: T_inh = 0.4*4 = 1.6s, effort = 200*sin(pi*t/1.6)
            % Flow when effort > 100: integral of (200*sin - 100)/6000
            T_inh = 0.4 * 60/15;
            t1 = T_inh/6; t2 = 5*T_inh/6;
            int_sin = T_inh/pi * (cos(pi*t1/T_inh) - cos(pi*t2/T_inh));
            expected_mol_per_breath = (200*int_sin - 100*(t2-t1)) / 6000;

            testCase.verifyEqual(mol_per_breath, expected_mol_per_breath, ...
                'RelTol', 0.25, ...
                sprintf('mol/breath: %.5f vs expected %.5f', ...
                mol_per_breath, expected_mol_per_breath));
        end

        function testBreathingFrequency(testCase)
            % Verify breathing period matches 15 bpm (4.0 s period).
            % Use threshold crossing for robust period measurement.
            simTime = 20;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            V_lungs = ScubaTestHelper.getSignal(out.logsout, 'V_lungs');

            % Use stable cycles only
            mask = V_lungs.Time > 3 & V_lungs.Time < 18;
            t = V_lungs.Time(mask);
            v = V_lungs.Data(mask);

            % Measure period via upward threshold crossings (more robust than peaks)
            mid = (max(v) + min(v)) / 2;
            crossings = [];
            for i = 2:numel(v)
                if v(i-1) < mid && v(i) >= mid
                    frac = (mid - v(i-1)) / (v(i) - v(i-1));
                    crossings(end+1) = t(i-1) + frac*(t(i)-t(i-1)); %#ok<AGROW>
                end
            end

            testCase.assertGreaterThanOrEqual(numel(crossings), 2, ...
                'Not enough crossings detected to measure period');
            periods = diff(crossings);
            avg_period = mean(periods);
            testCase.verifyEqual(avg_period, 4.0, ...
                'RelTol', 0.05, ...
                sprintf('Breathing period %.3f s vs expected 4.0 s', avg_period));
        end

        function testLungVolumePositive(testCase)
            % Lung volume must always be positive (physical constraint).
            simTime = 30;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            V_lungs = ScubaTestHelper.getSignal(out.logsout, 'V_lungs');
            testCase.verifyGreaterThan(min(V_lungs.Data), 0, ...
                'Lung volume must remain positive');
        end
    end
end
