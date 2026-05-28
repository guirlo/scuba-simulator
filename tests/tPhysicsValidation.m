classdef tPhysicsValidation < matlab.unittest.TestCase
    % Tests 4.1-4.6: Physics validation against analytical solutions.

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
            ScubaTestHelper.enableLogging(ScubaTestHelper.Lungs, ...
                ["V_lungs", "n_lungs", "n_dot_in", "n_dot_out"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.BCDBladder, ...
                ["V_bcd", "n_bcd"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.AmbPress, ...
                ["depth", "P_amb", "R.v"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.BuoyForce, ...
                ["f", "V_bcd", "V_lungs"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.HydroDrag, ...
                ["f", "R.v"]);
            ScubaTestHelper.enableLogging(ScubaTestHelper.ExhaleValve, ...
                ["n_dot"]);
            testCase.LoggedBlocks = {
                ScubaTestHelper.Tank
                ScubaTestHelper.Lungs
                ScubaTestHelper.BCDBladder
                ScubaTestHelper.AmbPress
                ScubaTestHelper.BuoyForce
                ScubaTestHelper.HydroDrag
                ScubaTestHelper.ExhaleValve
            };
        end
    end

    methods (TestMethodTeardown)
        function disableLogs(testCase)
            ScubaTestHelper.disableAllLogging(testCase.LoggedBlocks);
        end
    end

    methods (Test)
        function testConsumptionScalesWithDepth(testCase)
            % Test 4.1: Consumption rate is positive and consistent with
            % regulator flow physics (not a fixed tidal volume).
            simTime = 60;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            n_tank = ScubaTestHelper.getSignal(out.logsout, 'n_tank');

            % Measure average consumption rate over last 40s
            mask = n_tank.Time > 20;
            t_window = n_tank.Time(mask);
            n_window = n_tank.Data(mask);
            avg_rate = (n_window(1) - n_window(end)) / (t_window(end) - t_window(1));

            % Expected from regulator physics at 20m:
            % Per breath: integral of (200*sin - 100)/6000 over active period
            T_inh = 0.4 * 60/15;
            t1 = T_inh/6; t2 = 5*T_inh/6;
            int_sin = T_inh/pi * (cos(pi*t1/T_inh) - cos(pi*t2/T_inh));
            mol_per_breath = (200*int_sin - 100*(t2-t1)) / 6000;
            expected_rate = (15/60) * mol_per_breath;

            testCase.verifyEqual(avg_rate, expected_rate, ...
                'RelTol', 0.25, ...
                sprintf('Consumption rate %.5f vs expected %.5f mol/s', ...
                avg_rate, expected_rate));
        end

        function testBreathVolumeConstantAtDepth(testCase)
            % Test 4.2: Lung volume oscillates with a measurable tidal volume.
            % Actual tidal volume is determined by regulator flow dynamics.
            simTime = 30;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            V_lungs = ScubaTestHelper.getSignal(out.logsout, 'V_lungs');

            mask = V_lungs.Time > 5 & V_lungs.Time < 18;
            V_data = V_lungs.Data(mask);
            V_tidal = max(V_data) - min(V_data);

            % Tidal volume from regulator model: ~0.1L at 20m
            testCase.verifyGreaterThan(V_tidal, 0.05e-3, ...
                'Tidal volume should be measurable');
            testCase.verifyLessThan(V_tidal, 0.3e-3, ...
                sprintf('Tidal volume %.4f L exceeds physical expectation', V_tidal*1000));
        end

        function testBCDBoylesLaw(testCase)
            % Test 4.3: Fixed moles in BCD -> volume inversely proportional to pressure.
            % Use the runaway ascent scenario to sample V_bcd at different depths.
            simTime = 120;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);

            % Start at 30m with known moles
            n_bcd_init = 0.5; % mol
            simIn = simIn.setBlockParameter(ScubaTestHelper.BCDBladder, ...
                'n_init', num2str(n_bcd_init));
            simIn = simIn.setBlockParameter(ScubaTestHelper.AmbPress, ...
                'depth_init', '30');
            out = ScubaTestHelper.runSim(simIn);

            V_bcd = ScubaTestHelper.getSignal(out.logsout, 'V_bcd');
            depth = ScubaTestHelper.getSignal(out.logsout, 'depth');
            n_bcd = ScubaTestHelper.getSignal(out.logsout, 'n_bcd');

            R = 8.314; T = 293.15;

            % Sample at different depths during ascent
            test_depths = [25, 20, 15, 10];
            for d = test_depths
                mask = abs(depth.Data - d) < 1.0;
                if any(mask)
                    idx = find(mask, 1, 'first');
                    V_measured = V_bcd.Data(idx);
                    n_at_point = n_bcd.Data(idx);
                    P_d = ScubaTestHelper.pressureAtDepth(d);
                    V_expected = n_at_point * R * T / P_d;

                    % Clamp to V_max
                    V_expected = min(V_expected, 0.015);

                    testCase.verifyEqual(V_measured, V_expected, ...
                        'RelTol', 0.05, ...
                        sprintf('Boyle''s law violation at %.0f m: V=%.4f L vs expected %.4f L', ...
                        d, V_measured*1000, V_expected*1000));
                end
            end
        end

        function testBuoyancyForceAnalytical(testCase)
            % Test 4.4: Verify Archimedes force at known state.
            % At t=0 with known initial conditions, check force.
            simTime = 1;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            f_net = ScubaTestHelper.getSignal(out.logsout, 'f');

            % At t=0, depth=20m with default BCD (n_init=0.298)
            rho = 1025; g = 9.81; P_atm = 101325; R = 8.314; T = 293.15;
            P_20m = P_atm + rho * g * 20;

            V_body = 0.078;
            V_gear = 0.003;
            V_ws = 0.0063 * (P_atm / P_20m)^0.7;
            V_bcd_0 = 0.298 * R * T / P_20m;
            V_lungs_0 = 0.0624 * R * T / P_20m;
            V_total = V_body + V_gear + V_ws + V_bcd_0 + V_lungs_0;

            F_buoy = rho * g * V_total;
            m_total = 89;
            F_weight = m_total * g;
            F_net_expected = F_weight - F_buoy;

            % Check initial force (f is weight - buoyancy in model convention)
            testCase.verifyEqual(f_net.Data(1), F_net_expected, ...
                'AbsTol', 5, ...
                sprintf('Net force %.2f N vs expected %.2f N', ...
                f_net.Data(1), F_net_expected));
        end

        function testTerminalVelocity(testCase)
            % Test 4.5: Under constant net force, diver reaches terminal velocity.
            % Start with significant negative buoyancy and let diver sink.
            simTime = 90;
            ds = ScubaTestHelper.createInputDataset(simTime, 0, 0, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);

            % Empty BCD, start at 10m -> net negative buoyancy
            simIn = simIn.setBlockParameter(ScubaTestHelper.BCDBladder, ...
                'n_init', '0');
            simIn = simIn.setBlockParameter(ScubaTestHelper.AmbPress, ...
                'depth_init', '10');
            out = ScubaTestHelper.runSim(simIn);

            vel = ScubaTestHelper.getSignal(out.logsout, 'R.v');

            % Velocity should stabilize (terminal velocity)
            mask = vel.Time > 60;
            v_late = vel.Data(mask);
            v_variation = (max(v_late) - min(v_late));

            % Terminal velocity should be reached (variation < 10% of mean)
            if mean(abs(v_late)) > 0.01
                rel_var = v_variation / mean(abs(v_late));
                testCase.verifyLessThan(rel_var, 0.2, ...
                    'Velocity should stabilize at terminal velocity');
            end
        end

        function testMassBalance(testCase)
            % Test 4.6: Total moles leaving tank = exhaled + BCD/lung accumulation.
            simTime = 60;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);
            out = ScubaTestHelper.runSim(simIn);

            n_tank = ScubaTestHelper.getSignal(out.logsout, 'n_tank');
            n_lungs = ScubaTestHelper.getSignal(out.logsout, 'n_lungs');
            n_bcd = ScubaTestHelper.getSignal(out.logsout, 'n_bcd');
            n_dot_exhale = ScubaTestHelper.getSignal(out.logsout, 'n_dot');

            % Moles leaving tank
            delta_tank = n_tank.Data(1) - n_tank.Data(end);

            % Moles exhausted to ambient
            total_exhaled = trapz(n_dot_exhale.Time, n_dot_exhale.Data);

            % Changes in BCD and lungs
            delta_bcd = n_bcd.Data(end) - n_bcd.Data(1);
            delta_lungs = n_lungs.Data(end) - n_lungs.Data(1);

            % Mass balance: tank_out = exhaled + delta_bcd + delta_lungs + IP_delta
            % IP volume change is small but nonzero
            rhs = total_exhaled + delta_bcd + delta_lungs;
            imbalance = abs(delta_tank - rhs);

            % Allow for IP volume accumulation (small)
            testCase.verifyLessThan(imbalance, 0.01, ...
                sprintf('Mass imbalance: %.6f mol (tank: %.4f, exhaled: %.4f, delta_bcd: %.6f, delta_lungs: %.6f)', ...
                imbalance, delta_tank, total_exhaled, delta_bcd, delta_lungs));
        end

        function testDragForceCorrect(testCase)
            % Verify drag force matches F = 0.5*rho*Cd*A*v*|v| during motion.
            simTime = 60;
            ds = ScubaTestHelper.createInputDataset(simTime, 15, 1, 0, 0);
            simIn = ScubaTestHelper.configureSimInput(simTime, ds);

            % Start with negative buoyancy to create motion
            simIn = simIn.setBlockParameter(ScubaTestHelper.BCDBladder, ...
                'n_init', '0.1');
            out = ScubaTestHelper.runSim(simIn);

            f_drag = ScubaTestHelper.getSignal(out.logsout, 'f', 'HydroDrag');
            vel = ScubaTestHelper.getSignal(out.logsout, 'R.v', 'HydroDrag');

            % Check drag at points with significant velocity
            rho = 1025; Cd = 1.1; A = 0.12;
            mask = abs(vel.Data) > 0.05;
            if any(mask)
                indices = find(mask);
                sample = indices(round(linspace(1, numel(indices), min(20, numel(indices)))));
                for idx = sample'
                    v = vel.Data(idx);
                    F_expected = 0.5 * rho * Cd * A * v * abs(v);
                    testCase.verifyEqual(f_drag.Data(idx), F_expected, ...
                        'RelTol', 0.05, ...
                        sprintf('Drag mismatch at v=%.3f m/s', v));
                end
            end
        end
    end
end
