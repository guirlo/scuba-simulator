classdef tBreathingControl < matlab.unittest.TestCase
    % Tests for breathing-based depth control (inner loop).
    % Validates that breath_bias modulates the breathing waveform
    % asymmetrically and provides fine-trim depth control.

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
                ["V_lungs", "n_lungs"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.AmbPress, ...
                ["depth", "R.v"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.BCDBladder, ...
                ["V_bcd", "n_bcd"]);
            testCase.LoggedBlocks = {
                ScubaTestHelper.Lungs
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
        function testZeroBiasSymmetric(testCase)
            % With auto_depth=0 (manual), breathing is symmetric.
            % Inhale and exhale peak amplitudes should be equal.
            simTime = 20;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            V_lungs = ScubaTestHelper.getSignal(out.logsout, 'V_lungs');
            mask = V_lungs.Time > 5 & V_lungs.Time < 18;
            V = V_lungs.Data(mask);

            V_mean = mean(V);
            V_max = max(V);
            V_min = min(V);

            % Symmetric breathing: excursions above and below mean are similar
            up_excursion = V_max - V_mean;
            down_excursion = V_mean - V_min;
            ratio = up_excursion / down_excursion;

            testCase.verifyEqual(ratio, 1.0, 'RelTol', 0.3, ...
                sprintf('Breathing asymmetry ratio %.2f (expect ~1.0 for zero bias)', ratio));
        end

        function testPositiveBiasIncreasesLungMoles(testCase)
            % With positive depth error (too deep), auto mode activates
            % positive breath_bias -> peak lung moles per cycle increase.
            % Compare peak moles in the FIRST breath cycle (before drift).
            simTime = 8;

            % Auto mode, target 18m but start at 20m -> error = +2m -> positive bias
            t = [0; simTime];
            ds = Simulink.SimulationData.Dataset;
            ds = ds.addElement(timeseries(15*ones(2,1), t), 'breathing_rate');
            ds = ds.addElement(timeseries(ones(2,1), t), 'breath_depth');
            ds = ds.addElement(timeseries(zeros(2,1), t), 'inflate_btn');
            ds = ds.addElement(timeseries(zeros(2,1), t), 'purge_btn');
            ds = ds.addElement(timeseries([18;18], t), 'depth_target');
            ds = ds.addElement(timeseries([1;1], t), 'auto_depth');

            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out_biased = ScubaTestHelper.runSim(simIn);

            % Manual mode (no bias) for comparison
            ds_manual = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn_manual = ScubaTestHelper.configureSimInput(simTime, ds_manual);
            out_neutral = ScubaTestHelper.runSim(simIn_manual);

            % Compare peak lung moles in the first breath cycle (0.5-4.5s)
            n_biased = ScubaTestHelper.getSignal(out_biased.logsout, 'n_lungs');
            n_neutral = ScubaTestHelper.getSignal(out_neutral.logsout, 'n_lungs');

            mask_b = n_biased.Time > 0.5 & n_biased.Time < 4.5;
            mask_n = n_neutral.Time > 0.5 & n_neutral.Time < 4.5;

            peak_biased = max(n_biased.Data(mask_b));
            peak_neutral = max(n_neutral.Data(mask_n));

            testCase.verifyGreaterThan(peak_biased, peak_neutral, ...
                sprintf('Positive bias should increase peak lung moles (biased=%.5f, neutral=%.5f)', ...
                peak_biased, peak_neutral));
        end

        function testNegativeBiasDecreasesLungMoles(testCase)
            % With negative depth error (too shallow), auto mode activates
            % negative breath_bias -> time-averaged lung moles decrease.
            simTime = 20;

            % Auto mode, target 22m but start at 20m -> error = -2m -> negative bias
            t = [0; simTime];
            ds = Simulink.SimulationData.Dataset;
            ds = ds.addElement(timeseries(15*ones(2,1), t), 'breathing_rate');
            ds = ds.addElement(timeseries(ones(2,1), t), 'breath_depth');
            ds = ds.addElement(timeseries(zeros(2,1), t), 'inflate_btn');
            ds = ds.addElement(timeseries(zeros(2,1), t), 'purge_btn');
            ds = ds.addElement(timeseries([22;22], t), 'depth_target');
            ds = ds.addElement(timeseries([1;1], t), 'auto_depth');

            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out_biased = ScubaTestHelper.runSim(simIn);

            % Manual mode comparison
            ds_manual = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn_manual = ScubaTestHelper.configureSimInput(simTime, ds_manual);
            out_neutral = ScubaTestHelper.runSim(simIn_manual);

            n_biased = ScubaTestHelper.getSignal(out_biased.logsout, 'n_lungs');
            n_neutral = ScubaTestHelper.getSignal(out_neutral.logsout, 'n_lungs');

            mask_b = n_biased.Time > 5 & n_biased.Time < 15;
            mask_n = n_neutral.Time > 5 & n_neutral.Time < 15;

            mean_biased = mean(n_biased.Data(mask_b));
            mean_neutral = mean(n_neutral.Data(mask_n));

            testCase.verifyLessThan(mean_biased, mean_neutral, ...
                sprintf('Negative bias should decrease lung moles (biased=%.5f, neutral=%.5f)', ...
                mean_biased, mean_neutral));
        end

        function testContinuousBreathing(testCase)
            % Diver must never stop breathing, even at max bias.
            % Verify lung volume oscillates continuously.
            simTime = 30;

            % Force large error: target=15m, start at 20m -> max positive bias
            t = [0; simTime];
            ds = Simulink.SimulationData.Dataset;
            ds = ds.addElement(timeseries(15*ones(2,1), t), 'breathing_rate');
            ds = ds.addElement(timeseries(ones(2,1), t), 'breath_depth');
            ds = ds.addElement(timeseries(zeros(2,1), t), 'inflate_btn');
            ds = ds.addElement(timeseries(zeros(2,1), t), 'purge_btn');
            ds = ds.addElement(timeseries([15;15], t), 'depth_target');
            ds = ds.addElement(timeseries([1;1], t), 'auto_depth');

            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            V_lungs = ScubaTestHelper.getSignal(out.logsout, 'V_lungs');

            % Check multiple 4s windows (one full breath each)
            for tStart = 8:4:24
                mask = V_lungs.Time >= tStart & V_lungs.Time < tStart+4;
                V_window = V_lungs.Data(mask);
                oscillation = max(V_window) - min(V_window);
                testCase.verifyGreaterThan(oscillation, 0.02e-3, ...
                    sprintf('Lung volume stalled at t=%.0fs (oscillation=%.4f L)', ...
                    tStart, oscillation*1000));
            end
        end

        function testBCDInactiveForSmallError(testCase)
            % When depth error is within breathing trim range (<2m),
            % BCD should not fire.
            simTime = 30;

            % Target 19m, start at 20m -> 1m error, within breathing range
            t = [0; simTime];
            ds = Simulink.SimulationData.Dataset;
            ds = ds.addElement(timeseries(15*ones(2,1), t), 'breathing_rate');
            ds = ds.addElement(timeseries(ones(2,1), t), 'breath_depth');
            ds = ds.addElement(timeseries(zeros(2,1), t), 'inflate_btn');
            ds = ds.addElement(timeseries(zeros(2,1), t), 'purge_btn');
            ds = ds.addElement(timeseries([19;19], t), 'depth_target');
            ds = ds.addElement(timeseries([1;1], t), 'auto_depth');

            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            % Check BCD volume stays constant (no inflate/purge activity)
            V_bcd = ScubaTestHelper.getSignal(out.logsout, 'V_bcd');
            mask = V_bcd.Time > 5 & V_bcd.Time < 25;
            bcd_range = max(V_bcd.Data(mask)) - min(V_bcd.Data(mask));

            testCase.verifyLessThan(bcd_range, 0.5e-3, ...
                sprintf('BCD volume changed %.2f mL during small-error trim (expect minimal)', ...
                bcd_range*1e6));
        end

        function testBCDFiresForLargeError(testCase)
            % When depth error exceeds BCD deadband (>2m), BCD activates
            % (either inflate or purge depending on direction and rate limiting).
            simTime = 10;

            % Target 16m, start at 20m -> +4m error -> breathing+BCD respond
            % BCD may purge (rate limiting ascent) or inflate (if ascent stalls)
            t = [0; simTime];
            ds = Simulink.SimulationData.Dataset;
            ds = ds.addElement(timeseries(15*ones(2,1), t), 'breathing_rate');
            ds = ds.addElement(timeseries(ones(2,1), t), 'breath_depth');
            ds = ds.addElement(timeseries(zeros(2,1), t), 'inflate_btn');
            ds = ds.addElement(timeseries(zeros(2,1), t), 'purge_btn');
            ds = ds.addElement(timeseries([16;16], t), 'depth_target');
            ds = ds.addElement(timeseries([1;1], t), 'auto_depth');

            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            % BCD moles should change (proves BCD is active, not just breathing)
            n_bcd = ScubaTestHelper.getSignal(out.logsout, 'n_bcd');
            n_initial = n_bcd.Data(1);
            mask = n_bcd.Time > 3;
            n_later = mean(n_bcd.Data(mask));
            change = abs(n_later - n_initial);

            testCase.verifyGreaterThan(change, 0.005, ...
                sprintf('BCD should be active for large error (change=%.4f mol)', change));
        end

        function testBreathingTrimDirection(testCase)
            % With a depth error just above deadzone, breathing bias should
            % produce initial corrective motion (ascending) within the
            % first breath cycle, before Boyle instability can dominate.
            simTime = 8;

            % Target 19m, start at 20m -> +1m error -> positive bias -> ascend
            t = [0; simTime];
            ds = Simulink.SimulationData.Dataset;
            ds = ds.addElement(timeseries(15*ones(2,1), t), 'breathing_rate');
            ds = ds.addElement(timeseries(ones(2,1), t), 'breath_depth');
            ds = ds.addElement(timeseries(zeros(2,1), t), 'inflate_btn');
            ds = ds.addElement(timeseries(zeros(2,1), t), 'purge_btn');
            ds = ds.addElement(timeseries([19;19], t), 'depth_target');
            ds = ds.addElement(timeseries([1;1], t), 'auto_depth');

            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            depth = ScubaTestHelper.getSignal(out.logsout, 'depth');

            % After the first full breath cycle (~4s), the diver should have
            % moved toward the target (shallower) compared to start
            mask_early = depth.Time > 3 & depth.Time < 6;
            mean_depth_early = mean(depth.Data(mask_early));

            testCase.verifyLessThan(mean_depth_early, 20.0, ...
                sprintf('Positive bias should move diver shallower (depth=%.3fm, start=20m)', ...
                mean_depth_early));
        end
    end
end
