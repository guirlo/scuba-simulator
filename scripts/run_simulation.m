function results = run_simulation(configName, simTime)
% Run the scuba buoyancy simulation
%
% Usage:
%   results = run_simulation()                    % defaults
%   results = run_simulation("beginner_tropical", 600)

arguments
    configName (1,1) string = "default"
    simTime (1,1) double = 300
end

% Load parameters
if configName == "default"
    params = scuba_params();
else
    params = diver_configs(configName);
end
gas = gas_properties(params.tank.gasMix);

% Assign to base workspace for Simulink
assignin('base', 'params', params);
assignin('base', 'gas', gas);

% Run simulation
simIn = Simulink.SimulationInput('scuba_buoyancy_sim');
simIn = simIn.setModelParameter('StopTime', string(simTime));
results = sim(simIn);

end
