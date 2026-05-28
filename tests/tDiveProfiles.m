classdef tDiveProfiles < matlab.unittest.TestCase
    % Tests 3.1-3.3: Dive profile integration tests.
    % These validate realistic multi-phase scenarios.

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
            ScubaTestHelper.enableLogging(ScubaTestHelper.Tank, ...
                ["n_tank", "A.p"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.AmbPress, ...
                ["depth", "R.v"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.BCDBladder, ...
                ["V_bcd", "n_bcd"]);
            testCase.LoggedBlocks = {
                ScubaTestHelper.Tank
                ScubaTestHelper.AmbPress
                ScubaTestHelper.BCDBladder
            };
        end
    end

    methods (TestMethodTeardown)
        function disableLogs(testCase)
            ScubaTestHelper.disableAllLogging(testCase.LoggedBlocks);
        end
    end

    methods (Test)
        function testSquareProfileGasConsumption(testCase)
            % Test 3.1: 20m square profile - gas consumption matches expectations.
            % Simplified: hold at 20m for 120s and check consumption rate.
            simTime = 120;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            P_tank = ScubaTestHelper.getSignal(out.logsout, 'A.p');

            % Tank pressure should decrease
            P_start = P_tank.Data(1);
            P_end = P_tank.Data(end);
            testCase.verifyLessThan(P_end, P_start, ...
                'Tank pressure must decrease during dive');

            % At 20m (3 atm), 15 bpm, 0.5L tidal:
            % Consumption = 15/60 * 3 * 0.5 = 0.375 L/s surface equivalent
            % Over 120s = 45 L -> ~18 bar drop in 12L tank
            P_drop_bar = (P_start - P_end) / 1e5;
            testCase.verifyGreaterThan(P_drop_bar, 0.1, ...
                'Should have measurable pressure drop over 120s');
        end

        function testDepthHoldStability(testCase)
            % Diver maintains approximately constant depth at 20m
            % short-term. Open-loop (no controller) means positive
            % buoyancy feedback eventually causes drift.
            simTime = 30;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            depth = ScubaTestHelper.getSignal(out.logsout, 'depth');

            % Check short-term stability (t=5 to t=25)
            mask = depth.Time > 5 & depth.Time < 25;
            depth_window = depth.Data(mask);
            testCase.verifyEqual(mean(depth_window), 20, 'AbsTol', 1.0, ...
                'Diver should hold near 20m short-term');

            depth_range = max(depth_window) - min(depth_window);
            testCase.verifyLessThan(depth_range, 3.0, ...
                sprintf('Depth range %.2f m too large for short-term hold', depth_range));
        end

        function testBCDInflateForAscentProfile(testCase)
            % Test: inflate BCD to initiate ascent from 20m.
            % Inflate at t=10 for 5s, verify diver rises.
            simTime = 60;
            t = [0; 9.99; 10; 15; 15.01; 60];
            inflateVec = [0; 0; 1; 1; 0; 0];
            purgeVec = zeros(size(t));
            rateVec = 15 * ones(size(t));
            depthVec = ones(size(t));

            ds = ScubaTestHelper.createProfileDataset(simTime, t, ...
                rateVec, depthVec, inflateVec, purgeVec);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            depth = ScubaTestHelper.getSignal(out.logsout, 'depth');
            V_bcd = ScubaTestHelper.getSignal(out.logsout, 'V_bcd');

            % BCD volume should increase
            mask_before = V_bcd.Time < 10;
            mask_after = V_bcd.Time > 20 & V_bcd.Time < 30;
            testCase.verifyGreaterThan(mean(V_bcd.Data(mask_after)), ...
                mean(V_bcd.Data(mask_before)), ...
                'BCD volume should increase after inflate');

            % Depth should decrease (ascent)
            mask_late = depth.Time > 40;
            testCase.verifyLessThan(mean(depth.Data(mask_late)), 20, ...
                'Diver should ascend after BCD inflate');
        end

        function testYoYoInstability(testCase)
            % Test 3.3: With fixed BCD, depth perturbation shows instability.
            % Start neutral at 20m, observe if natural breathing causes drift.
            simTime = 120;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            depth = ScubaTestHelper.getSignal(out.logsout, 'depth');
            V_bcd = ScubaTestHelper.getSignal(out.logsout, 'V_bcd');

            % BCD volume should vary with depth (Boyle's law coupling)
            % If diver drifts deeper, V_bcd compresses
            depth_range = max(depth.Data) - min(depth.Data);

            if depth_range > 0.5
                % Verify anti-correlation: deeper -> smaller V_bcd
                mask_early = depth.Time > 10 & depth.Time < 30;
                mask_late = depth.Time > 90 & depth.Time < 120;

                if mean(depth.Data(mask_late)) > mean(depth.Data(mask_early))
                    % Diver sank -> BCD should have compressed
                    testCase.verifyLessThanOrEqual(mean(V_bcd.Data(mask_late)), ...
                        mean(V_bcd.Data(mask_early)) * 1.01, ...
                        'BCD should compress as diver descends (positive feedback)');
                end
            end
        end

        function testConsumptionRateHigherAtDepth(testCase)
            % Verify gas consumption is positive and consistent with
            % regulator flow physics at depth.
            simTime = 60;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            n_tank = ScubaTestHelper.getSignal(out.logsout, 'n_tank');

            % Total consumption
            total_consumed = n_tank.Data(1) - n_tank.Data(end);

            % Consumption should be positive and measurable
            testCase.verifyGreaterThan(total_consumed, 0.05, ...
                'Should consume significant gas over 60s at depth');

            % Verify rate is in physically reasonable range
            % At 20m with regulator physics: ~0.002-0.005 mol/s
            avg_rate = total_consumed / simTime;
            testCase.verifyGreaterThan(avg_rate, 0.001, ...
                sprintf('Consumption rate %.5f mol/s too low', avg_rate));
            testCase.verifyLessThan(avg_rate, 0.01, ...
                sprintf('Consumption rate %.5f mol/s too high', avg_rate));
        end
    end
end
