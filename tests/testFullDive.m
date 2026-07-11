% testFullDive - Run the closed-loop 1-hour dive (fullDiveHarness) and plot
% the results: depth tracking, BCD volume, valve commands, and lung volume.
% Controller parameters load automatically via the model InitFcn
% (scripts/initDiveController.m).

initDiveController;
mdl = 'fullDiveHarness';
in = Simulink.SimulationInput(mdl);
out = sim(in, 'ShowProgress', 'off');

depth   = out.logsout.get('depth').Values;
ref     = out.logsout.get('depth_ref').Values;
Vbcd    = out.logsout.get('Vbcd').Values;
inflate = out.logsout.get('inflate').Values;
deflate = out.logsout.get('deflate').Values;
Vlung   = out.logsout.get('V_lung').Values;
TankPressure = out.logsout.get('Tank Pressure').Values;

figure('Name', 'Full Dive Results')
tiledlayout(5, 1, 'TileSpacing', 'compact')

nexttile
plot(ref.Time/60, ref.Data, '--', depth.Time/60, depth.Data)
set(gca, 'YDir', 'reverse')
ylabel('Depth (m)')
legend('reference', 'actual', 'Location', 'southeast')
grid on
title('1-hour dive: 18 m \rightarrow 12 m \rightarrow 5 m safety stop \rightarrow surface')

nexttile
plot(Vbcd.Time/60, Vbcd.Data*1e3)
ylabel('V_{BCD} (L)')
grid on

nexttile
plot(inflate.Time/60, inflate.Data, deflate.Time/60, deflate.Data)
ylabel('Valve cmd (0-1)')
legend('inflate', 'deflate', 'Location', 'northeast')
grid on

nexttile
plot(Vlung.Time/60, Vlung.Data*1e3)
ylabel('V_{lung} (L)')
xlabel('Time (min)')
grid on

nexttile
plot(TankPressure.Time/60, TankPressure.Data)
ylabel('Tank Pressure (PSI)')
xlabel('Time (min)')
grid on

% Summary: tracking error and valve duty during each constant-depth hold
holds = [180 1500; 1680 2700; 2880 3180];   % s
names = ["Bottom 18 m", "Bottom 12 m", "Safety stop 5 m"];
fprintf('Dive ended at %.1f min | max depth %.2f m\n', ...
    depth.Time(end)/60, max(depth.Data))
for k = 1:size(holds, 1)
    tq   = (holds(k,1):0.5:holds(k,2))';
    err  = interp1(depth.Time, depth.Data, tq) - interp1(ref.Time, ref.Data, tq);
    duty = mean(interp1(inflate.Time, inflate.Data, tq) > 0 | ...
                interp1(deflate.Time, deflate.Data, tq) > 0) * 100;
    fprintf('%-16s |err| mean %.2f m, max %.2f m | valve duty %.2f%%\n', ...
        names(k), mean(abs(err)), max(abs(err)), duty)
end
