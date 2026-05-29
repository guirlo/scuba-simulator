%% Test BCD Buoyancy Harness
% Standalone test: BCDBladder with position-based translational port
% connected to a mass. Slowly inflates BCD from near-empty to observe
% buoyancy transition from negative (sinking) to positive (rising).
%
% Uses foundation.translational.translational (position-based domain).
% Mass (PB) includes gravity automatically via domain params (beta=90).
% Positive x = downward = increasing depth.

%% Parameters
mdl = 'bcd_buoyancy_harness';
diver_mass = 89;      % kg (total diver mass)
depth_init = 20;      % m (starting depth)
bcd_n_init = 0.01;    % mol (almost empty BCD)
sim_time   = 120;     % seconds
flow_rate  = 0.005;   % mol/s (steady inflation rate)

%% Build model
if bdIsLoaded(mdl); close_system(mdl, 0); end
new_system(mdl);
open_system(mdl);

set_param(mdl, 'Solver', 'ode23t', 'StopTime', num2str(sim_time), ...
    'RelTol', '1e-4', 'MaxStep', '0.1');

%% Add blocks

% Simscape solver configuration
add_block('nesl_utility/Solver Configuration', [mdl '/Solver'], ...
    'Position', [50 50 100 90]);

% Mechanical Translational Properties (PB) - sets gravity=9.81, beta=90
add_block('fl_lib/Translational/Utilities/Mechanical Translational Properties (PB)', ...
    [mdl '/MechProps'], 'Position', [50 150 110 190], ...
    'gravity', '9.81', 'beta', '90');

% Translational World (PB) - reference frame (RConn1)
add_block('fl_lib/Translational/Elements/Translational World (PB)', ...
    [mdl '/World'], 'Position', [700 170 740 210]);

% Mass (PB) - diver (LConn1 = R port)
add_block('fl_lib/Translational/Elements/Mass (PB)', ...
    [mdl '/DiverMass'], 'Position', [500 170 550 210], ...
    'mass', num2str(diver_mass));

% Translational Motion Sensor (PB) - absolute mode (LConn1=F, RConn1-3=A,V,P)
add_block('fl_lib/Translational/Sensors/Translational Motion Sensor (PB)', ...
    [mdl '/MotionSensor'], 'Position', [500 250 550 290], ...
    'reference', 'foundation.enum.MeasurementReference.absolute');

% BCD Bladder (LConn1=A gas, RConn1=R PB translational, RConn2=V_bcd PS)
add_block('scuba_lib/gas/elements/BCD Bladder', [mdl '/BCDBladder'], ...
    'Position', [300 160 360 220], ...
    'n_init', num2str(bcd_n_init));

% Gas Domain Properties (propagation source)
add_block('scuba_lib/gas/elements/Gas Domain Properties', [mdl '/GasDomainProps'], ...
    'Position', [100 250 160 290]);

% Ideal Molar Flow Source (LConn1=A gas, LConn2=flow_cmd PS)
add_block('scuba_lib/gas/elements/Ideal Molar Flow Source', [mdl '/FlowSource'], ...
    'Position', [200 250 260 290]);

% Constant flow command (Simulink)
add_block('simulink/Sources/Constant', [mdl '/FlowCmd'], ...
    'Position', [50 330 100 360], ...
    'Value', num2str(flow_rate));

% Simulink-PS Converter for flow command
add_block('nesl_utility/Simulink-PS Converter', [mdl '/SPS_Flow'], ...
    'Position', [150 330 200 360]);

% PS-Simulink converters for outputs
add_block('nesl_utility/PS-Simulink Converter', [mdl '/PSS_Pos'], ...
    'Position', [600 280 650 300]);
add_block('nesl_utility/PS-Simulink Converter', [mdl '/PSS_Vel'], ...
    'Position', [600 250 650 270]);

% Scopes
add_block('simulink/Sinks/Scope', [mdl '/DepthScope'], ...
    'Position', [690 275 730 305]);
add_block('simulink/Sinks/Scope', [mdl '/VelScope'], ...
    'Position', [690 245 730 275]);

% V_bcd output
add_block('nesl_utility/PS-Simulink Converter', [mdl '/PSS_Vbcd'], ...
    'Position', [400 120 450 140]);
