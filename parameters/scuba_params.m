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

%% First Stage Regulator
params.firstStage.IP_offset = 10e5;    % Pa (10 bar above ambient)
params.firstStage.R_open = 1e3;        % Pa*s/mol

%% Intermediate Pressure Volume
params.ipVolume.V = 1e-4;              % m^3

%% Second Stage Regulator
params.secondStage.P_crack = 100;      % Pa (work of breathing)
params.secondStage.R_open = 6000;      % Pa*s/mol

%% Lungs
params.lungs.residualMoles = 0.0624;   % mol (residual vol at surface)

%% Exhale Valve
params.exhaleValve.P_crack = 50;       % Pa
params.exhaleValve.R_open = 9000;      % Pa*s/mol

%% BCD Inflate Valve
params.bcdInflateValve.R_open = 5e6;   % Pa*s/mol (~0.2 mol/s, symmetric with purge)

%% BCD Bladder
params.bcd.maxVolume = 0.015;          % m^3 (15 L capacity)
params.bcd.wallStiffness = 1e7;        % Pa/m^3
params.bcd.initMoles = 0.298;           % mol (for neutral buoyancy at ic.depth)
params.bcd.inflateRate = 5e-4;         % m^3/s at ambient pressure
params.bcd.deflateRate = 1e-3;         % m^3/s vent rate

%% Purge Valve
params.purgeValve.R_open = 1e4;        % Pa*s/mol (with P_dump=2000 gives ~0.2 mol/s)

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

%% Breathing
params.breathing.rate = 15;            % breaths per minute
params.breathing.tidalVolume = 0.5e-3; % m^3 (0.5 L normal)
params.breathing.residualVolume = 1.5e-3; % m^3 (1.5 L)
params.breathing.maxVolume = 6e-3;     % m^3 (total lung capacity)

%% Initial Conditions
params.ic.depth = 20;                  % m (initial depth)

%% Physical Constants
params.const.g = 9.81;                 % m/s^2
params.const.R = 8.314;                % J/(mol*K)
params.const.Patm = 101325;            % Pa

%% Derived Parameters
params.wetsuit.surfaceVolume = params.wetsuit.surfaceArea * params.wetsuit.thickness * params.wetsuit.gasFraction;
params.tank.startMoles = params.tank.startPressure * params.tank.internalVolume / (params.const.R * params.water.temperature);
params.diver.totalMass = params.diver.mass + params.weightbelt.mass + params.gear.mass;
params.ipVolume.initMoles = (params.const.Patm + params.firstStage.IP_offset) * params.ipVolume.V / (params.const.R * params.water.temperature);

end
