% Build the custom Simscape library from +scuba package
% Run this after any .ssc file changes

fprintf('Building scuba Simscape library...\n');
sscbuild('scuba');
fprintf('Library build complete.\n');
