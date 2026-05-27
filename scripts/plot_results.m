function plot_results(simOut)
% Post-simulation visualization for scuba buoyancy model

simlog = simOut.simlog;
R = 8.314; T = 293.15;

% Extract data
t = simlog.AmbientPressure.depth.series.time;
depth = double(simlog.AmbientPressure.depth.series.values('m'));
n_tank = double(simlog.GasTank.n_tank.series.values('mol'));
n_bcd = double(simlog.BCDBladder.n_bcd.series.values('mol'));
n_lungs = double(simlog.Lungs.n_lungs.series.values('mol'));

P_amb = 101325 + 1025*9.81*depth;
P_tank = n_tank * R * T / 0.012;
V_bcd = n_bcd .* R .* T ./ P_amb * 1000;
V_lungs = n_lungs .* R .* T ./ P_amb * 1000;

V_ws = 6.3 * (101325 ./ P_amb).^0.7;
V_total = 78 + 3 + V_ws + V_bcd + V_lungs;
F_buoy = 1025 * 9.81 * V_total / 1000;
F_weight = 89 * 9.81;
F_net = F_buoy - F_weight;

figure('Name', 'Scuba Buoyancy Simulation', 'Position', [100 100 1000 700]);

subplot(3,2,1);
plot(t, depth, 'b', 'LineWidth', 1.2);
xlabel('Time (s)'); ylabel('Depth (m)');
title('Depth'); set(gca, 'YDir', 'reverse'); grid on;

subplot(3,2,2);
plot(t, P_tank/1e5, 'r', 'LineWidth', 1.2);
xlabel('Time (s)'); ylabel('Pressure (bar)');
title('Tank Pressure'); grid on;

subplot(3,2,3);
plot(t, V_bcd, 'g', 'LineWidth', 1.2);
xlabel('Time (s)'); ylabel('Volume (L)');
title('BCD Volume'); grid on;

subplot(3,2,4);
plot(t, V_lungs, 'm', 'LineWidth', 1.2);
xlabel('Time (s)'); ylabel('Volume (L)');
title('Lung Volume'); grid on;

subplot(3,2,5);
plot(t, V_ws, 'c', 'LineWidth', 1.2);
xlabel('Time (s)'); ylabel('Volume (L)');
title('Wetsuit Volume'); grid on;

subplot(3,2,6);
plot(t, F_net, 'k', 'LineWidth', 1.2);
xlabel('Time (s)'); ylabel('Force (N)');
title('Net Buoyancy Force'); grid on;
yline(0, '--r');

sgtitle('Scuba Diver Buoyancy Simulation Results');

end