add_block('simulink/Sinks/Scope', [mdl '/VbcdScope'], ...
    'Position', [490 115 530 145]);

%% Connect blocks

% Solver connects to mechanical domain (via MechProps)
add_line(mdl, 'Solver/RConn1', 'MechProps/RConn1', 'autorouting', 'smart');

% Translational network: all on same node
% MechProps <-> DiverMass <-> BCDBladder.R <-> World
add_line(mdl, 'MechProps/RConn1', 'DiverMass/LConn1', 'autorouting', 'smart');
add_line(mdl, 'BCDBladder/RConn1', 'DiverMass/LConn1', 'autorouting', 'smart');
add_line(mdl, 'DiverMass/LConn1', 'World/RConn1', 'autorouting', 'smart');

% Motion sensor (absolute mode): RConn1=F (conserving), RConn2=V, RConn3=P
add_line(mdl, 'MotionSensor/RConn1', 'DiverMass/LConn1', 'autorouting', 'smart');

% Gas network: GasDomainProps <-> FlowSource <-> BCDBladder.A (all same node)
add_line(mdl, 'GasDomainProps/LConn1', 'FlowSource/LConn1', 'autorouting', 'smart');
add_line(mdl, 'FlowSource/LConn1', 'BCDBladder/LConn1', 'autorouting', 'smart');

% Flow command: FlowCmd -> SPS_Flow -> FlowSource.flow_cmd (LConn2)
add_line(mdl, 'FlowCmd/1', 'SPS_Flow/1', 'autorouting', 'smart');
add_line(mdl, 'SPS_Flow/RConn1', 'FlowSource/LConn2', 'autorouting', 'smart');

% Motion sensor PS outputs: RConn2=V, RConn3=P
add_line(mdl, 'MotionSensor/RConn3', 'PSS_Pos/LConn1', 'autorouting', 'smart');
add_line(mdl, 'MotionSensor/RConn2', 'PSS_Vel/LConn1', 'autorouting', 'smart');

% Scope connections
add_line(mdl, 'PSS_Pos/1', 'DepthScope/1', 'autorouting', 'smart');
add_line(mdl, 'PSS_Vel/1', 'VelScope/1', 'autorouting', 'smart');

% V_bcd: BCDBladder.V_bcd (RConn2) -> PSS_Vbcd -> VbcdScope
add_line(mdl, 'BCDBladder/RConn2', 'PSS_Vbcd/LConn1', 'autorouting', 'smart');
add_line(mdl, 'PSS_Vbcd/1', 'VbcdScope/1', 'autorouting', 'smart');

%% Configure initial conditions
% Set initial velocity=0 on mass
set_param([mdl '/DiverMass'], 'v_specify', 'on', 'v_priority', 'High', 'v', '0');

%% Configure Simscape logging and run
set_param(mdl, 'SimscapeLogType', 'all');

fprintf('Running BCD buoyancy test harness (position-based domain)...\n');
fprintf('  Diver mass: %.0f kg\n', diver_mass);
fprintf('  Initial depth: %.0f m\n', depth_init);
fprintf('  BCD initial moles: %.3f mol\n', bcd_n_init);
fprintf('  Inflation rate: %.4f mol/s\n', flow_rate);
fprintf('  Gravity: beta=90 deg (full gravity along +x = downward)\n');
fprintf('  Expected: buoyancy crosses neutral as BCD inflates\n\n');

out = sim(mdl);

%% Extract and display results
log = out.simlog;
x_series = log.BCDBladder.R.x.series;
vbcd_series = log.BCDBladder.V_bcd.series;
n_series = log.BCDBladder.n_bcd.series;

fprintf('\n=== Results ===\n');
fprintf('Depth: %.2f m -> %.2f m\n', x_series.values(1), x_series.values(end));
fprintf('V_bcd: %.4f L -> %.4f L\n', vbcd_series.values(1)*1e3, vbcd_series.values(end)*1e3);
fprintf('n_bcd: %.4f mol -> %.4f mol\n', n_series.values(1), n_series.values(end));

fprintf('\nSimulation complete (%.0f s).\n', sim_time);
