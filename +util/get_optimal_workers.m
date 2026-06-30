function n = get_optimal_workers()
% GET_OPTIMAL_WORKERS  Auto-detect optimal worker count for parfor loops.
%
%   n = util.get_optimal_workers()
%
% Returns the number of CPU cores minus 1 (to leave resources for the
% main MATLAB process). Minimum 1 worker.
%
% Example:
%   pool_size = util.get_optimal_workers();
%   parpool(pool_size);

    % Get CPU core count
    cores = feature('numCores');

    % Leave 1 core for system, minimum 1 worker
    n = max(1, cores - 1);
end
