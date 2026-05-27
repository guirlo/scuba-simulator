function params = diver_configs(configName)
% Preset diver configurations
%
% Usage: params = diver_configs("beginner_tropical")

params = scuba_params(); % Start with defaults

switch configName
    case "beginner_tropical"
        params.water.type = "salt";
        params.water.rho = 1025;
        params.water.temperature = 300.15;  % 27 C
        params.wetsuit.thickness = 0.003;   % 3 mm
        params.weightbelt.mass = 3;
        params.tank.gasMix = "air";
        params.breathing.rate = 18;         % higher for beginners
    case "experienced_cold"
        params.water.type = "fresh";
        params.water.rho = 1000;
        params.water.temperature = 283.15;  % 10 C
        params.wetsuit.thickness = 0.007;   % 7 mm
        params.weightbelt.mass = 7;
        params.tank.gasMix = "air";
        params.breathing.rate = 12;
    case "nitrox_warm"
        params.water.type = "salt";
        params.water.rho = 1025;
        params.water.temperature = 297.15;  % 24 C
        params.wetsuit.thickness = 0.005;   % 5 mm
        params.weightbelt.mass = 4;
        params.tank.gasMix = "nitrox32";
        params.breathing.rate = 14;
    otherwise
        error("Unknown config: %s. Use 'beginner_tropical', 'experienced_cold', or 'nitrox_warm'.", configName);
end

% Recompute derived parameters
params.wetsuit.surfaceVolume = params.wetsuit.surfaceArea * params.wetsuit.thickness * params.wetsuit.gasFraction;
params.tank.startMoles = params.tank.startPressure * params.tank.internalVolume / (params.const.R * params.water.temperature);

end
