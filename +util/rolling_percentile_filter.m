function baseline = rolling_percentile_filter(signal, window_length, step_size, percentile)
% ROLLING_PERCENTILE_FILTER  Sliding-window percentile baseline estimation.
%
%   baseline = util.rolling_percentile_filter(signal, window_length, ...
%                                              step_size, percentile)
%
% Computes a smooth baseline of a 1D signal by sliding a window across it,
% computing the specified percentile within each window, and assigning
% that value to the window's center region. This is used to estimate
% slow fluorescence fluctuations (e.g., photobleaching) in calcium
% imaging time courses.
%
% Inputs:
%   signal       - 1D signal vector (row or column)
%   window_length - Number of samples in each sliding window (default: 300)
%   step_size    - Step size between window centers (default: 100)
%   percentile   - Percentile to compute in each window, 0-100 (default: 15)
%
% Output:
%   baseline     - Same length as signal; smooth lower envelope
%
% Algorithm (from get_cell_tcourse_new_zs_jtg.m):
%   Windows of `window_length` samples are placed along the signal spaced
%   by `step_size`. For each window, the `percentile`-th percentile is
%   computed and assigned to the center region (step_size/2 on each side
%   of the window center). Edge windows use truncated ranges.
%
% Example:
%   t = 1:1000;
%   signal = sin(t/50) + 0.5 * randn(1, 1000) + t * 0.01;
%   bl = util.rolling_percentile_filter(signal, 200, 50, 10);
%   plot(t, signal, t, bl);

    if nargin < 2 || isempty(window_length), window_length = 300; end
    if nargin < 3 || isempty(step_size),     step_size = 100; end
    if nargin < 4 || isempty(percentile),    percentile = 15; end

    % Ensure row vector
    was_column = iscolumn(signal);
    if was_column
        signal = signal';
    end

    n_samples = length(signal);
    baseline = zeros(size(signal));

    % Slide window across the signal
    for j = 1 : step_size : n_samples + step_size/2
        % Determine window boundaries (handle edges)
        if j <= window_length / 2
            win_start = 1;
            win_end = window_length;
        elseif j > n_samples - window_length / 2
            win_start = n_samples - window_length + 1;
            win_end = n_samples;
        else
            win_start = j - floor(window_length / 2);
            win_end = j + floor(window_length / 2);
        end

        % Clamp to valid range
        win_start = max(1, win_start);
        win_end = min(n_samples, win_end);

        % Compute percentile within window
        window_data = real(signal(win_start:win_end));
        pct_value = prctile(window_data, percentile);

        % Assign to center region of the window
        assign_start = max(1, j - floor(step_size / 2));
        assign_end = min(n_samples, j + floor(step_size / 2));
        baseline(assign_start:assign_end) = pct_value;
    end

    % Linear interpolation to smooth transitions between windows
    % (preserves the original piecewise-constant behavior at window centers,
    %  but removes sharp jumps at window boundaries)
    nonzero_mask = baseline ~= 0;
    if any(nonzero_mask)
        nonzero_idx = find(nonzero_mask);
        zero_idx = find(~nonzero_mask);

        if ~isempty(zero_idx)
            % Interpolate any gaps
            baseline(zero_idx) = interp1(nonzero_idx, baseline(nonzero_idx), ...
                                         zero_idx, 'linear', 'extrap');
        end
    end

    if was_column
        baseline = baseline';
    end
end
