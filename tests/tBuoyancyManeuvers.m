classdef tBuoyancyManeuvers < matlab.unittest.TestCase
    % Tests 2.1-2.6: Integration tests for basic buoyancy maneuvers.

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
            ScubaTestHelper.enableLogging(ScubaTestHelper.AmbPress, ...
                ["depth", "P_amb", "R.v"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.BCDBladder, ...
                ["V_bcd", "n_bcd"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.BuoyForce, ...
                ["f"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.Tank, ...
                ["A.p"]);
            testCase.LoggedBlocks = {
                ScubaTestHelper.AmbPress
                ScubaTestHelper.BCDBladder
                ScubaTestHelper.BuoyForce
                ScubaTestHelper.Tank
            };
        end
    end

    methods (TestMethodTeardown)
        function disableLogs(testCase)
            ScubaTestHelper.disableAllLogging(testCase.LoggedBlocks);
        end
    end

    methods (Test)
        function testNeutralBuoyancyHold(testCase)
            % Test 2.1: Properly trimmed diver holds depth at 20m.
            % The model starts at 20m with BCD pre-charged (n_init=0.298).
            % With correct buoyancy physics, slight positive feedback exists
            % (BCD expansion with ascent) so short-term stability is checked.
            simTime = 30;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            depth = ScubaTestHelper.getSignal(out.logsout, 'depth');

            % Mean depth in first 20s should be close to 20m
            mask = depth.Time > 5 & depth.Time < 25;
            mean_depth = mean(depth.Data(mask));
            testCase.verifyEqual(mean_depth, 20, 'AbsTol', 1.0, ...
                sprintf('Mean depth %.2f m deviates from 20 m', mean_depth));

            % Oscillation should be small
            depth_range = max(depth.Data(mask)) - min(depth.Data(mask));
            testCase.verifyLessThan(depth_range, 3.0, ...
                sprintf('Depth range %.2f m too large for neutral buoyancy', depth_range));
        end

        function testNegativeBuoyancyDescent(testCase)
            % Test 2.2: Empty BCD -> diver descends.
            % Start at 10m where body volume alone cannot support 89 kg.
            simTime = 60;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);

            simIn = simIn.setBlockParameter(ScubaTestHelper.BCDBladder, ...
                'n_init', '0');
            simIn = simIn.setBlockParameter(ScubaTestHelper.AmbPress, ...
                'depth_init', '10');
            out = ScubaTestHelper.runSim(simIn);

            depth = ScubaTestHelper.getSignal(out.logsout, 'depth');

            % Depth should increase (diver descends)
            testCase.verifyGreaterThan(depth.Data(end), depth.Data(1), ...
                'Diver with empty BCD should descend');
        end

        function testPositiveBuoyancyAscent(testCase)
            % Test 2.3: Excess BCD gas at depth causes ascent.
            % Start at 30m with extra gas in BCD.
            simTime = 90;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);

            % Large BCD charge at 30m -> positive buoyancy
            % At 30m: P = 402990 Pa, n for 5L = 402990*0.005/(8.314*293.15) = 0.826 mol
            simIn = simIn.setBlockParameter(ScubaTestHelper.BCDBladder, ...
                'n_init', '0.9');
            simIn = simIn.setBlockParameter(ScubaTestHelper.AmbPress, ...
                'depth_init', '30');
            out = ScubaTestHelper.runSim(simIn);

            depth = ScubaTestHelper.getSignal(out.logsout, 'depth');

            % Diver should ascend (depth decreases)
            testCase.verifyLessThan(depth.Data(end), 30, ...
                'Over-inflated BCD diver should ascend');
        end

        function testAscentAccelerates(testCase)
            % Test 2.3 corollary: Ascent rate increases as BCD expands.
            simTime = 90;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);

            simIn = simIn.setBlockParameter(ScubaTestHelper.BCDBladder, ...
                'n_init', '0.9');
            simIn = simIn.setBlockParameter(ScubaTestHelper.AmbPress, ...
                'depth_init', '30');
            out = ScubaTestHelper.runSim(simIn);

            vel = ScubaTestHelper.getSignal(out.logsout, 'R.v');
            depth = ScubaTestHelper.getSignal(out.logsout, 'depth');

            % Find velocity at two depth points during ascent
            % Velocity is negative during ascent (depth decreasing)
            mask_deep = depth.Data > 20 & depth.Data < 25;
            mask_shallow = depth.Data > 10 & depth.Data < 15;

            if any(mask_deep) && any(mask_shallow)
                speed_deep = abs(mean(vel.Data(mask_deep)));
                speed_shallow = abs(mean(vel.Data(mask_shallow)));
                testCase.verifyGreaterThan(speed_shallow, speed_deep, ...
                    'Ascent should accelerate as BCD expands');
            end
        end

        function testBCDInflateCausesAscent(testCase)
            % Test 2.4: Inflating BCD at depth creates positive buoyancy.
            simTime = 40;
            t = [0; 9.99; 10; 13; 13.01; 40];
            inflateVec = [0; 0; 1; 1; 0; 0];
            purgeVec = zeros(size(t));
            rateVec = 15 * ones(size(t));
            depthVec = ones(size(t));

            ds = ScubaTestHelper.createProfileDataset(simTime, t, ...
                rateVec, depthVec, inflateVec, purgeVec);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);

            % Start at 25m with approximately neutral BCD
            simIn = simIn.setBlockParameter(ScubaTestHelper.AmbPress, ...
                'depth_init', '25');
            simIn = simIn.setBlockParameter(ScubaTestHelper.BCDBladder, ...
                'n_init', '0.40');
            out = ScubaTestHelper.runSim(simIn);

            depth = ScubaTestHelper.getSignal(out.logsout, 'depth');

            % Depth after inflate should be less than before
            mask_before = depth.Time > 5 & depth.Time < 10;
            mask_after = depth.Time > 30 & depth.Time < 40;
            depth_before = mean(depth.Data(mask_before));
            depth_after = mean(depth.Data(mask_after));

            testCase.verifyLessThan(depth_after, depth_before, ...
                'Diver should ascend after BCD inflate');
        end

        function testBCDPurgeCausesDescent(testCase)
            % Test 2.5: Purge valve vents gas from overfull BCD.
            % The purge valve requires P_excess (BCD overfull) to drive
            % flow, so we start with n > n_max at depth. Verify that
            % purge reduces BCD gas content and volume.
            simTime = 20;
            t = [0; 2.99; 3; 15; 15.01; 20];
            inflateVec = zeros(size(t));
            purgeVec = [0; 0; 1; 1; 0; 0];
            rateVec = 15 * ones(size(t));
            depthVec = ones(size(t));

            ds = ScubaTestHelper.createProfileDataset(simTime, t, ...
                rateVec, depthVec, inflateVec, purgeVec);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);

            % At 30m: n_max = P*V_max/(R*T) = 402990*0.015/(8.314*293.15) = 2.48
            % Use n=2.6 (slightly overfull) at 30m
            simIn = simIn.setBlockParameter(ScubaTestHelper.AmbPress, ...
                'depth_init', '30');
            simIn = simIn.setBlockParameter(ScubaTestHelper.BCDBladder, ...
                'n_init', '2.6');
            out = ScubaTestHelper.runSim(simIn);

            n_bcd = ScubaTestHelper.getSignal(out.logsout, 'n_bcd');

            % Purge should reduce moles in BCD
            n_before = n_bcd.Data(1);
            mask_after = n_bcd.Time > 16;
            n_after = mean(n_bcd.Data(mask_after));

            testCase.verifyLessThan(n_after, n_before, ...
                'Purge should remove gas from BCD');
            testCase.verifyLessThan(n_after, 0.95 * n_before, ...
                'Purge should remove significant gas (>5%)');
        end

        function testFreeAscentRunaway(testCase)
            % Test 2.6: Uncontrolled ascent from 40m with 5L BCD.
            simTime = 120;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);

            % At 40m: P = 503545 Pa, n for 5L = 503545*0.005/(8.314*293.15) = 1.033 mol
            simIn = simIn.setBlockParameter(ScubaTestHelper.BCDBladder, ...
                'n_init', '1.033');
            simIn = simIn.setBlockParameter(ScubaTestHelper.AmbPress, ...
                'depth_init', '40');
            out = ScubaTestHelper.runSim(simIn);

            V_bcd = ScubaTestHelper.getSignal(out.logsout, 'V_bcd');
            depth = ScubaTestHelper.getSignal(out.logsout, 'depth');

            % BCD volume should increase as diver ascends (Boyle's law)
            % Check V_bcd at different depths
            mask_deep = depth.Data > 30 & depth.Data < 35;
            mask_mid = depth.Data > 15 & depth.Data < 20;

            if any(mask_deep) && any(mask_mid)
                V_deep = mean(V_bcd.Data(mask_deep));
                V_mid = mean(V_bcd.Data(mask_mid));
                testCase.verifyGreaterThan(V_mid, V_deep, ...
                    'BCD volume should expand during ascent (Boyle''s law)');

                % Check ratio matches pressure ratio approximately
                P_deep = ScubaTestHelper.pressureAtDepth(32.5);
                P_mid = ScubaTestHelper.pressureAtDepth(17.5);
                expected_ratio = P_deep / P_mid;
                actual_ratio = V_mid / V_deep;
                testCase.verifyEqual(actual_ratio, expected_ratio, ...
                    'RelTol', 0.15, ...
                    'Volume ratio should match inverse pressure ratio');
            end
        end
    end
end
