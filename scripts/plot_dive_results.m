function plot_dive_results(out, ds)
% Plot results of a full dive simulation.

depth = ScubaTestHelper.getSignal(out.logsout, 'depth');
P_tank = ScubaTestHelper.getSignal(out.logsout, 'A.p');
V_bcd = ScubaTestHelper.getSignal(out.logsout, 'V_bcd');

% Extract target depth from dataset
depth_target_ts = ds.getElement('depth_target');

figure('Name', 'Full Dive Profile', 'Position', [100 100 1000 700]);

% Depth profile
subplot(3,1,1);
plot(depth.Time/60, depth.Data, 'b-', 'LineWidth', 1.5); hold on;
plot(depth_target_ts.Time/60, depth_target_ts.Data, 'r--', 'LineWidth', 1);
set(gca, 'YDir', 'reverse');
ylabel('Depth (m)');
xlabel('Time (min)');
legend('Actual', 'Target', 'Location', 'best');
title('Dive Profile');
grid on;

% Tank pressure
subplot(3,1,2);
plot(P_tank.Time/60, P_tank.Data/1e5, 'k-', 'LineWidth', 1.5);
ylabel('Tank Pressure (bar)');
xlabel('Time (min)');
title('Tank Pressure');
grid on;

% BCD volume
subplot(3,1,3);
plot(V_bcd.Time/60, V_bcd.Data*1000, 'm-', 'LineWidth', 1.5);
ylabel('BCD Volume (L)');
xlabel('Time (min)');
title('BCD Volume');
grid on;

% Summary
fprintf('\n=== Dive Summary ===\n');
fprintf('Final depth: %.1f m\n', depth.Data(end));
fprintf('Max depth: %.1f m\n', max(depth.Data));
fprintf('Tank start: %.0f bar\n', P_tank.Data(1)/1e5);
fprintf('Tank end:   %.0f bar\n', P_tank.Data(end)/1e5);
fprintf('Gas used:   %.0f bar\n', (P_tank.Data(1)-P_tank.Data(end))/1e5);

end
