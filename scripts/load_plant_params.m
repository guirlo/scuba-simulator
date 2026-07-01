function load_plant_params()
% Loads plant parameters into base workspace as individual variables
% for Simscape block parameterization. Call after scuba_params().

params = evalin('base', 'params');

%% Gas Domain Properties
assignin('base', 'gas_R',           params.const.R);
assignin('base', 'gas_T',           params.water.temperature);

%% Gas Tank
assignin('base', 'tank_V',          params.tank.internalVolume);
assignin('base', 'tank_n_init',     params.tank.startMoles);

%% First Stage Regulator
assignin('base', 'reg1_IP_offset',  params.firstStage.IP_offset);
assignin('base', 'reg1_R_open',     params.firstStage.R_open);

%% IP Volume
assignin('base', 'ipvol_V',         params.ipVolume.V);
assignin('base', 'ipvol_n_init',    params.ipVolume.initMoles);

%% Second Stage Regulator
assignin('base', 'reg2_P_crack',    params.secondStage.P_crack);
assignin('base', 'reg2_R_open',     params.secondStage.R_open);

%% Lungs
assignin('base', 'lungs_n_init',    params.lungs.residualMoles);

%% Exhale Valve
assignin('base', 'exhale_P_crack',  params.exhaleValve.P_crack);
assignin('base', 'exhale_R_open',   params.exhaleValve.R_open);

%% BCD Inflate Valve
assignin('base', 'bcdinfl_R_open',  params.bcdInflateValve.R_open);

%% BCD Bladder
assignin('base', 'bcd_V_max',       params.bcd.maxVolume);
assignin('base', 'bcd_K_wall',      params.bcd.wallStiffness);
assignin('base', 'bcd_n_init',      params.bcd.initMoles);

%% Purge Valve
assignin('base', 'purge_R_open',    params.purgeValve.R_open);
assignin('base', 'purge_P_dump',    5000);

%% Ambient Pressure Sensor
assignin('base', 'env_rho_water',   params.water.rho);
assignin('base', 'env_g',           params.const.g);
assignin('base', 'env_P_atm',       params.const.Patm);
assignin('base', 'ic_depth',        params.ic.depth);

%% Buoyancy Force Source
assignin('base', 'diver_m_total',   params.diver.totalMass);
assignin('base', 'diver_V_body',    params.diver.bodyVolume);
assignin('base', 'gear_V',          params.gear.volume);
assignin('base', 'ws_V_surface',    params.wetsuit.surfaceVolume);
assignin('base', 'ws_comp_exp',     params.wetsuit.compressionExponent);

%% Hydrodynamic Drag
assignin('base', 'drag_Cd',         params.diver.dragCoeff);
assignin('base', 'drag_A_frontal',  params.diver.frontalArea);

%% Diver Mass (Simscape Mass block)
assignin('base', 'diver_mass_total', params.diver.totalMass);

%% Breathing Control
assignin('base', 'bc_deadzone',      params.breathControl.deadzone);
assignin('base', 'bc_saturation',    params.breathControl.saturation);
assignin('base', 'bc_K_vel',         params.breathControl.K_vel);
assignin('base', 'bc_duty_shift',    params.breathControl.dutyShiftMax);
assignin('base', 'bc_amp_gain',      params.breathControl.amplitudeGain);
assignin('base', 'bc_bcd_deadband',  params.breathControl.bcdDeadband);

% New 8-second timing parameters (for fullDiveHarness)
assignin('base', 'bc_t_inh_0',       params.breathControl.bc_t_inh_0);
assignin('base', 'bc_duty_shift_inh',params.breathControl.bc_duty_shift_inh);
assignin('base', 'bc_A_base',        params.breathControl.bc_A_base);
assignin('base', 'bc_amplitude_gain',params.breathControl.bc_amplitude_gain);
assignin('base', 'bc_t_ihld_0',      params.breathControl.bc_t_ihld_0);
assignin('base', 'bc_hold_shift_max',params.breathControl.bc_hold_shift_max);
assignin('base', 'bc_t_exh_0',       params.breathControl.bc_t_exh_0);
assignin('base', 'bc_duty_shift_exh',params.breathControl.bc_duty_shift_exh);
assignin('base', 'bc_t_ehld_0',      params.breathControl.bc_t_ehld_0);

% Supervisory control parameters (for fullDiveHarness)
assignin('base', 'ctrl_bottom_depth', params.controller.ctrl_bottom_depth);
assignin('base', 'ctrl_descent_rate', params.controller.ctrl_descent_rate);
assignin('base', 'ctrl_max_descent_rate', params.controller.ctrl_max_descent_rate);
assignin('base', 'ctrl_K_brake',      params.controller.ctrl_K_brake);
assignin('base', 'ctrl_bottom_duration', params.controller.ctrl_bottom_duration);
assignin('base', 'ctrl_safety_depth',  params.controller.ctrl_safety_depth);
assignin('base', 'ctrl_bcd_deadband',  params.controller.ctrl_bcd_deadband);
assignin('base', 'ctrl_K_p',           params.controller.ctrl_K_p);
assignin('base', 'ctrl_ascent_rate',   params.controller.ctrl_ascent_rate);
assignin('base', 'ctrl_K_ascent',      params.controller.ctrl_K_ascent);
assignin('base', 'ctrl_max_ascent_rate', params.controller.ctrl_max_ascent_rate);
assignin('base', 'ctrl_safety_duration', params.controller.ctrl_safety_duration);
assignin('base', 'ctrl_neutral_burst_duration', params.controller.ctrl_neutral_burst_duration);

end
