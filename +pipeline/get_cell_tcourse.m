function [cell_resp, cell_info] = get_cell_tcourse(data_dir, params)
% GET_CELLTCOURSE  Extract fluorescence time courses from SPIM stacks.
%
%   [cell_resp, cell_info] = pipeline.get_cell_tcourse(data_dir)
%   [cell_resp, cell_info] = pipeline.get_cell_tcourse(data_dir, params)
%
% Reads per-plane stacks (PlaneXX.stack), extracts the mean fluorescence
% within each cell's ROI over time, applies baseline correction for
% photobleaching, and optionally runs detrending and cell filtering.
%
% Optional params fields:
%   .enable_detrending        - Rolling percentile detrending (default: false)
%   .enable_remove_duplicates - Remove double-counted cells on adjacent
%                               z-planes by correlation (default: false)
%   .enable_motion_filter     - Remove cells near high-motion grid points
%                               (default: false; requires motion_param.mat)
%   .test_minutes             - Limit to first N minutes (default: all)
%   .pool_size                - Number of parallel workers (default: 6)
%
% Always-active processing:
%   1. Raw fluorescence extraction (mean over cell ROI)
%   2. Exponential photobleaching baseline correction
%
% Outputs (written to data_dir):
%   cell_resp_processed.stackf  - Baseline-corrected fluorescence (float32)
%   cell_info_processed.mat     - Filtered cell info struct
%   cell_resp_dim_processed.mat - Dimensions of processed response
%
% See also pipeline.recog_wholefish, pipeline.check_motion

    import util.*;
    import fileIO.*;

    %%% ---------------------------------------------------------------
    %%% 1. Setup and parameter detection
    %%% ---------------------------------------------------------------
    fprintf('\n========== Time Course Extraction (get_cell_tcourse) ==========\n');
    fprintf('Data directory: %s\n', data_dir);

    t_start = tic;

    if nargin < 2, params = struct(); end

    % Default parameter values
    if ~isfield(params, 'enable_detrending'),        params.enable_detrending = false; end
    if ~isfield(params, 'enable_remove_duplicates'), params.enable_remove_duplicates = false; end
    if ~isfield(params, 'enable_motion_filter'),     params.enable_motion_filter = false; end
    if ~isfield(params, 'pool_size'),                params.pool_size = 6; end

    % Auto-detect frame rate and dimensions
    detected = util.auto_params.detect_all(data_dir);
    frame_rate = detected.frame_rate;
    n_total_frames = detected.n_total_frames;
    stack_height = detected.stack_height;
    stack_width = detected.stack_width;
    n_zplanes = detected.n_zplanes;

    % Determine ending frame
    if isfield(params, 'test_minutes') && ~isempty(params.test_minutes)
        ending_frame = round(params.test_minutes * 60 * frame_rate);
        fprintf('TEST MODE: limiting to first %.0f minutes = %d frames\n', ...
                params.test_minutes, ending_frame);
    else
        ending_frame = 0;  % 0 = use all frames
    end

    % Baseline window: 5 seconds worth of frames
    adapting_frame = 1;
    baseline_window_frames = ceil(frame_rate * 5);
    fprintf('Baseline window: ceil(%.2f Hz * 5 s) = %d frames\n', frame_rate, baseline_window_frames);

    %%% ---------------------------------------------------------------
    %%% 2. Load prerequisite data
    %%% ---------------------------------------------------------------
    % Cell info from segmentation
    cell_info_path = fullfile(data_dir, 'cell_info.mat');
    if ~exist(cell_info_path, 'file')
        error('get_cell_tcourse:missingFile', ...
              'cell_info.mat not found. Run pipeline.recog_wholefish first.');
    end
    loaded = load(cell_info_path, 'cell_info');
    cell_info = loaded.cell_info;
    n_cells = length(cell_info);
    fprintf('Loaded %d cells from cell_info.mat\n', n_cells);

    % Average stack (for dimensions)
    ave_file = fullfile(data_dir, 'ave.tif');
    if exist(ave_file, 'file')
        ave_info = imfinfo(ave_file);
        n_ave_pages = length(ave_info);
        ave_stack = zeros(ave_info(1).Height, ave_info(1).Width, n_ave_pages, 'uint16');
        for k = 1:n_ave_pages
            ave_stack(:,:,k) = imread(ave_file, k);
        end
    else
        error('get_cell_tcourse:missingFile', 'ave.tif not found.');
    end
    dim = size(ave_stack);
    if length(dim) == 2, dim = [dim, 1]; end

    % Background image
    bg_file = fullfile(data_dir, 'Background_1.tif');
    if ~exist(bg_file, 'file')
        bg_file = fullfile(data_dir, 'background_1.tif');
    end
    if exist(bg_file, 'file')
        background_img = imread(bg_file);
        fprintf('Loaded background image: %s\n', bg_file);
    else
        warning('get_cell_tcourse:noBackground', ...
                'Background image not found. Using 0 as background value.');
        background_img = zeros(dim(1), dim(2), 'uint16');
    end

    %%% ---------------------------------------------------------------
    %%% 3. Build z-plane → cell index mapping
    %%% ---------------------------------------------------------------
    cell_z_list = [cell_info.slice];
    zplane_list = min(cell_z_list):max(cell_z_list);

    zplane_cell_map = struct();
    for zp = zplane_list
        zplane_cell_map(zp).cellinds = find(cell_z_list == zp);
    end

    % Get total time length from first plane stack
    first_plane_path = fullfile(data_dir, sprintf('Plane%02d.stack', zplane_list(1)));
    stack_dims = double(fileIO.read_LSstack_info(first_plane_path, dim(1:2)));
    n_time_frames = stack_dims(3);
    fprintf('Total time frames per plane: %d\n', n_time_frames);

    %%% ---------------------------------------------------------------
    %%% 4. Extract raw fluorescence (parfor over z-planes)
    %%% ---------------------------------------------------------------
    fprintf('Extracting raw fluorescence for %d cells across %d planes...\n', ...
            n_cells, length(zplane_list));

    raw_fluorescence = zeros(n_cells, n_time_frames, 'single');
    plane_responses = cell(1, length(zplane_list));

    if ~isfield(params, 'pool_size') || isempty(params.pool_size)
        params.pool_size = util.get_optimal_workers();
    end
    fprintf('Extracting raw fluorescence with %d workers...\n', params.pool_size);
    parpool(params.pool_size);

    parfor zp_idx = 1:length(zplane_list)
        zp = zplane_list(zp_idx);
        cell_inds = zplane_cell_map(zp).cellinds;

        plane_path = fullfile(data_dir, sprintf('Plane%02d.stack', zp));
        plane_stack = fileIO.read_LSstack_fast1(plane_path, dim);
        fprintf('  Plane %d: extracting %d cells...\n', zp, length(cell_inds));

        plane_resp = zeros(length(cell_inds), n_time_frames);
        plane_cinfo = cell_info(cell_inds);
        time_slice_offsets = int64(0:(n_time_frames-1)) * int64(dim(1) * dim(2));

        for c = 1:length(cell_inds)
            cell_pixel_inds = plane_cinfo(c).inds;
            tcourse = single(util.get_cell_tcourse_mex64(plane_stack, time_slice_offsets, ...
                                                    int64(cell_pixel_inds)));
            plane_resp(c, :) = tcourse;
        end

        plane_responses{zp_idx} = plane_resp;
    end

    % Reassemble responses in cell_info order
    for zp_idx = 1:length(zplane_list)
        zp = zplane_list(zp_idx);
        cell_inds = zplane_cell_map(zp).cellinds;
        raw_fluorescence(cell_inds, :) = plane_responses{zp_idx};
    end
    clear plane_responses plane_stack;

    % Apply frame range
    if ending_frame == 0
        raw_fluorescence = raw_fluorescence(:, adapting_frame:end);
    else
        raw_fluorescence = raw_fluorescence(:, adapting_frame:ending_frame);
    end
    [n_cells, n_timepoints] = size(raw_fluorescence);
    fprintf('Raw fluorescence dimensions: %d cells x %d timepoints\n', n_cells, n_timepoints);

    % Save raw response
    fileIO.write_LSstack_fast_float(fullfile(data_dir, 'cell_resp.stackf'), raw_fluorescence);
    cell_resp_dim = size(raw_fluorescence);
    save(fullfile(data_dir, 'cell_resp_dim.mat'), 'cell_resp_dim');

    %%% ---------------------------------------------------------------
    %%% 5. Baseline correction (exponential photobleaching fit)
    %%% ---------------------------------------------------------------
    fprintf('Applying baseline correction (exponential photobleaching fit)...\n');

    % Background value: mean of bottom 5% of background pixels
    bg_sorted = sort(double(background_img(:)), 'ascend');
    background_baseline = mean(bg_sorted(1:round(length(bg_sorted) / 20)));
    fprintf('  Background baseline: %.1f (bottom 5%% of background pixels)\n', background_baseline);

    n_baseline_windows = floor(n_timepoints / baseline_window_frames);
    fprintf('  %d baseline windows of %d frames each\n', n_baseline_windows, baseline_window_frames);

    bottom_fraction = round(baseline_window_frames / 3);
    fprintf('  F0 estimated from bottom %d frames per window\n', bottom_fraction);

    % For each cell, estimate baseline in each window (bottom fraction)
    window_baselines = zeros(n_cells, n_baseline_windows);
    for w = 1:n_baseline_windows
        window_data = raw_fluorescence(:, (w-1)*baseline_window_frames + (1:baseline_window_frames));
        window_data_sorted = sort(window_data, 2);
        window_baselines(:, w) = mean(window_data_sorted(:, 1:bottom_fraction), 2) - background_baseline;
    end
    window_baselines(window_baselines < 0) = 0;

    % Exponential fit: log(baseline / mean(first windows))
    log_baseline_ratio = log(window_baselines ./ repmat(mean(window_baselines(:, 1:2), 2), [1 n_baseline_windows]));
    window_centers = round(baseline_window_frames / 2) + (0:baseline_window_frames:((n_baseline_windows-1)*baseline_window_frames));

    fitted_baseline = zeros(n_cells, n_timepoints);
    fprintf('  Fitting exponential baseline for %d cells...\n', n_cells);

    for c = 1:n_cells
        coeffs = polyfit(window_centers, log_baseline_ratio(c, :), 1);
        fitted_baseline(c, :) = exp(coeffs(1) * (1:n_timepoints)) * mean(window_baselines(c, 1:2));
    end

    % Apply baseline correction: dF/F = (F - F0) / F0_fit
    baseline_corrected = (raw_fluorescence - background_baseline) ./ fitted_baseline;

    % Save intermediate
    save(fullfile(data_dir, 'baseline_fit.mat'), 'window_centers', 'window_baselines', ...
         'fitted_baseline', 'background_baseline', '-v7.3');

    %%% ---------------------------------------------------------------
    %%% 6. Optional: Detrending (rolling percentile filter)
    %%% ---------------------------------------------------------------
    if params.enable_detrending
        fprintf('\n--- Optional: Detrending (rolling percentile filter) ---\n');
        fprintf('  Window: %d frames, step: %d frames, percentile: %d\n', 300, 100, 15);

        detrended = zeros(size(baseline_corrected), 'single');
        win_len = 300;
        move_step = 100;

        parfor c = 1:n_cells
            cell_trace = baseline_corrected(c, :);
            crd = zeros(size(cell_trace));

            for j = 1 : move_step : n_timepoints + move_step/2
                % Window boundaries with edge handling
                if j <= win_len / 2
                    w_start = 1;
                    w_end = win_len;
                elseif j > n_timepoints - win_len / 2
                    w_start = n_timepoints - win_len + 1;
                    w_end = n_timepoints;
                else
                    w_start = j - floor(win_len / 2);
                    w_end = j + floor(win_len / 2);
                end

                w_start = max(1, w_start);
                w_end = min(n_timepoints, w_end);

                window_vals = real(cell_trace(w_start:w_end));
                pct_val = prctile(window_vals, 15);

                assign_start = max(1, j - floor(move_step / 2));
                assign_end = min(n_timepoints, j + floor(move_step / 2));
                crd(assign_start:assign_end) = pct_val;
            end

            detrended(c, :) = cell_trace - crd + 1;
        end

        baseline_corrected = detrended;
        fprintf('  Detrending complete.\n');
    end

    %%% ---------------------------------------------------------------
    %%% 7. Optional: Remove double-counted cells
    %%% ---------------------------------------------------------------
    if params.enable_remove_duplicates && dim(3) > 1
        fprintf('\n--- Optional: Removing double-counted cells ---\n');

        corr_threshold = 0.7;
        fprintf('  Correlation threshold: %.2f\n', corr_threshold);

        % De-mean for correlation
        n_epochs = floor(n_timepoints / baseline_window_frames);
        epoch_len = baseline_window_frames;
        n_corr_timepoints = n_epochs * epoch_len;
        trace_for_corr = baseline_corrected(:, 1:n_corr_timepoints);

        epoch_mean = squeeze(mean(reshape(trace_for_corr, [n_cells, epoch_len, n_epochs]), 3));
        trace_demeaned = trace_for_corr - repmat(epoch_mean, [1, n_epochs]);

        % Build 5x5 spatial neighborhood kernel
        [kr, kc] = find(ones(5, 5));
        kr = kr - 3; kc = kc - 3;
        neighbor_offsets = kc * dim(1) + kr;

        cell_remove_mask = zeros(1, n_cells);
        for z = 1:dim(3) - 1
            % Map cells on plane z and z+1 to spatial grids
            plane_z = zeros(dim(1), dim(2));
            plane_zp1 = zeros(dim(1), dim(2));

            cells_on_z = find([cell_info.slice] == z & cell_remove_mask == 0);
            cells_on_zp1 = find([cell_info.slice] == z + 1 & cell_remove_mask == 0);

            for i = 1:length(cells_on_z)
                ci = cells_on_z(i);
                center_lin = dim(1) * (cell_info(ci).center(2) - 1) + cell_info(ci).center(1);
                nbr = center_lin + neighbor_offsets;
                in_bounds = nbr > 0 & nbr < dim(1) * dim(2);
                plane_z(nbr(in_bounds)) = ci;
            end

            for i = 1:length(cells_on_zp1)
                ci = cells_on_zp1(i);
                center_lin = dim(1) * (cell_info(ci).center(2) - 1) + cell_info(ci).center(1);
                nbr = center_lin + neighbor_offsets;
                in_bounds = nbr > 0 & nbr < dim(1) * dim(2);
                plane_zp1(nbr(in_bounds)) = ci;
            end

            % Find overlapping regions
            overlap_mask = (plane_z > 0) .* (plane_zp1 > 0);
            CC = bwconncomp(overlap_mask);

            for comp = 1:CC.NumObjects
                pixels = CC.PixelIdxList{comp};
                cell_above = max(plane_z(pixels));
                cell_below = max(plane_zp1(pixels));

                corr_val = util.corrcoef_pair_mex(double(trace_demeaned(cell_above, :)), ...
                                             double(trace_demeaned(cell_below, :)));
                if corr_val > corr_threshold
                    cell_remove_mask(cell_below) = 1;
                end
            end
        end

        removed_cells = find(cell_remove_mask > 0);
        keep_cells = find(cell_remove_mask == 0);
        fprintf('  Removed %d double-counted cells (%.1f%%)...\n', ...
                length(removed_cells), 100 * length(removed_cells) / n_cells);

        cell_info = cell_info(keep_cells);
        baseline_corrected = baseline_corrected(keep_cells, :);
        n_cells = length(cell_info);
    end

    %%% ---------------------------------------------------------------
    %%% 8. Optional: Motion-based cell filtering
    %%% ---------------------------------------------------------------
    if params.enable_motion_filter
        fprintf('\n--- Optional: Motion-based cell filtering ---\n');

        motion_file = fullfile(data_dir, 'motion_param.mat');
        if ~exist(motion_file, 'file')
            warning('get_cell_tcourse:noMotionFile', ...
                    'motion_param.mat not found. Skipping motion filtering.');
        else
            loaded_motion = load(motion_file, 'motion_param');
            motion_param = loaded_motion.motion_param;

            move_threshold = 1;
            fprintf('  Motion threshold: %d pixel\n', move_threshold);

            % For each cell, find nearest grid points and average their motion
            for c = 1:n_cells
                zp = cell_info(c).slice;
                cell_yx = cell_info(c).center;

                grid_lin = motion_param(zp).indslist;
                grid_y = mod(grid_lin, dim(1));
                grid_y(grid_y == 0) = dim(1);
                grid_x = ceil(grid_lin / dim(1));

                distances = sqrt((grid_y - cell_yx(1)).^2 + (grid_x - cell_yx(2)).^2);
                [~, sort_idx] = sort(distances, 'ascend');
                n_nearby = min(5, length(sort_idx));
                nearest_grid_inds = sort_idx(1:n_nearby);

                cell_info(c).motion = mean(motion_param(zp).tilt_med(nearest_grid_inds, :), 1);
            end

            motion_mat = [cell_info.motion];
            motion_y = motion_mat(1:3:end);
            motion_x = motion_mat(2:3:end);
            motion_z = motion_mat(3:3:end);

            high_motion = find(abs(motion_y) > move_threshold | ...
                               abs(motion_x) > move_threshold | ...
                               abs(motion_z) > move_threshold);
            keep_cells = setdiff(1:n_cells, high_motion);

            fprintf('  Removed %d cells near high-motion regions\n', length(high_motion));

            cell_info = cell_info(keep_cells);
            baseline_corrected = baseline_corrected(keep_cells, :);
            n_cells = length(cell_info);
        end
    end

    %%% ---------------------------------------------------------------
    %%% 9. Save outputs
    %%% ---------------------------------------------------------------
    cell_resp = baseline_corrected;
    cell_resp_dim = size(cell_resp);

    % Build output suffix based on enabled options
    suffixes = {};
    if params.enable_detrending, suffixes{end+1} = 'detrended'; end
    if params.enable_remove_duplicates, suffixes{end+1} = 'dedup'; end
    if params.enable_motion_filter, suffixes{end+1} = 'motionfiltered'; end

    if isempty(suffixes)
        suffix_str = '';
    else
        suffix_str = ['_' strjoin(suffixes, '_')];
    end

    resp_filename = ['cell_resp_processed' suffix_str '.stackf'];
    dim_filename = ['cell_resp_dim_processed' suffix_str '.mat'];
    info_filename = ['cell_info_processed' suffix_str '.mat'];

    fileIO.write_LSstack_fast_float(fullfile(data_dir, resp_filename), cell_resp);
    save(fullfile(data_dir, dim_filename), 'cell_resp_dim');
    save(fullfile(data_dir, info_filename), 'cell_info');

    delete(gcp('nocreate'));

    elapsed = toc(t_start);
    fprintf('\n========== Time course extraction complete ==========\n');
    fprintf('Cells: %d, Timepoints: %d\n', n_cells, cell_resp_dim(2));
    fprintf('Outputs:\n');
    fprintf('  %s\n', fullfile(data_dir, resp_filename));
    fprintf('  %s\n', fullfile(data_dir, info_filename));
    if params.enable_detrending,  fprintf('  [x] Detrending applied\n'); end
    if params.enable_remove_duplicates, fprintf('  [x] Double-counted cells removed\n'); end
    if params.enable_motion_filter, fprintf('  [x] Motion-filtered\n'); end
    fprintf('Elapsed time: %.1f seconds\n', elapsed);
    fprintf('========================================================\n\n');
end
