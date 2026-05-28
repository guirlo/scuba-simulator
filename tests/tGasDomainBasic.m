classdef tGasDomainBasic < matlab.unittest.TestCase
    % Tests 1.1 and 1.2: Gas domain flow conservation and tank pressure depletion.

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
                ["n_tank", "n_dot_out", "A.p"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.AmbientRef, ...
                ["n_dot_in"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.ExhaleValve, ...
                ["n_dot"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.BCDBladder, ...
                ["n_dot_in"]);
            testCase.LoggedBlocks = {
                ScubaTestHelper.Tank
                ScubaTestHelper.AmbientRef
                ScubaTestHelper.ExhaleValve
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
        function testFlowConservation(testCase)
            % Test 1.1: Molar flow out of tank equals flow into ambient + BCD accumulation.
            % With no BCD commands, all flow exits via exhale valve to ambient.
            simTime = 60;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            n_dot_tank = ScubaTestHelper.getSignal(out.logsout, 'n_dot_out');
            n_dot_exhale = ScubaTestHelper.getSignal(out.logsout, 'n_dot');
            n_dot_ambient = ScubaTestHelper.getSignal(out.logsout, 'n_dot_in', 'AmbientRef');

            % Total moles leaving tank
            total_out_tank = trapz(n_dot_tank.Time, n_dot_tank.Data);

            % Total moles arriving at ambient reference (exhale + purge paths)
            total_in_ambient = trapz(n_dot_ambient.Time, n_dot_ambient.Data);

            % Allow for accumulation changes in lungs/IP volume and
            % gas expansion due to depth change during simulation.
            imbalance = abs(total_out_tank - total_in_ambient);
            testCase.verifyLessThan(imbalance, 0.05, ...
                sprintf('Flow imbalance %.6f mol exceeds tolerance', imbalance));
        end

        function testTankPressureDepletion(testCase)
            % Test 1.2: Tank pressure follows ideal gas law as moles decrease.
            simTime = 60;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            n_tank = ScubaTestHelper.getSignal(out.logsout, 'n_tank');
            P_tank = ScubaTestHelper.getSignal(out.logsout, 'A.p');

            R = 8.314;
            T = 293.15;
            V_tank = 0.012;

            % Verify P = n*R*T/V at multiple time points
            indices = round(linspace(1, numel(n_tank.Data), 10));
            for i = indices
                P_expected = n_tank.Data(i) * R * T / V_tank;
                testCase.verifyEqual(P_tank.Data(i), P_expected, ...
                    'RelTol', 0.001, ...
                    sprintf('Ideal gas law violated at t=%.1f s', n_tank.Time(i)));
            end
        end

        function testTankDepletionRate(testCase)
            % Tank should deplete monotonically during active breathing.
            simTime = 60;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            n_tank = ScubaTestHelper.getSignal(out.logsout, 'n_tank');

            % Overall trend: n_tank decreases
            testCase.verifyLessThan(n_tank.Data(end), n_tank.Data(1), ...
                'Tank moles should decrease over time with breathing');

            % Check net flow is always non-negative (tank only supplies)
            n_dot = ScubaTestHelper.getSignal(out.logsout, 'n_dot_out');
            testCase.verifyGreaterThanOrEqual(min(n_dot.Data), -1e-8, ...
                'Flow into tank should not occur (one-way supply)');
        end
    end
end
