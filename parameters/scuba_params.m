function params = scuba_params()
% Master parameter configuration for scuba buoyancy simulation

%% Water Environment
params.water.type = "salt";            % "salt" or "fresh"
params.water.temperature = 293.15;     % K (20 C)
if params.water.type == "salt"
    params.water.rho = 1025;           % kg/m^3
else
    params.water.rho = 1000;           % kg/m^3
end

%% Tank
params.tank.internalVolume = 0.012;    % m^3 (12 L aluminum 80)
params.tank.startPressure = 200e5;     % Pa (200 bar)
params.tank.gasMix = "air";            % "air" or "nitrox32"

%% Diver
params.diver.mass = 80;                % kg (body mass)
params.diver.bodyVolume = 0.078;       % m^3
params.diver.frontalArea = 0.12;       % m^2
params.diver.dragCoeff = 1.1;          % dimensionless

%% Wetsuit
params.wetsuit.thickness = 0.005;      % m (5 mm)
params.wetsuit.surfaceArea = 1.8;      % m^2 (body surface area covered)
params.wetsuit.gasFraction = 0.70;     % closed-cell porosity
params.wetsuit.compressionExponent = 0.7; % empirical Boyle's exponent

%% Weight Belt
params.weightbelt.mass = 4;            % kg

%% Gear
params.gear.mass = 5;                  % kg (fins, mask, reg, etc.)
params.gear.volume = 0.003;            % m^3 (displaced volume)

%% BCD
params.bcd.maxVolume = 0.015;          % m^3 (15 L capacity)
params.bcd.inflateRate = 5e-4;         % m^3/s at ambient pressure
params.bcd.deflateRate = 1e-3;         % m^3/s vent rate

%% Breathing
params.breathing.rate = 15;            % breaths per minute
params.breathing.tidalVolume = 0.5e-3; % m^3 (0.5 L normal)
params.breathing.residualVolume = 1.5e-3; % m^3 (1.5 L)
params.breathing.maxVolume = 6e-3;     % m^3 (total lung capacity)

%% Physical Constants
params.const.g = 9.81;                 % m/s^2
params.const.R = 8.314;                % J/(mol*K)
params.const.Patm = 101325;            % Pa

%% Derived Parameters
params.wetsuit.surfaceVolume = params.wetsuit.surfaceArea * params.wetsuit.thickness * params.wetsuit.gasFraction;
params.tank.startMoles = params.tank.startPressure * params.tank.internalVolume / (params.const.R * params.water.temperature);

end
