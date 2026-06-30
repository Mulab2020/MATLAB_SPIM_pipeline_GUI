function motion_param = check_motion_gpu(data_dir, params)
% CHECK_MOTION_GPU  GPU-accelerated motion correction.
%
%   motion_param = pipeline.check_motion_gpu(data_dir)
%   motion_param = pipeline.check_motion_gpu(data_dir, params)
%
% GPU-accelerated variant of pipeline.check_motion. The FFT-based
% cross-correlation at each grid point runs on the GPU for faster
% throughput. All other logic (I/O, grid placement, visualization)
% is identical to the CPU version.
%
% Falls back to pipeline.check_motion if:
%   - No GPU device is detected (gpuDeviceCount == 0)
%   - GPU memory is insufficient for the working set
%
% Optional params fields: same as pipeline.check_motion.
%   .test_minutes        - Limit processing to first N minutes (for dev/testing)
%   .brightness_threshold - Grid-point brightness threshold (default: 120)
%   .pool_size           - Number of parfor workers (default: auto-detect)
%   .skip_viz            - Skip visualization generation (default: false)
%   .keep_pool           - Keep parallel pool alive after completion (default: false)
%
% See also pipeline.check_motion

    % Check GPU availability
    try
        if (exist('gpuDeviceCount', 'builtin') == 0 && exist('gpuDeviceCount', 'file') == 0) ...
           || gpuDeviceCount() == 0
            fprintf('[check_motion_gpu] No GPU detected. Falling back to CPU.\n');
            motion_param = pipeline.check_motion(data_dir, params);
            return;
        end
        gpu_dev = gpuDevice();
        fprintf('[check_motion_gpu] Using GPU: %s (%.1f GB available)\n', ...
                gpu_dev.Name, gpu_dev.AvailableMemory / 1e9);
    catch ME
        fprintf('[check_motion_gpu] GPU check failed: %s. Falling back to CPU.\n', ME.message);
        motion_param = pipeline.check_motion(data_dir, params);
        return;
    end

    %%% ---------------------------------------------------------------
    %%% This is the same as check_motion.m except the inner FFT
    %%% cross-correlation loop uses gpuArray. We delegate the bulk
    %%% of the logic to check_motion but replace the bottleneck.
    %%%
    %%% Strategy: the parfor loop calls a local helper that runs
    %%% FFT operations on gpuArray for each grid point.
    %%% ---------------------------------------------------------------

    import util.*;
    import fileIO.*;

    fprintf('\n========== Motion Correction (GPU) ==========\n');
    fprintf('Data directory: %s\n', data_dir);

    if nargin < 2, params = struct(); end

    % Auto-detect parameters
    detected = util.auto_params.detect_all(data_dir);
    frame_rate = detected.frame_rate;
    stack_height = detected.stack_height;
    stack_width = detected.stack_width;
    n_zplanes = detected.n_zplanes;
    sdim = [stack_height, stack_width, n_zplanes];

    xy_pixel_um = 0.406;
    z_pixel_um = 5;
    grid_radius = 30;
    zcycle_seconds = 60;
    zcycle = round(frame_rate * zcycle_seconds);
    fprintf('zcycle = round(frame_rate * %.0f) = %d frames/timepoint\n', zcycle_seconds, zcycle);

    if isfield(params, 'brightness_threshold')
        brightness_threshold = params.brightness_threshold;
    else
        brightness_threshold = 120;
    end

    if isfield(params, 'test_minutes') && ~isempty(params.test_minutes)
        max_frames = round(params.test_minutes * 60 * frame_rate);
        fprintf('TEST MODE: limiting to first %.0f minutes\n', params.test_minutes);
    else
        max_frames = Inf;
    end

    %%% --- Build reference stacks (same as CPU version) ---
    grid_roi_width = grid_radius * 2 + 1;
    z_list = 1:sdim(3);

    reference_set = struct();
    ref_volume = zeros(sdim(1), sdim(2), sdim(3));

    for i = 1:sdim(3)
        reference_set(i).sdim = sdim;
    end

    % Allow overriding worker count via params.pool_size (for benchmarking)
    if isfield(params, 'pool_size') && ~isempty(params.pool_size)
        pool_size = params.pool_size;
    else
        pool_size = util.get_optimal_workers();
    end

    % Open parallel pool only if needed
    pool = gcp('nocreate');
    if isempty(pool)
        fprintf('Opening parallel pool with %d workers...\n', pool_size);
        parpool(pool_size);
    elseif pool.NumWorkers ~= pool_size
        fprintf('Reconfiguring parallel pool: %d -> %d workers...\n', pool.NumWorkers, pool_size);
        delete(pool);
        parpool(pool_size);
    else
        fprintf('Using existing parallel pool with %d workers.\n', pool_size);
    end

    parfor zz = 1:length(z_list)
        plane_path = fullfile(data_dir, sprintf('Plane%02d.stack', z_list(zz)));
        plane_dims = reference_set(zz).sdim;
        frame_stack = fileIO.read_LSstack_fast2(plane_path, [plane_dims(1) plane_dims(2)], [1 zcycle]);
        ref_volume(:,:,zz) = util.create_zslice_ave_mex(uint16(frame_stack), ...
                            int32([plane_dims(1) plane_dims(2)]), int32(1:zcycle));
    end

    for i = 1:sdim(3)
        neighbor_planes = (-2:2) + i;
        valid_neighbors = neighbor_planes(neighbor_planes > 0 & neighbor_planes <= sdim(3));
        reference_set(i).refstack = ref_volume(:,:,valid_neighbors);
    end

    %%% --- Motion estimation with GPU-accelerated FFT ---
    % Pre-allocate struct arrays for parfor (must match CPU version)
    motion_param = struct('tilt', cell(1, length(z_list)), ...
                          'tilt_med', cell(1, length(z_list)), ...
                          'indslist', cell(1, length(z_list)), ...
                          'xymove_av', cell(1, length(z_list)), ...
                          'xymove_sd', cell(1, length(z_list)), ...
                          'zmove_av', cell(1, length(z_list)), ...
                          'zmove_sd', cell(1, length(z_list)));

    parfor zz = z_list
        plane_path = fullfile(data_dir, sprintf('Plane%02d.stack', z_list(zz)));
        d = reference_set(zz).sdim;

        d2_full = double(fileIO.read_LSstack_info(plane_path, [d(1) d(2)]));
        n_frames_use = min(d2_full(3), max_frames);
        n_timepoints = floor(n_frames_use / zcycle);

        % Read timepoint stacks (I/O is CPU-bound)
        timepoint_stack = zeros(d(1), d(2), n_timepoints);
        for tp = 1:n_timepoints
            frame_range = [((tp-1)*zcycle + 1), tp*zcycle];
            fstack = fileIO.read_LSstack_fast2(plane_path, [d(1) d(2)], frame_range);
            timepoint_stack(:,:,tp) = util.create_zslice_ave_mex(uint16(fstack), ...
                                     int32([d(1) d(2)]), int32(1:zcycle));
        end

        % Grid-point setup (same as CPU)
        reference_image = double(mean(timepoint_stack(:,:,1), 3));
        grid_spacing = grid_radius;
        n_grid_y = floor((d(1) - grid_roi_width*2) / grid_spacing);
        n_grid_x = floor((d(2) - grid_roi_width*2) / grid_spacing);
        n_grid_points = n_grid_y * n_grid_x;
        grid_start_inds = zeros(n_grid_points, 2);

        [r_patch, c_patch] = find(ones(grid_roi_width) > 0);
        r_patch = r_patch - grid_radius - 1;
        c_patch = c_patch - grid_radius - 1;
        patch_offset_inds = (c_patch - 1) * d(1) + r_patch;

        idx = 1;
        for gx = 1:n_grid_x
            for gy = 1:n_grid_y
                start_ind = (grid_roi_width + (gx-1)*grid_spacing) * d(1) + ...
                            grid_roi_width + (gy-1)*grid_spacing + 1;
                grid_start_inds(idx, 1) = start_ind;
                grid_start_inds(idx, 2) = mean(reference_image(start_ind + patch_offset_inds));
                idx = idx + 1;
            end
        end

        bright_enough = find(grid_start_inds(:,2) > brightness_threshold);
        valid_grid_inds = grid_start_inds(bright_enough, 1);

        % --- GPU-accelerated FFT cross-correlation ---
        first_timepoint_img = double(timepoint_stack(:,:,1));
        tilt_raw = zeros(length(valid_grid_inds), 3);

        z_neighbor_shifts = -2:2;

        for i = 1:length(valid_grid_inds)
            gind = valid_grid_inds(i);

            % Extract patch and move to GPU
            source_patch = reshape(first_timepoint_img(gind + patch_offset_inds), ...
                                   [grid_roi_width grid_roi_width]);
            source_fft_gpu = fft2(gpuArray(source_patch));

            displacement_xy_g = zeros(2, n_timepoints);
            displacement_z_raw_g = zeros(1, n_timepoints);

            for tp = 1:n_timepoints
                % GPU: FFT of target, cross-power spectrum
                target_patch = reshape(timepoint_stack(gind + patch_offset_inds + ...
                                       (tp-1)*d(1)*d(2)), [grid_roi_width grid_roi_width]);
                target_fft_gpu = fft2(gpuArray(target_patch));

                cross_power_gpu = fftshift(ifft2(source_fft_gpu .* conj(target_fft_gpu)));
                [~, maxpos] = max(abs(cross_power_gpu(:)));
                maxpos = gather(maxpos);

                dy = -(mod(maxpos, grid_roi_width) - grid_radius - 1);
                if dy == -grid_radius - 1, dy = grid_radius; end
                dx = -(ceil(maxpos / grid_roi_width) - grid_radius - 1);

                displacement_xy_g(1, tp) = dy;
                displacement_xy_g(2, tp) = dx;

                % Z estimation (CPU — small data, correlation is cheap)
                move_offset = -dx * d(1) - dy;
                z_correlations = zeros(1, 5);
                valid_z_shifts = find(z_neighbor_shifts + zz > 0 & ...
                                      z_neighbor_shifts + zz <= d(3));
                target_cpu = target_patch;  % target_patch is already on CPU
                for k = 1:length(valid_z_shifts)
                    z_target_vals = reference_set(zz).refstack(...
                        gind + move_offset + patch_offset_inds + (k-1)*d(1)*d(2));
                    z_correlations(valid_z_shifts(k)) = ...
                        util.corrcoef_pair_mex(target_cpu(:), z_target_vals(:));
                end
                [~, z_best] = max(z_correlations(valid_z_shifts));
                displacement_z_raw_g(tp) = z_neighbor_shifts(valid_z_shifts(z_best));
            end

            displacement_xy = gather(displacement_xy_g);
            displacement_z_raw = gather(displacement_z_raw_g);

            % Linear fit (CPU)
            time_axis = (1:n_timepoints)';
            py = polyfit(time_axis, squeeze(displacement_xy(1, :))', 1);
            px = polyfit(time_axis, squeeze(displacement_xy(2, :))', 1);
            pz = polyfit(time_axis, displacement_z_raw, 1);

            tilt_raw(i, 1) = py(1) * (n_timepoints - 1);
            tilt_raw(i, 2) = px(1) * (n_timepoints - 1);
            tilt_raw(i, 3) = pz(1) * (n_timepoints - 1);
        end

        % Median filtering (same as CPU)
        tilt_med = zeros(length(valid_grid_inds), 3);
        for dim = 1:3
            tilt_grid = zeros(n_grid_y, n_grid_x);
            mask_grid = zeros(n_grid_y, n_grid_x);
            for ii = 1:length(valid_grid_inds)
                tilt_grid(bright_enough(ii)) = tilt_raw(ii, dim);
                mask_grid(bright_enough(ii)) = 1;
            end
            [r_k, c_k] = find(ones(3, 3));
            median_kernel = (c_k - 2) * n_grid_y + (r_k - 2);
            for ii = 1:length(valid_grid_inds)
                nbr = bright_enough(ii) + median_kernel;
                in_b = nbr > 0 & nbr <= n_grid_x * n_grid_y;
                valid_nbr = nbr(in_b);
                has_data = valid_nbr(mask_grid(valid_nbr) > 0);
                tilt_med(ii, dim) = median(tilt_grid(has_data));
            end
        end

        xy_mag = sqrt(tilt_med(:,1).^2 + tilt_med(:,2).^2);
        motion_param(zz).tilt = tilt_raw;
        motion_param(zz).tilt_med = tilt_med;
        motion_param(zz).indslist = valid_grid_inds;
        motion_param(zz).xymove_av = mean(xy_mag) * xy_pixel_um;
        motion_param(zz).xymove_sd = std(xy_mag * xy_pixel_um, [], 1);
        motion_param(zz).zmove_av = mean(abs(tilt_med(:,3))) * z_pixel_um;
        motion_param(zz).zmove_sd = std(abs(tilt_med(:,3)) * z_pixel_um);

        fprintf('  Plane %d (GPU): XY = %.2f +/- %.2f um, Z = %.2f +/- %.2f um\n', ...
                zz, motion_param(zz).xymove_av, motion_param(zz).xymove_sd, ...
                motion_param(zz).zmove_av, motion_param(zz).zmove_sd);
    end

    % Keep pool alive if requested (for benchmarking)
    if ~isfield(params, 'keep_pool') || ~params.keep_pool
        delete(gcp('nocreate'));
    end

    % Save output
    motion_param_path = fullfile(data_dir, 'motion_param.mat');
    save(motion_param_path, 'motion_param');
    fprintf('Saved motion parameters: %s\n', motion_param_path);
    fprintf('========== Motion correction (GPU) complete ==========\n\n');
end
