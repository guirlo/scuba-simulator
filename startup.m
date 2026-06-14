% Project startup script
% Loads parameters into base workspace for Simulink model access

% Add project root to path so Simscape resolves the +scuba domain package

params = scuba_params();
gas = gas_properties(params.tank.gasMix);
load_plant_params();


