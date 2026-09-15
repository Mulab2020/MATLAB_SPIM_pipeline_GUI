function baseline = rolling_percentile_filter(signal, window, percentile)
% ROLLING_PERCENTILE_FILTER  Per-sample sliding-window percentile baseline.
%
%   baseline = util.rolling_percentile_filter(signal)
%   baseline = util.rolling_percentile_filter(signal, window, percentile)
%
% Estimates the slow lower envelope of a 1D signal by sliding a window
% across it one sample at a time and computing the given percentile of
% each window. Used to estimate the baseline fluorescence F0 in the
% rolling-percentile dF/F normalization of pipeline.get_cell_tcourse
% (cf. "Baseline normalization" in Mu et al., 2019, Cell 178, 27-43).
%
% Inputs:
%   signal     - 1D signal vector (row or column)
%   window     - Number of samples in the sliding window (default: 600);
%                clamped to the signal length if it exceeds it
%   percentile - Percentile to compute in each window, 0-100 (default: 15)
%
% Output:
%   baseline - Same size as signal; per-sample percentile estimate. The
%              first ceil(window/2) and last floor(window/2) samples take
%              the value of the first / last full window.
%
% Algorithm (ported from common_20210823/new pipeline):
%   A running sorted copy of the current window is maintained. At each
%   step the outgoing sample is located with a binary search and removed,
%   and the incoming sample is inserted at its sorted position, so each
%   window's percentile is obtained without re-sorting. Complexity is
%   O(n_samples * window) per signal.
%
%   Deviations from the original (bug fixes):
%     - The original inserts a new running minimum AFTER the previous
%       minimum (util.binary_search cannot return a position before the
%       first element), silently breaking the sorted order on drifting
%       signals such as photobleaching decay. New minima are now
%       prepended.
%     - Column vectors are accepted and preserved.
%     - The window is clamped to the signal length (short test runs).
%
% Example:
%   t = 1:1000;
%   signal = sin(t/50) + 0.5 * randn(1, 1000) + t * 0.01;
%   bl = util.rolling_percentile_filter(signal, 200, 15);
%   plot(t, signal, t, bl);
%
% See also util.binary_search, pipeline.get_cell_tcourse

    if nargin < 2 || isempty(window),     window = 600; end
    if nargin < 3 || isempty(percentile), percentile = 15; end

    if ~isvector(signal)
        error('rolling_percentile_filter:notVector', 'Input must be a 1D vector.');
    end

    was_column = iscolumn(signal);
    signal = signal(:)';   % work in row orientation

    n_samples = length(signal);
    window = min(window, n_samples);
    if window < 1
        error('rolling_percentile_filter:badWindow', 'Window must be at least 1 sample.');
    end
    prc_index = min(window, max(1, round(window * percentile / 100)));

    % Degenerate case: single-sample windows
    if window == 1
        baseline = signal;
        if was_column, baseline = baseline'; end
        return;
    end

    baseline = zeros(size(signal));

    sorted = sort(signal(1:window));
    baseline(1:ceil(window/2)) = sorted(prc_index);

    for j = ceil(window/2) + 1 : n_samples - floor(window/2)
        last_point = signal(j - ceil(window/2));
        last_point_index = util.binary_search(sorted, last_point);
        sorted = [sorted(1:last_point_index-1) sorted(last_point_index+1:end)];
        new_point = signal(j + floor(window/2));
        new_point_index = util.binary_search(sorted, new_point);
        if new_point_index == 1 && sorted(1) > new_point
            % New running minimum: insert before the first element
            sorted = [new_point sorted];
        else
            sorted = [sorted(1:new_point_index) new_point sorted(new_point_index+1:end)];
        end
        baseline(j) = sorted(prc_index);
    end

    baseline(n_samples - floor(window/2) + 1 : end) = sorted(prc_index);

    if was_column
        baseline = baseline';
    end
end
