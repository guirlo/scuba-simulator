function gas = gas_properties(mixName)
% Gas mix properties for scuba simulation
%
% Usage: gas = gas_properties("air") or gas = gas_properties("nitrox32")

switch mixName
    case "air"
        gas.name = "Air";
        gas.O2fraction = 0.21;
        gas.N2fraction = 0.79;
        gas.molarMass = 0.21*32e-3 + 0.79*28e-3; % kg/mol
    case "nitrox32"
        gas.name = "Nitrox 32%";
        gas.O2fraction = 0.32;
        gas.N2fraction = 0.68;
        gas.molarMass = 0.32*32e-3 + 0.68*28e-3; % kg/mol
    otherwise
        error("Unknown gas mix: %s. Use 'air' or 'nitrox32'.", mixName);
end

end
