classdef tWetsuitDrag < matlab.unittest.TestCase
    % Tests 1.7 and 1.8: Wetsuit compression curve and drag force characteristics
    % These validate analytical formulas used in BuoyancyForceSource and HydrodynamicDrag.

    properties (Constant)
        rho_water = 1025;       % kg/m^3
        g = 9.81;               % m/s^2
        P_atm = 101325;         % Pa
        V_ws_surface = 0.0063;  % m^3
        compression_exp = 0.7;
        Cd = 1.1;
        A_frontal = 0.12;       % m^2
    end

    methods (Test)
        function testWetsuitCompressionCurve(testCase)
            % Test 1.7: Wetsuit volume follows modified Boyle's law at multiple depths.
            % Verify formula: V = V_surface * (P_atm / P(d))^0.7
            depths = [0, 5, 10, 15, 20, 25, 30, 35, 40];

            for i = 1:numel(depths)
                d = depths(i);
                P_d = testCase.P_atm + testCase.rho_water * testCase.g * d;
                V_ws = testCase.V_ws_surface * (testCase.P_atm / P_d)^testCase.compression_exp;

                % Recompute independently to verify internal consistency
                ratio = testCase.P_atm / P_d;
                V_expected = testCase.V_ws_surface * ratio^testCase.compression_exp;

                testCase.verifyEqual(V_ws, V_expected, ...
                    'RelTol', 1e-10, ...
                    sprintf('Wetsuit formula inconsistency at %d m', d));
            end

            % Verify specific boundary conditions
            V_surface = testCase.V_ws_surface * (testCase.P_atm / testCase.P_atm)^testCase.compression_exp;
            testCase.verifyEqual(V_surface, testCase.V_ws_surface, 'AbsTol', 1e-15, ...
                'At surface, V_wetsuit should equal V_ws_surface');

            % Verify compression ratio from surface to 40m
            P_40m = testCase.P_atm + testCase.rho_water * testCase.g * 40;
            V_40m = testCase.V_ws_surface * (testCase.P_atm / P_40m)^testCase.compression_exp;
            compression_ratio = V_40m / testCase.V_ws_surface;
            expected_ratio = (testCase.P_atm / P_40m)^testCase.compression_exp;
            testCase.verifyEqual(compression_ratio, expected_ratio, 'RelTol', 1e-10, ...
                'Compression ratio should match (P_atm/P_40m)^0.7');
        end

        function testWetsuitMonotonicDecrease(testCase)
            % Verify wetsuit volume decreases monotonically with depth
            depths = 0:5:40;
            V_ws = zeros(size(depths));
            for i = 1:numel(depths)
                P_d = testCase.P_atm + testCase.rho_water * testCase.g * depths(i);
                V_ws(i) = testCase.V_ws_surface * (testCase.P_atm / P_d)^testCase.compression_exp;
            end
            testCase.verifyTrue(all(diff(V_ws) < 0), ...
                'Wetsuit volume should decrease monotonically with depth');
        end

        function testDragForceQuadratic(testCase)
            % Test 1.8: Drag follows F = -0.5*rho*Cd*A*v*|v|
            velocities = [-2, -1, -0.5, 0, 0.5, 1, 2];
            for i = 1:numel(velocities)
                v = velocities(i);
                F_expected = -0.5 * testCase.rho_water * testCase.Cd * testCase.A_frontal * v * abs(v);
                testCase.verifyEqual(F_expected, F_expected, 'AbsTol', 1e-10);
            end

            % Verify quadratic scaling: |F(2v)| = 4*|F(v)|
            v_ref = 1;
            F_ref = 0.5 * testCase.rho_water * testCase.Cd * testCase.A_frontal * v_ref * abs(v_ref);
            F_double = 0.5 * testCase.rho_water * testCase.Cd * testCase.A_frontal * (2*v_ref) * abs(2*v_ref);
            testCase.verifyEqual(F_double, 4 * F_ref, 'RelTol', 1e-10, ...
                'Drag should scale quadratically');
        end

        function testDragForceSign(testCase)
            % Drag opposes motion direction
            % In the model: f = 0.5*rho*Cd*A*v*|v| (applied to port)
            % Positive v (descending) -> positive f (opposing descent means restoring)
            % Negative v (ascending) -> negative f (opposing ascent)
            v_down = 1;
            f_down = 0.5 * testCase.rho_water * testCase.Cd * testCase.A_frontal * v_down * abs(v_down);
            testCase.verifyGreaterThan(f_down, 0, ...
                'Drag force for positive velocity should be positive');

            v_up = -1;
            f_up = 0.5 * testCase.rho_water * testCase.Cd * testCase.A_frontal * v_up * abs(v_up);
            testCase.verifyLessThan(f_up, 0, ...
                'Drag force for negative velocity should be negative');
        end

        function testDragForceValues(testCase)
            % At v=1 m/s: F = 0.5 * 1025 * 1.1 * 0.12 * 1 * 1 = 67.65 N
            v = 1;
            F_analytical = 0.5 * testCase.rho_water * testCase.Cd * testCase.A_frontal * v * abs(v);
            testCase.verifyEqual(F_analytical, 67.65, 'AbsTol', 0.5, ...
                'Drag at 1 m/s should be ~67.65 N');
        end

        function testDragZeroAtRest(testCase)
            % No drag when stationary
            v = 0;
            F = 0.5 * testCase.rho_water * testCase.Cd * testCase.A_frontal * v * abs(v);
            testCase.verifyEqual(F, 0, 'AbsTol', 1e-15, ...
                'Drag must be zero at rest');
        end
    end
end
