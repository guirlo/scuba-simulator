% scripts/run_full_1hr_dive.m
% Run and validate the 1-hour closed-loop dive simulation using fullDiveHarness.slx

% 1. Load parameters and initialize workspace
initWorkspace;

% 2. Configure simulation inputs for 65 minutes (3900 seconds)
simTime = 3900;
simIn = Simulink.SimulationInput('fullDiveHarness');
simIn = simIn.setModelParameter('StopTime', string(simTime));

% 3. Run simulation
fprintf('Starting 1-hour closed-loop dive simulation (3900s of physical time)...\n');
tic;
out = sim(simIn);
sim_elapsed = toc;
fprintf('Simulation completed in %.2f seconds.\n', sim_elapsed);

% 4. Extract logged signals from the outport logging (or Scope logging)
% If outports are logged, we can access them. Let's inspect logs or extract from scopes.
% Since Simulink logs outport signals by default in out, we can get depth and vel from out.get('logsout')
% or out.yout or directly from out.
try
    % Extract depth and velocity from Simscape logs
    p_series = out.simlog.Scuba_Diver.MotionSensor.P.series;
    v_series = out.simlog.Scuba_Diver.MotionSensor.V.series;
    
    t = p_series.time;
    depth = p_series.values;
    vel = v_series.values;
    
    % Let's find index ranges for different phases
    % Bottom hold is between t = 180s and t = 3120s
    bottom_idx = find(t >= 180 & t <= 3120);
    bottom_depth_err = abs(depth(bottom_idx) - 20.0);
    max_bottom_err = max(bottom_depth_err);
    mean_bottom_err = mean(bottom_depth_err);
    
    % Ascent is between t = 3120s and t = 3300s, and t = 3600s and t = 3750s
    % Check maximum ascent velocity (ascent is negative velocity since depth is positive downward)
    % So velocity should be >= -0.167 m/s (10 m/min)
    ascent_vel = vel(t >= 3120 & t <= 3750);
    max_ascent_speed = max(max(0, -ascent_vel));
    
    % Print validation metrics
    fprintf('\n================== VALIDATION METRICS ==================\n');
    fprintf('Initial Depth at t=0: %.3f m\n', depth(1));
    fprintf('Peak Bottom Depth: %.2f m\n', max(depth));
    fprintf('Bottom Time Depth Tracking Error (max): %.2f m\n', max_bottom_err);
    fprintf('Bottom Time Depth Tracking Error (mean): %.2f m\n', mean_bottom_err);
    fprintf('Max Ascent Speed reached: %.3f m/s (Limit: 0.167 m/s)\n', max_ascent_speed);
    fprintf('========================================================\n\n');
    
    % Plot the tracking results
    figure('Position', [100, 100, 800, 600]);
    subplot(2,1,1);
    plot(t, depth, 'b-', 'LineWidth', 2);
    hold on;
    % Draw target depth
    % Descent: 0 to 20m in 120s
    % Bottom: 20m from 120s to 3120s
    % Ascent: 20m to 5m from 3120s to 3300s
    % Safety Stop: 5m from 3300s to 3600s
    % Final Ascent: 5m to 1m from 3600s to 3750s
    % Surfaced: 1m from 3750s onwards
    target_t = [0, 120, 3120, 3300, 3600, 3750, 3900];
    target_d = [0, 20, 20, 5, 5, 1, 1];
    plot(target_t, target_d, 'r--', 'LineWidth', 1.5);
    grid on;
    xlabel('Time (s)');
    ylabel('Depth (m)');
    title('Scuba Diver 1-Hour Dive Profile - Depth Tracking');
    legend('Actual Depth', 'Target Depth');
    set(gca, 'YDir', 'reverse'); % positive depth downwards
    
    subplot(2,1,2);
    plot(t, vel, 'k-', 'LineWidth', 1.5);
    hold on;
    % Draw ascent/descent safety limits
    plot([0, 3900], [0.5, 0.5], 'r:', 'LineWidth', 1);
    plot([0, 3900], [-0.167, -0.167], 'r:', 'LineWidth', 1);
    grid on;
    xlabel('Time (s)');
    ylabel('Velocity (m/s)');
    title('Scuba Diver Velocity');
    legend('Actual Velocity', 'Limits');
    
    % Save plot
    saveas(gcf, 'docs/specs/plant-models/scuba-diver/full_1hr_dive_results.png');
    fprintf('Dive profile plot saved to docs/specs/plant-models/scuba-diver/full_1hr_dive_results.png\n');
    
catch ME
    disp('Error during result extraction or plotting:');
    disp(ME.message);
end
