% Run a full 36-minute dive profile simulation.
% Requires project to be open (startup.m loads params).
%
% Profile: 1m -> 30m descent -> 20 min bottom -> stepped ascent (5m increments)
% -> 3 min safety stop at 5m -> surface at 1m.
% Depth controller (auto mode) manages BCD inflate/purge.
% Diver weighted at 93 kg for proper surface-start ballasting.

%% Create dive profile
ds = create_dive_profile();

%% Configure simulation
simTime = 36 * 60;
simIn = Simulink.SimulationInput('scuba_buoyancy_sim');
simIn = simIn.setModelParameter('StopTime', string(simTime));
simIn = simIn.setModelParameter('LoadExternalInput', 'on');
simIn = simIn.setModelParameter('ExternalInput', 'ds');
simIn = simIn.setModelParameter('SimulationMode', 'normal');

% Surface start at 1m with near-empty BCD
simIn = simIn.setBlockParameter('scuba_buoyancy_sim/Mechanics/AmbientPressure', ...
    'depth_init', '1');
simIn = simIn.setBlockParameter('scuba_buoyancy_sim/GasCircuit/BCDBladder', ...
    'n_init', '0.05');
% Overweight for surface-start diving (93 kg = 80 body + 8 belt + 5 gear)
simIn = simIn.setBlockParameter('scuba_buoyancy_sim/Mechanics/BuoyancyForce', ...
    'm_total', '93');

% Assign dataset to base workspace for External Input
assignin('base', 'ds', ds);

%% Enable logging for tank pressure and key signals
ScubaTestHelper.enableLogging('scuba_buoyancy_sim/GasCircuit/GasTank', ["A.p", "n_tank"]);
ScubaTestHelper.enableLogging('scuba_buoyancy_sim/Mechanics/AmbientPressure', ["depth", "R.v"]);
ScubaTestHelper.enableLogging('scuba_buoyancy_sim/GasCircuit/BCDBladder', ["V_bcd", "n_bcd"]);

%% Run simulation
fprintf('Starting 36-minute dive simulation...\n');
tic;
out = sim(simIn);
elapsed = toc;
fprintf('Simulation completed in %.1f seconds.\n', elapsed);

%% Plot results
plot_dive_results(out, ds);
