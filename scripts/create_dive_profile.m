function ds = create_dive_profile()
% Creates a 36-minute dive profile dataset.
% Profile: surface (1m) -> descent to 30m -> 20 min bottom -> stepped ascent
% in 5m increments -> 3 min safety stop at 5m -> surface (1m).
% Ascent rate limited to 9 m/min (0.15 m/s) between steps.

simTime = 36 * 60;  % 36 minutes in seconds

% Ascent rate limit: 9 m/min = 0.15 m/s
max_ascent_rate = 0.15;  % m/s

% Descent rate: 0.5 m/s (30 m in 60s, but from 1m so 29m in 58s ~= 1 min)
descent_rate = 0.5;  % m/s

% Phase timing
t_descent_start = 0;
depth_start = 1;
depth_bottom = 30;
descent_duration = (depth_bottom - depth_start) / descent_rate;  % ~58s

t_bottom_start = descent_duration;
t_bottom_end = t_bottom_start + 20 * 60;  % 20 min at bottom

% Stepped ascent: 30 -> 25 -> 20 -> 15 -> 10 -> 5 in 5m increments
% Time for each 5m step at max_ascent_rate: 5/0.15 = 33.3s
% Add a 1-min hold at each intermediate depth for realism
step_size = 5;
ascent_depths = 25:-step_size:5;
step_transit = step_size / max_ascent_rate;  % 33.3s transit
step_hold = 60;  % 1 min hold at each depth

% Safety stop: 3 min at 5m
safety_stop_duration = 3 * 60;

% Final ascent: 5m -> 1m at reduced rate (3 m/min for shallow safety)
final_ascent_rate = 0.05;  % m/s (3 m/min)
final_ascent_duration = (5 - depth_start) / final_ascent_rate;

% Build time-depth profile as waypoints
t = [];
d = [];

% Start at surface (1m)
t(end+1) = 0;
d(end+1) = depth_start;

% Descent to 30m
t(end+1) = descent_duration;
d(end+1) = depth_bottom;

% Bottom hold
t(end+1) = t_bottom_end;
d(end+1) = depth_bottom;

% Stepped ascent
t_current = t_bottom_end;
depth_current = depth_bottom;
for target_depth = ascent_depths
    % Transit down to target
    t_current = t_current + step_transit;
    t(end+1) = t_current;
    d(end+1) = target_depth;

    % Hold at depth (except at 5m where safety stop applies)
    if target_depth > 5
        t_current = t_current + step_hold;
        t(end+1) = t_current;
        d(end+1) = target_depth;
    end
end

% Safety stop at 5m
t_current = t_current + safety_stop_duration;
t(end+1) = t_current;
d(end+1) = 5;

% Final ascent to 1m
t_current = t_current + final_ascent_duration;
t(end+1) = t_current;
d(end+1) = depth_start;

% Hold at 1m until end of sim
t(end+1) = simTime;
d(end+1) = depth_start;

% Build dataset
t = t(:);
d = d(:);
n = numel(t);

ds = Simulink.SimulationData.Dataset;
ds = ds.addElement(timeseries(15*ones(n,1), t), 'breathing_rate');
ds = ds.addElement(timeseries(ones(n,1), t), 'breath_depth');
ds = ds.addElement(timeseries(zeros(n,1), t), 'inflate_btn');
ds = ds.addElement(timeseries(zeros(n,1), t), 'purge_btn');
ds = ds.addElement(timeseries(d, t), 'depth_target');
ds = ds.addElement(timeseries(ones(n,1), t), 'auto_depth');

fprintf('Dive profile created: %.1f min total\n', t(end)/60);
fprintf('  Descent: 0-%.0fs (%.0fm -> %.0fm)\n', descent_duration, depth_start, depth_bottom);
fprintf('  Bottom:  %.0fs-%.0fs at %.0fm\n', t_bottom_start, t_bottom_end, depth_bottom);
fprintf('  Ascent:  stepped 5m increments with 1-min holds\n');
fprintf('  Safety:  %.0f min at 5m\n', safety_stop_duration/60);
fprintf('  Surface: final ascent to %.0fm\n', depth_start);

end
