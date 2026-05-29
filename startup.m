% Project startup script
% Loads parameters into base workspace for Simulink model access

% Add project root to path so Simscape resolves the +scuba domain package
projRoot = fileparts(mfilename('fullpath'));
addpath(projRoot);
addpath(fullfile(projRoot, 'parameters'));
addpath(fullfile(projRoot, 'scripts'));
addpath(fullfile(projRoot, 'tests'));

params = scuba_params();
gas = gas_properties(params.tank.gasMix);
load_plant_params();

fprintf('Scuba Buoyancy Simulation loaded.\n');
fprintf('  Water: %s (%.0f kg/m^3)\n', params.water.type, params.water.rho);
fprintf('  Tank: %.0f bar, %s\n', params.tank.startPressure/1e5, gas.name);
fprintf('  Diver: %.0f kg, %.1f mm wetsuit\n', params.diver.mass, params.wetsuit.thickness*1000);

