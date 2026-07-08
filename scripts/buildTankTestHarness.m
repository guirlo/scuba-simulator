function buildTankTestHarness()
    % Programmatically builds models/tank_test.slx using port handles
    
    modelName = 'tank_test';
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
    
    % Create system
    new_system(modelName);
    
    % Set Data Dictionary
    set_param(modelName, 'DataDictionary', 'scubaParams.sldd');
    
    % Load necessary libraries
    load_system('scuba_lib');
    load_system('fl_lib');
    load_system('nesl_utility');
    load_system('simulink');
    
    % Add blocks with proper positions to keep layout neat
    add_block('scuba_lib/gas/elements/Gas Tank', [modelName '/GasTank'], 'Position', [250, 150, 350, 210]);
    add_block('scuba_lib/gas/elements/Ideal Molar Flow Source', [modelName '/FlowSource'], 'Position', [450, 150, 550, 210]);
    add_block('scuba_lib/gas/elements/Ambient Reference', [modelName '/AmbientRef'], 'Position', [450, 250, 550, 280]);
    add_block('scuba_lib/gas/elements/Gas Domain Properties', [modelName '/GasProps'], 'Position', [250, 50, 350, 100]);
    add_block('nesl_utility/Solver Configuration', [modelName '/Solver'], 'Position', [100, 50, 150, 100]);
    
    % Add Constant Block for flow rate command (1.0 mol/s)
    add_block('simulink/Sources/Constant', [modelName '/ConstantFlow'], 'Value', '1.0', 'Position', [450, 50, 480, 80]);
    add_block('nesl_utility/Simulink-PS Converter', [modelName '/SP_Conv'], 'Position', [520, 50, 550, 80]);
    
    % Add translational spring support for Port R (LConn1)
    add_block('fl_lib/Mechanical/Translational Elements/Translational Spring', [modelName '/Spring'], 'Position', [100, 230, 150, 270]);
    add_block('fl_lib/Mechanical/Translational Elements/Mechanical Translational Reference', [modelName '/MechRef'], 'Position', [100, 310, 150, 340]);
    
    % Retrieve Port Handles
    hTank = get_param([modelName '/GasTank'], 'PortHandles');
    hFlow = get_param([modelName '/FlowSource'], 'PortHandles');
    hProps = get_param([modelName '/GasProps'], 'PortHandles');
    hSolver = get_param([modelName '/Solver'], 'PortHandles');
    hSpring = get_param([modelName '/Spring'], 'PortHandles');
    hMechRef = get_param([modelName '/MechRef'], 'PortHandles');
    hConst = get_param([modelName '/ConstantFlow'], 'PortHandles');
    hConv = get_param([modelName '/SP_Conv'], 'PortHandles');
    hAmbient = get_param([modelName '/AmbientRef'], 'PortHandles');
    
    % Connection 1: ConstantFlow output 1 to SP_Conv input 1
    add_line(modelName, hConst.Outport(1), hConv.Inport(1));
    
    % Connection 2: SP_Conv physical signal (RConn1) to FlowSource input (LConn1)
    add_line(modelName, hConv.RConn(1), hFlow.LConn(1));
    
    % Connection 3: Connect GasTank LConn2 (Gas port A) to FlowSource RConn1 (A)
    add_line(modelName, hTank.LConn(2), hFlow.RConn(1));
    
    % Connection 4: Connect GasProps LConn1 to FlowSource RConn1 (A)
    add_line(modelName, hProps.LConn(1), hFlow.RConn(1));
    
    % Connection 5: Connect Solver RConn1 to FlowSource RConn1 (A)
    add_line(modelName, hSolver.RConn(1), hFlow.RConn(1));
    
    % Connection 6: Connect FlowSource RConn1 (A) to AmbientRef LConn1
    add_line(modelName, hFlow.RConn(1), hAmbient.LConn(1));
    
    % Connection 7: Connect GasTank LConn1 (Port R) to Spring LConn1
    add_line(modelName, hTank.LConn(1), hSpring.LConn(1));
    
    % Connection 8: Connect Spring LConn2 to MechRef LConn1
    add_line(modelName, hSpring.LConn(2), hMechRef.LConn(1));
    
    % Save and close
    save_system(modelName, 'models/tank_test.slx');
    close_system(modelName);
end
