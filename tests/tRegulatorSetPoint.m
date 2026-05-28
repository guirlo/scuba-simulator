classdef tRegulatorSetPoint < matlab.unittest.TestCase
    % Tests 1.3 and 1.4: First stage regulator set point and second stage demand valve.

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
            ScubaTestHelper.enableLogging(ScubaTestHelper.FirstStage, ...
                ["A.p", "B.p", "P_amb", "n_dot"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.SecondStage, ...
                ["A.p", "B.p", "P_amb", "n_dot"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.AmbPress, ...
                ["depth", "P_amb"]);
            testCase.LoggedBlocks = {
                ScubaTestHelper.FirstStage
                ScubaTestHelper.SecondStage
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
        function testFirstStageSetPoint(testCase)
            % Test 1.3: 1st stage maintains outlet at P_amb + 10 bar.
            % Run at default 20m depth and check IP pressure.
            simTime = 30;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            P_IP = ScubaTestHelper.getSignal(out.logsout, 'B.p', 'FirstStageReg');
            P_amb = ScubaTestHelper.getSignal(out.logsout, 'P_amb', 'FirstStageReg');

            % Check at steady state (after 5s)
            mask = P_IP.Time > 5;
            P_IP_ss = P_IP.Data(mask);
            P_amb_ss = P_amb.Data(mask);

            IP_offset = 10e5; % 10 bar
            P_IP_expected = P_amb_ss + IP_offset;

            % IP should track P_amb + 10 bar within 0.5 bar
            max_err = max(abs(P_IP_ss - P_IP_expected));
            testCase.verifyLessThan(max_err, 0.5e5, ...
                sprintf('IP set point error %.2f bar exceeds 0.5 bar', max_err/1e5));
        end

        function testFirstStageTracksAmbient(testCase)
            % IP should be referenced to ambient (depth-dependent).
            % At 20m: P_amb ~ 302 kPa, so IP ~ 1302 kPa.
            simTime = 10;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            P_IP = ScubaTestHelper.getSignal(out.logsout, 'B.p', 'FirstStageReg');
            depth = ScubaTestHelper.getSignal(out.logsout, 'depth');

            % Check after settling (t > 2s)
            mask = P_IP.Time > 2;
            avg_P_IP = mean(P_IP.Data(mask));
            avg_depth = mean(depth.Data(mask));
            P_amb_expected = ScubaTestHelper.pressureAtDepth(avg_depth);
            P_IP_expected = P_amb_expected + 10e5;

            testCase.verifyEqual(avg_P_IP, P_IP_expected, ...
                'RelTol', 0.02, ...
                'IP should be P_amb + 10 bar at depth');
        end

        function testSecondStageDemandValve(testCase)
            % Test 1.4: 2nd stage only flows when downstream demand exceeds P_crack.
            % During breathing pauses, flow should be near zero.
            % During inhale, flow should be positive.
            simTime = 20;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            n_dot_2nd = ScubaTestHelper.getSignal(out.logsout, 'n_dot', 'SecondStageReg');

            % Flow should always be non-negative (2nd stage only delivers)
            testCase.verifyGreaterThanOrEqual(min(n_dot_2nd.Data), -1e-8, ...
                'Second stage should not allow reverse flow');

            % Flow should have peaks (during inhale) and valleys (during pause/exhale)
            testCase.verifyGreaterThan(max(n_dot_2nd.Data), 0.01, ...
                'Second stage should deliver flow during inhale');
        end

        function testSecondStageFlowRate(testCase)
            % Verify flow magnitude is consistent with demand/R_open formulation.
            % At 20m with 200 Pa effort: demand = 200 Pa, flow = (200-100)/6000 mol/s
            simTime = 20;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            n_dot = ScubaTestHelper.getSignal(out.logsout, 'n_dot', 'SecondStageReg');

            % Expected peak flow: (peak_effort - P_crack) / R_open
            % peak_effort ~ 200 Pa (half-sine), P_crack = 100, R_open = 6000
            expected_peak = (200 - 100) / 6000; % ~ 0.0167 mol/s
            actual_peak = max(n_dot.Data);

            testCase.verifyEqual(actual_peak, expected_peak, ...
                'RelTol', 0.3, ...
                'Peak flow should match demand/R_open within 30%');
        end
    end
end
