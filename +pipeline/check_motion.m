function motion_param = check_motion(data_dir, params)
% CHECK_MOTION  Estimate tissue motion from SPIM time-series stacks.
%
%   motion_param = pipeline.check_motion(data_dir)
%   motion_param = pipeline.check_motion(data_dir, params)
%
% Uses FFT-based 2D cross-correlation on a grid of points to estimate
% XY and Z displacement over time for each z-plane. A reference is built
% from the first zcycle frames; each subsequent zcycle block is registered
% against it.
%
% Optional params fields:
%   .test_minutes        - Limit processing to first N minutes (for dev/testing)
%   .brightness_threshold - Grid-point brightness threshold (default: 120)
%   .pool_size           - Number of parfor workers (default: auto-detect)
%   .skip_viz            - Skip visualization generation (default: false)
%   .keep_pool           - Keep parallel pool alive after completion (default: false)
%
% Outputs (written to data_dir):
%   motion_param.mat - Struct array (one element per z-plane) with fields:
%       .tilt             - Raw displacement per grid point [n x 3]
%       .tilt_med         - Median-filtered displacement [n x 3]
%       .indslist         - Linear indices of valid grid points
%       .xymove_av / sd   - Mean / std XY motion (um)
%       .zmove_av / sd    - Mean / std Z motion (um)
%   motion.tif        - Per-plane motion visualization
%   motion_graph.tif  - Summary scatter plots
%
% See also pipeline.recog_wholefish, pipeline.get_cell_tcourse

    import util.*;
    import fileIO.*;

    %%% ---------------------------------------------------------------
    %%% 1. Load metadata
    %%% ---------------------------------------------------------------
    fprintf('\n========== Motion Correction (check_motion) ==========\n');
    fprintf('Data directory: %s\n', data_dir);

    if nargin < 2, params = struct(); end

    % Auto-detect parameters
    detected = util.auto_params.detect_all(data_dir);
    frame_rate = detected.frame_rate;
    stack_height = detected.stack_height;
    stack_width = detected.stack_width;
    n_zplanes = detected.n_zplanes;
    sdim = [stack_height, stack_width, n_zplanes];

    % Hardcoded physical constants (from acquisition setup)
    xy_pixel_um = 0.406;      % XY pixel size in microns
    z_pixel_um = 5;           % Z step in microns

    % Grid-point search radius (pixels)
    grid_radius = 30;

    % zcycle: number of consecutive frames to average into one timepoint
    % Formula: ~60 seconds worth of frames per timepoint
    zcycle_seconds = 60;
    zcycle = round(frame_rate * zcycle_seconds);
    fprintf('Formula: zcycle = round(frame_rate * %.0f) = round(%.2f * %.0f) = %d frames/timepoint\n', ...
            zcycle_seconds, frame_rate, zcycle_seconds, zcycle);

    % Brightness threshold for grid-point selection
    if isfield(params, 'brightness_threshold')
        brightness_threshold = params.brightness_threshold;
    else
        brightness_threshold = 120;
    end
    fprintf('Grid-point brightness threshold: %d\n', brightness_threshold);

    % Test-mode: limit frames
    if isfield(params, 'test_minutes') && ~isempty(params.test_minutes)
        max_frames = round(params.test_minutes * 60 * frame_rate);
        fprintf('TEST MODE: limiting to first %.0f minutes = %d frames\n', ...
                params.test_minutes, max_frames);
    else
        max_frames = Inf;
    end

    %%% ---------------------------------------------------------------
    %%% 2. Build reference stacks (first zcycle frames per plane)
    %%% ---------------------------------------------------------------
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

    fprintf('Building reference stacks from first %d frames per plane...\n', zcycle);
    parfor zz = 1:length(z_list)
        plane_file = sprintf('Plane%02d.stack', z_list(zz));
        plane_path = fullfile(data_dir, plane_file);
        plane_dims = reference_set(zz).sdim;

        frame_stack = fileIO.read_LSstack_fast2(plane_path, [plane_dims(1) plane_dims(2)], [1 zcycle]);
        ref_volume(:,:,zz) = util.create_zslice_ave_mex(uint16(frame_stack), ...
                            int32([plane_dims(1) plane_dims(2)]), int32(1:zcycle));
    end

    % Build 5-plane neighborhood for Z-motion estimation
    for i = 1:sdim(3)
        neighbor_planes = (-2:2) + i;
        valid_neighbors = neighbor_planes(neighbor_planes > 0 & neighbor_planes <= sdim(3));
        reference_set(i).refstack = ref_volume(:,:,valid_neighbors);
    end

    %%% ---------------------------------------------------------------
    %%% 3. Motion estimation — per z-plane (parallel)
    %%% ---------------------------------------------------------------
    % Pre-allocate struct arrays for parfor
    output = struct('masks', cell(1, length(z_list)), ...
                    'tilt', cell(1, length(z_list)), ...
                    'tilt_med', cell(1, length(z_list)), ...
                    'indslist2', cell(1, length(z_list)), ...
                    'regimg2', cell(1, length(z_list)));
    motion_param = struct('tilt', cell(1, length(z_list)), ...
                          'tilt_med', cell(1, length(z_list)), ...
                          'indslist', cell(1, length(z_list)), ...
                          'xymove_av', cell(1, length(z_list)), ...
                          'xymove_sd', cell(1, length(z_list)), ...
                          'zmove_av', cell(1, length(z_list)), ...
                          'zmove_sd', cell(1, length(z_list)));
    move_tcourse = struct('tcourse', cell(1, length(z_list)), ...
                          'rs_ave_xy', cell(1, length(z_list)), ...
                          'rs_std_xy', cell(1, length(z_list)), ...
                          'rs_ave_z', cell(1, length(z_list)), ...
                          'rs_std_z', cell(1, length(z_list)));

    fprintf('Estimating motion for %d z-planes...\n', length(z_list));

    % Progress bar via DataQueue (parfor-compatible)
    n_planes = length(z_list);
    wb = waitbar(0, 'Initializing...', 'Name', 'Drift Motion Check');
    q = parallel.pool.DataQueue;
    afterEach(q, @(k) waitbar(k/n_planes, wb, ...
        sprintf('Plane %d/%d', k, n_planes)));

    parfor zz = z_list
        plane_file = sprintf('Plane%02d.stack', z_list(zz));
        plane_path = fullfile(data_dir, plane_file);
        d = reference_set(zz).sdim;

        % Get total number of frames in this plane
        d2_full = double(fileIO.read_LSstack_info(plane_path, [d(1) d(2)]));
        n_frames_total = d2_full(3);

        % Apply test-mode limit
        if ~isinf(max_frames)
            n_frames_use = min(n_frames_total, max_frames);
        else
            n_frames_use = n_frames_total;
        end

        n_timepoints = floor(n_frames_use / zcycle);
        fprintf('  Plane %d: %d total frames -> %d timepoints (zcycle=%d)\n', ...
                zz, n_frames_use, n_timepoints, zcycle);

        move_tcourse(zz).tcourse = ((1:n_timepoints) - 1) * zcycle + round(zcycle / 2);

        % --- 3a. Read time-averaged stacks for each timepoint ---
        timepoint_stack = zeros(d(1), d(2), n_timepoints);
        for tp = 1:n_timepoints
            frame_range = [((tp-1)*zcycle + 1), tp*zcycle];
            fstack = fileIO.read_LSstack_fast2(plane_path, [d(1) d(2)], frame_range);
            timepoint_stack(:,:,tp) = util.create_zslice_ave_mex(uint16(fstack), ...
                                     int32([d(1) d(2)]), int32(1:zcycle));
        end

        % --- 3b. Place grid points on first timepoint ---
        reference_image = double(mean(timepoint_stack(:,:,1), 3));
        reg_img = repmat(util.imNormalize99(reference_image), [1 1 3]);
        reg_img_original = reg_img;

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

        % --- 3c. Filter grid points by brightness ---
        bright_enough = find(grid_start_inds(:,2) > brightness_threshold);
        valid_grid_inds = grid_start_inds(bright_enough, 1);

        % Mark valid grid points in visualization
        for i = 1:length(valid_grid_inds)
            gind = valid_grid_inds(i);
            reg_img(gind + patch_offset_inds) = 1;
            reg_img(gind + patch_offset_inds + d(1)*d(2)) = 0;
            reg_img(gind + patch_offset_inds + d(1)*d(2)*2) = 0;
        end

        % --- 3d. FFT cross-correlation for each grid point ---
        first_timepoint_img = double(timepoint_stack(:,:,1));
        displacement_xy = zeros(length(valid_grid_inds), 2, n_timepoints);
        displacement_z_raw = zeros(length(valid_grid_inds), n_timepoints);
        tilt_raw = zeros(length(valid_grid_inds), 3);

        z_neighbor_shifts = -2:2;

        for i = 1:length(valid_grid_inds)
            gind = valid_grid_inds(i);
            source_fft = fft2(reshape(first_timepoint_img(gind + patch_offset_inds), ...
                                      [grid_roi_width grid_roi_width]));

            for tp = 1:n_timepoints
                % XY: phase correlation
                target_patch = reshape(timepoint_stack(gind + patch_offset_inds + ...
                                      (tp-1)*d(1)*d(2)), [grid_roi_width grid_roi_width]);
                cross_power = fftshift(ifft2(source_fft .* conj(fft2(target_patch))));
                [~, maxpos] = max(abs(cross_power(:)));

                dy = -(mod(maxpos, grid_roi_width) - grid_radius - 1);
                if dy == -grid_radius - 1, dy = grid_radius; end
                dx = -(ceil(maxpos / grid_roi_width) - grid_radius - 1);

                displacement_xy(i, 1, tp) = dy;
                displacement_xy(i, 2, tp) = dx;

                move_offset = -dx * d(1) - dy;

                % Z: correlate with neighboring planes
                z_correlations = zeros(1, 5);
                valid_z_shifts = find(z_neighbor_shifts + zz > 0 & ...
                                      z_neighbor_shifts + zz <= d(3));
                for k = 1:length(valid_z_shifts)
                    z_target_vals = reference_set(zz).refstack(...
                        gind + move_offset + patch_offset_inds + ...
                        (k-1)*d(1)*d(2));
                    z_correlations(valid_z_shifts(k)) = ...
                        util.corrcoef_pair_mex(target_patch(:), z_target_vals(:));
                end
                [~, z_best] = max(z_correlations(valid_z_shifts));
                displacement_z_raw(i, tp) = z_neighbor_shifts(valid_z_shifts(z_best));
            end

            % Linear fit of displacement over time → cumulative tilt
            time_axis = (1:n_timepoints)';
            py = polyfit(time_axis, squeeze(displacement_xy(i, 1, :)), 1);
            px = polyfit(time_axis, squeeze(displacement_xy(i, 2, :)), 1);
            pz = polyfit(time_axis, squeeze(displacement_z_raw(i, :)), 1);

            tilt_raw(i, 1) = py(1) * (n_timepoints - 1);
            tilt_raw(i, 2) = px(1) * (n_timepoints - 1);
            tilt_raw(i, 3) = pz(1) * (n_timepoints - 1);
        end

        % --- 3e. Median filter tilts over 3×3 spatial neighborhood ---
        [r_kernel, c_kernel] = find(ones(3, 3));
        median_kernel_offsets = (c_kernel - 2) * n_grid_y + (r_kernel - 2);

        tilt_med = zeros(length(valid_grid_inds), 3);
        for dim = 1:3
            tilt_grid = zeros(n_grid_y, n_grid_x);
            mask_grid = zeros(n_grid_y, n_grid_x);

            for ii = 1:length(valid_grid_inds)
                tilt_grid(bright_enough(ii)) = tilt_raw(ii, dim);
                mask_grid(bright_enough(ii)) = 1;
            end

            for ii = 1:length(valid_grid_inds)
                neighbor_idx = bright_enough(ii) + median_kernel_offsets;
                in_bounds = neighbor_idx > 0 & neighbor_idx <= n_grid_x * n_grid_y;
                valid_neighbors = neighbor_idx(in_bounds);
                has_data = valid_neighbors(mask_grid(valid_neighbors) > 0);
                tilt_med(ii, dim) = median(tilt_grid(has_data));
            end
        end

        % --- 3f. Compute per-plane summary statistics ---
        xy_magnitude = sqrt(tilt_med(:,1).^2 + tilt_med(:,2).^2);

        motion_param(zz).tilt = tilt_raw;
        motion_param(zz).tilt_med = tilt_med;
        motion_param(zz).indslist = valid_grid_inds;
        motion_param(zz).xymove_av = mean(xy_magnitude) * xy_pixel_um;
        motion_param(zz).xymove_sd = std(xy_magnitude * xy_pixel_um, [], 1);
        motion_param(zz).zmove_av = mean(abs(tilt_med(:,3))) * z_pixel_um;
        motion_param(zz).zmove_sd = std(abs(tilt_med(:,3)) * z_pixel_um);

        % Store visualization data
        output(zz).masks = reg_img;
        output(zz).tilt = tilt_raw;
        output(zz).tilt_med = tilt_med;
        output(zz).indslist2 = valid_grid_inds;
        output(zz).regimg2 = reg_img_original;

        % Timecourse of motion magnitude
        xy_over_time = sqrt(squeeze(displacement_xy(:,1,:)).^2 + ...
                            squeeze(displacement_xy(:,2,:)).^2);
        z_over_time = squeeze(displacement_z_raw(:,:));

        move_tcourse(zz).rs_ave_xy = mean(xy_over_time);
        move_tcourse(zz).rs_std_xy = std(xy_over_time);
        move_tcourse(zz).rs_ave_z = mean(z_over_time);
        move_tcourse(zz).rs_std_z = std(z_over_time);

        fprintf('  Plane %d done: XY motion = %.2f +/- %.2f um, Z motion = %.2f +/- %.2f um\n', ...
                zz, motion_param(zz).xymove_av, motion_param(zz).xymove_sd, ...
                motion_param(zz).zmove_av, motion_param(zz).zmove_sd);
        send(q, zz);
    end
    close(wb);

    % Keep pool alive if requested (for benchmarking)
    if ~isfield(params, 'keep_pool') || ~params.keep_pool
        delete(gcp('nocreate'));
    end

    % Allow skipping visualization (for benchmarking)
    skip_viz = isfield(params, 'skip_viz') && params.skip_viz;

    if ~skip_viz
        %%% ---------------------------------------------------------------
        %%% 4. Generate visualizations
        %%% ---------------------------------------------------------------
    fprintf('Generating motion visualizations...\n');

    % --- Motion timecourse graphs per plane ---
    h1 = figure('Visible', 'off');
    set(h1, 'Position', [300 400 500 500]);
    movegraph = struct();
    xtcourse = move_tcourse(1).tcourse;

    for zz = 1:length(z_list)
        clf(h1);
        errorbar(xtcourse, move_tcourse(zz).rs_ave_xy * xy_pixel_um, ...
                 move_tcourse(zz).rs_std_xy * xy_pixel_um, 'mo-', 'linewidth', 2);
        hold on;
        errorbar(xtcourse, move_tcourse(zz).rs_ave_z * z_pixel_um, ...
                 move_tcourse(zz).rs_std_z * z_pixel_um, 'co-', 'linewidth', 2);
        hold off;
        ylim([-10 10]); xlim([0 max(xtcourse)]);
        title({['Plane ', num2str(zz), ': motion timecourse'], 'magenta=XY,  cyan=Z'});
        CC = getframe(h1);
        imwrite(CC.cdata, fullfile(data_dir, 'motion_tcourse.tif'), 'WriteMode', 'append');
    end
    close(h1);

    % --- Quiver + z-motion per plane ---
    h2 = figure('Visible', 'off');
    set(h2, 'Position', [150 150 400 800]);
    dim = size(output(1).masks);
    colorlist = [0 0 1; 0 1 1; 0 1 0; 1 1 0; 1 0 0];
    z_move_labels = [-2 -1 0 1 2];

    for zz = 1:length(z_list)
        clf(h2);
        % Quiver plot
        subplot(1, 2, 1);
        ha = gca; set(ha, 'Position', [0 0 0.5 1]);
        image(output(zz).regimg2); hold on;
        quiver(ceil(output(zz).indslist2 / dim(1)), ...
               mod(output(zz).indslist2, dim(1)), ...
               output(zz).tilt_med(:,2) * 10, ...
               output(zz).tilt_med(:,1) * 10, 0, 'linewidth', 2, 'Color', [1 0 0]);
        hold off; axis off;

        % Z-motion rectangles
        subplot(1, 2, 2);
        ha2 = gca; set(ha2, 'Position', [0.5 0 0.5 1]);
        image(output(zz).regimg2); hold on;
        for i = 1:5
            in_this_bin = find(round(output(zz).tilt_med(:,3)) == z_move_labels(i));
            for j = 1:length(in_this_bin)
                rectangle('Position', [ceil(output(zz).indslist2(in_this_bin(j)) / dim(1)), ...
                          mod(output(zz).indslist2(in_this_bin(j)), dim(1)), 20, 20], ...
                          'FaceColor', colorlist(i, :));
            end
        end
        hold off; axis off;

        CC = getframe(h2);
        imwrite(CC.cdata, fullfile(data_dir, 'motion.tif'), 'WriteMode', 'append');
    end
    close(h2);

    % --- Summary scatter plots ---
    h3 = figure('Visible', 'off');
    set(h3, 'Position', [100 100 1500 750]);

    subplot(1, 2, 1);
    for zz = z_list
        plot(ones(1, length(output(zz).indslist2)) * zz, ...
             sqrt(output(zz).tilt_med(:,1).^2 + output(zz).tilt_med(:,2).^2) * xy_pixel_um, '.');
        hold on;
    end
    errorbar([motion_param(z_list).xymove_av], [motion_param(z_list).xymove_sd], ...
             'r', 'LineWidth', 2, 'LineStyle', 'none');
    scatter(z_list, [motion_param.xymove_av], 'ro', 'fill'); hold off;
    xlim([min(z_list)-1 max(z_list)+1]); ylim([-1 5]);
    xlabel('Z-plane'); ylabel('XY motion (um)');
    title('XY motion per plane');

    subplot(1, 2, 2);
    for zz = z_list
        plot(ones(1, length(output(zz).indslist2)) * zz, ...
             abs(output(zz).tilt_med(:,3)) * z_pixel_um, '.');
        hold on;
    end
    errorbar([motion_param(z_list).zmove_av], [motion_param(z_list).zmove_sd], ...
             'r', 'LineWidth', 2, 'LineStyle', 'none');
    scatter(z_list, [motion_param.zmove_av], 'ro', 'fill'); hold off;
    xlim([min(z_list)-1 max(z_list)+1]); ylim([-1 10]);
    xlabel('Z-plane'); ylabel('Z motion (um)');
    title('Z motion per plane');

    set(h3, 'PaperPositionMode', 'auto');
    saveas(h3, fullfile(data_dir, 'motion_graph.tif'), 'tif');
    saveas(h3, fullfile(data_dir, 'motion_graph.eps'), 'eps');
    close(h3);
    end  % if ~skip_viz

    %%% ---------------------------------------------------------------
    %%% 5. Save outputs
    %%% ---------------------------------------------------------------
    motion_param_path = fullfile(data_dir, 'motion_param.mat');
    save(motion_param_path, 'motion_param');
    fprintf('Saved motion parameters: %s\n', motion_param_path);
    fprintf('========== Motion correction complete ==========\n\n');
end
