classdef tBCDInflateDeflate < matlab.unittest.TestCase
    % Test 1.6: BCD responds correctly to inflate and purge commands.

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
            ScubaTestHelper.enableLogging(ScubaTestHelper.BCDBladder, ...
                ["V_bcd", "n_bcd", "n_dot_in"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.AmbPress, ...
                ["depth"]);
            testCase.LoggedBlocks = {
                ScubaTestHelper.BCDBladder
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
        function testInflateIncreasesVolume(testCase)
            % Phase A: inflate ON for 5s -> V_bcd should increase.
            simTime = 20;
            t = [0; 4.99; 5; 10; 10.01; 20];
            inflateVec = [0; 0; 1; 1; 0; 0];
            purgeVec = zeros(size(t));
            rateVec = 15 * ones(size(t));
            depthVec = ones(size(t));

            ds = ScubaTestHelper.createProfileDataset(simTime, t, ...
                rateVec, depthVec, inflateVec, purgeVec);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            V_bcd = ScubaTestHelper.getSignal(out.logsout, 'V_bcd');

            % Volume at end of inflate phase should exceed initial
            mask_before = V_bcd.Time < 5;
            mask_after = V_bcd.Time > 10 & V_bcd.Time < 11;
            V_before = mean(V_bcd.Data(mask_before));
            V_after = mean(V_bcd.Data(mask_after));

            testCase.verifyGreaterThan(V_after, V_before, ...
                'BCD volume should increase after inflate');
        end

        function testPurgeDecreasesVolume(testCase)
            % Inflate first, then purge -> n_bcd should decrease.
            % Note: V_bcd may remain at V_max if still overfull, so we
            % verify moles removed rather than volume directly.
            simTime = 25;
            t = [0; 2; 2.01; 7; 7.01; 12; 12.01; 17; 17.01; 25];
            inflateVec = [0; 0; 1; 1; 0; 0; 0; 0; 0; 0];
            purgeVec   = [0; 0; 0; 0; 0; 0; 1; 1; 0; 0];
            rateVec = 15 * ones(size(t));
            depthVec = ones(size(t));

            ds = ScubaTestHelper.createProfileDataset(simTime, t, ...
                rateVec, depthVec, inflateVec, purgeVec);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            n_bcd = ScubaTestHelper.getSignal(out.logsout, 'n_bcd');

            % Moles before purge vs after purge
            mask_before_purge = n_bcd.Time > 10 & n_bcd.Time < 12;
            mask_after_purge = n_bcd.Time > 18 & n_bcd.Time < 20;
            n_before = mean(n_bcd.Data(mask_before_purge));
            n_after = mean(n_bcd.Data(mask_after_purge));

            testCase.verifyLessThan(n_after, n_before, ...
                'BCD moles should decrease after purge');
        end

        function testHoldPhaseConstant(testCase)
            % After inflate, volume should remain approximately constant.
            simTime = 20;
            t = [0; 1; 1.01; 4; 4.01; 20];
            inflateVec = [0; 0; 1; 1; 0; 0];
            purgeVec = zeros(size(t));
            rateVec = 15 * ones(size(t));
            depthVec = ones(size(t));

            ds = ScubaTestHelper.createProfileDataset(simTime, t, ...
                rateVec, depthVec, inflateVec, purgeVec);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            V_bcd = ScubaTestHelper.getSignal(out.logsout, 'V_bcd');

            % Check hold phase (t=6 to t=18) is stable
            % Note: depth may drift slightly changing BCD volume
            mask_hold = V_bcd.Time > 6 & V_bcd.Time < 18;
            V_hold = V_bcd.Data(mask_hold);

            if ~isempty(V_hold)
                relative_variation = (max(V_hold) - min(V_hold)) / mean(V_hold);
                testCase.verifyLessThan(relative_variation, 0.05, ...
                    sprintf('BCD volume variation %.1f%% during hold exceeds 5%%', ...
                    relative_variation*100));
            end
        end

        function testVolumeNeverExceedsMax(testCase)
            % Prolonged inflation should not exceed V_max = 15 L.
            simTime = 60;
            t = [0; 1; 1.01; 60];
            inflateVec = [0; 0; 1; 1];
            purgeVec = zeros(size(t));
            rateVec = 15 * ones(size(t));
            depthVec = ones(size(t));

            ds = ScubaTestHelper.createProfileDataset(simTime, t, ...
                rateVec, depthVec, inflateVec, purgeVec);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            V_bcd = ScubaTestHelper.getSignal(out.logsout, 'V_bcd');

            V_max = 0.015; % 15 L in m^3
            testCase.verifyLessThanOrEqual(max(V_bcd.Data), V_max + 1e-5, ...
                sprintf('BCD volume %.4f L exceeds max 15 L', max(V_bcd.Data)*1000));
        end

        function testInflateMonotonic(testCase)
            % During active inflation, volume should increase monotonically.
            simTime = 10;
            t = [0; 0.5; 0.51; 10];
            inflateVec = [0; 0; 1; 1];
            purgeVec = zeros(size(t));
            rateVec = 15 * ones(size(t));
            depthVec = ones(size(t));

            ds = ScubaTestHelper.createProfileDataset(simTime, t, ...
                rateVec, depthVec, inflateVec, purgeVec);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            V_bcd = ScubaTestHelper.getSignal(out.logsout, 'V_bcd');

            % Check monotonicity during inflation (t > 1s to skip transient)
            mask = V_bcd.Time > 1 & V_bcd.Time < 9;
            V_inflate = V_bcd.Data(mask);

            % Allow small numerical noise
            dV = diff(V_inflate);
            testCase.verifyGreaterThanOrEqual(min(dV), -1e-7, ...
                'BCD volume should not decrease during active inflation');
        end
    end
end
