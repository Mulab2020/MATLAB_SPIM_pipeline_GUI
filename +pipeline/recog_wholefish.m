function cell_info = recog_wholefish(data_dir, br_threshold, show_histogram)
% RECOG_WHOLESFISH  Cell segmentation from average anatomy stack.
%
%   cell_info = pipeline.recog_wholefish(data_dir)
%   cell_info = pipeline.recog_wholefish(data_dir, br_threshold)
%   cell_info = pipeline.recog_wholefish(data_dir, br_threshold, show_histogram)
%
% Identifies neurons in a SPIM average anatomy stack using two-round
% local contrast + local maxima detection. Only parameter: brightness
% threshold. If omitted, a suggestion is computed from the data histogram
% and the user is prompted once.
%
% Inputs:
%   data_dir       - Path to registered data directory containing ave.tif
%   br_threshold   - Brightness threshold (optional; auto-detected if empty)
%   show_histogram - Show intensity histogram figure (optional, default true).
%                    Set to false when called from GUI to avoid redundant popup.
%
% Outputs (written to data_dir):
%   cell_info.mat            - Struct array of detected cells
%   cellmask_<threshold>.tif - RGB visualization of cell masks
%
% See also pipeline.check_motion, pipeline.get_cell_tcourse

    import util.*;
    import fileIO.*;

    %%% ---------------------------------------------------------------
    %%% 1. Load average anatomy stack
    %%% ---------------------------------------------------------------
    ave_file = fullfile(data_dir, 'ave.tif');

    if ~exist(ave_file, 'file')
        error('recog_wholefish:missingFile', ...
              'ave.tif not found in: %s\nExpected a pre-computed average anatomy stack.', data_dir);
    end

    fprintf('\n========== Cell Recognition (recog_wholefish) ==========\n');
    fprintf('Data directory: %s\n', data_dir);
    fprintf('Loading average stack from ave.tif ...\n');

    t_start = tic;
    info = imfinfo(ave_file);
    n_zplanes_ave = length(info);

    % Read all z-slices
    stack_av = zeros(info(1).Height, info(1).Width, n_zplanes_ave, 'uint16');
    for k = 1:n_zplanes_ave
        stack_av(:,:,k) = imread(ave_file, k);
    end

    dim = size(stack_av);
    if length(dim) == 2
        dim = [dim, 1];
    end

    fprintf('Stack dimensions: %d x %d x %d (H x W x Z planes)\n', dim(1), dim(2), dim(3));

    %%% ---------------------------------------------------------------
    %%% 2. Determine brightness threshold
    %%% ---------------------------------------------------------------
    % Default: show histogram (suppress when called from GUI)
    if nargin < 3 || isempty(show_histogram)
        show_histogram = true;
    end

    % Show histogram for user reference (unless suppressed, e.g. from GUI)
    if show_histogram
        figure('Name', 'Intensity Histogram', 'NumberTitle', 'off');
        histogram(stack_av(:), 200);
        title('Pixel intensity distribution of average stack');
        xlabel('Intensity'); ylabel('Count');
        drawnow;
    end

    % Compute suggestion: 85th percentile of pixel intensities
    sorted_pixels = sort(double(stack_av(:)), 'ascend');
    suggested_threshold = sorted_pixels(round(0.85 * length(sorted_pixels)));
    default_threshold = 120;

    if nargin < 2 || isempty(br_threshold)
        fprintf('\nBrightness threshold: default = %d, 85th-percentile suggestion = %.0f\n', ...
                default_threshold, suggested_threshold);
        br_threshold = input('Enter brightness threshold (press Enter for default): ');
        if isempty(br_threshold)
            br_threshold = default_threshold;
        end
    else
        fprintf('Using brightness threshold: %.0f (user-provided)\n', br_threshold);
    end

    %%% ---------------------------------------------------------------
    %%% 3. Algorithm parameters
    %%% ---------------------------------------------------------------
    cont_threshold = 5;      % Local contrast threshold
    cell_radius = 5;         % Cell radius in pixels (5=nuclear, 6=cytosolic, 12=single-plane)

    fprintf('Parameters: cell_radius=%d, contrast_threshold=%d, brightness_threshold=%d\n', ...
            cell_radius, cont_threshold, br_threshold);

    %%% ---------------------------------------------------------------
    %%% 4. Set up morphological filters
    %%% ---------------------------------------------------------------
    averaging_radius = round(cell_radius / 2) + 1;
    [averaging_disk, averaging_strel, r_ave, c_ave, averaging_offsets] = ...
        make_recog_disk(averaging_radius, dim);
    [max_disk, max_strel, r_max, c_max, max_offsets] = ...
        make_recog_disk(cell_radius + 2, dim);

    % Small disk for morphological cleanup of contrast image
    cleanup_disk = makeDisk2(3, 7);
    cleanup_strel = strel(cleanup_disk);

    %%% ---------------------------------------------------------------
    %%% 5. Build rank-calculation template
    %%% ---------------------------------------------------------------
    padded_radius = cell_radius * 2;
    padded_dims = [dim(1) + padded_radius*2, dim(2) + padded_radius*2];
    padded_mask = zeros(padded_dims);
    padded_mask(padded_radius+1:end-padded_radius, padded_radius+1:end-padded_radius) = 1;
    padded_mask_inds = find(padded_mask);

    [rank_disk, ~, ~, ~, rank_offset_inds] = make_recog_disk(padded_radius, padded_dims);
    rank_ones = double(maskones2D_mex(int32([dim(1) dim(2)]), ...
                                      int32(rank_disk), int32(size(rank_disk))))';

    %%% ---------------------------------------------------------------
    %%% 6. Recognize cells — per z-plane
    %%% ---------------------------------------------------------------
    z_planes = 1:dim(3);
    n_pixels_per_plane = dim(1) * dim(2);
    all_plane_mask = zeros(dim(1), dim(2));

    cell_info = struct();
    cell_color = zeros([dim(1) dim(2)*2+1 dim(3) 3], 'uint8');
    total_cells = 0;

    wb = waitbar(0, 'Segmenting cells...', 'Name', 'Cell Recognition');

    for z = z_planes
        waitbar(z / dim(3), wb, sprintf('Plane %d/%d', z, dim(3)));
        plane_image = stack_av(:,:,z);
        all_plane_mask(:) = 0;

        % --- 6a. Build candidate pixel mask (contrast + brightness) ---
        contrast_image = local_contrast_mex(single(plane_image), int32(32), single(cont_threshold));
        contrast_image = imdilate(imerode(contrast_image, cleanup_strel), cleanup_strel);
        candidate_mask = contrast_image .* uint8(plane_image > br_threshold);
        candidate_pixels = find(candidate_mask);

        if isempty(candidate_pixels)
            total_cells_in_plane = 0;
            cell_label_image = zeros(size(plane_image));
            fprintf('  Plane %d/%d: no candidates found (all pixels below threshold or contrast)\n', ...
                    z, dim(3));
        else
            % --- 6b. Round 1: find bright cells ---
            rank_image = calc_rank_simple2(plane_image, rank_ones, cell_radius*2, ...
                                           padded_mask, padded_mask_inds, ...
                                           rank_offset_inds, candidate_pixels);

            averaged_rank = double(local_average_mex(single(rank_image), ...
                                                     int32(c_ave), int32(r_ave), ...
                                                     int32(candidate_pixels)));

            max_rank = double(local_max_mex(single(averaged_rank), ...
                                            int32(c_max), int32(r_max), ...
                                            int32(candidate_pixels)));

            % Cells whose local average equals the local max (and above floor)
            cell_center_inds_round1 = find(max_rank(candidate_pixels) > 0 & ...
                                           averaged_rank(candidate_pixels) > 0.4);

            round1_mask = zeros(dim(1), dim(2));
            for i = 1:length(cell_center_inds_round1)
                seed_ind = candidate_pixels(cell_center_inds_round1(i)) + averaging_offsets;
                seed_ind(seed_ind > n_pixels_per_plane | seed_ind < 1) = [];
                round1_mask(seed_ind) = 1;
            end

            all_plane_mask = round1_mask;

            % --- 6c. Round 2: find remaining cells in gaps ---
            exclusion_mask = ones(size(plane_image), 'uint8') - ...
                             imdilate(uint8(all_plane_mask), max_strel);
            exclusion_mask = imdilate(imerode(exclusion_mask, cleanup_strel), cleanup_strel);

            remaining_candidates = candidate_pixels(exclusion_mask(candidate_pixels) > 0);

            if ~isempty(remaining_candidates)
                rank_image_2 = calc_rank_simple2(plane_image, rank_ones, cell_radius*2, ...
                                                 padded_mask, padded_mask_inds, ...
                                                 rank_offset_inds, remaining_candidates);

                averaged_rank_2 = double(local_average_mex(single(rank_image_2), ...
                                                           int32(c_ave), int32(r_ave), ...
                                                           int32(remaining_candidates)));

                max_rank_2 = double(local_max_mex(single(averaged_rank_2), ...
                                                  int32(c_ave), int32(r_ave), ...
                                                  int32(remaining_candidates)));

                cell_center_inds_round2 = find(max_rank_2(remaining_candidates) > 0 & ...
                                               averaged_rank_2(remaining_candidates) > 0.4);

                round2_mask = zeros(dim(1), dim(2));
                for i = 1:length(cell_center_inds_round2)
                    seed_ind = remaining_candidates(cell_center_inds_round2(i)) + averaging_offsets;
                    seed_ind(seed_ind > n_pixels_per_plane | seed_ind < 1) = [];
                    round2_mask(seed_ind) = 1;
                end

                all_plane_mask = all_plane_mask + round2_mask;
            end

            % --- 6d. Label and store cells ---
            [cell_label_image, total_cells_in_plane] = bwlabel(all_plane_mask, 8);

            if total_cells_in_plane > 0
                cell_info = create_cell_info_fish(cell_info, cell_label_image, ...
                                                  total_cells_in_plane, z);
            end
        end

        % --- 6e. Build color visualization for this plane ---
        cell_color(:,:,z,:) = reshape(imMask2D_fish(plane_image, cell_label_image, candidate_pixels), ...
                                      [dim(1) dim(2)*2+1 1 3]);

        total_cells = total_cells + total_cells_in_plane;
        fprintf('  Plane %d/%d: found %d cells (cumulative total: %d)\n', ...
                z, dim(3), total_cells_in_plane, total_cells);
    end

    close(wb);

    %%% ---------------------------------------------------------------
    %%% 7. Save outputs
    %%% ---------------------------------------------------------------
    cellmask_filename = sprintf('cellmask_%d_%d_%d.tif', ...
                                br_threshold, cont_threshold, cell_radius);
    cellmask_path = fullfile(data_dir, cellmask_filename);

    fprintf('\nWriting cell mask: %s\n', cellmask_filename);
    write_colortiff_mex(cellmask_path, cell_color, int32(size(cell_color)));

    cell_info_path = fullfile(data_dir, 'cell_info.mat');
    seg_params = struct();
    seg_params.br_threshold = br_threshold;
    seg_params.cont_threshold = cont_threshold;
    seg_params.cell_radius = cell_radius;
    save(cell_info_path, 'cell_info', 'seg_params');
    fprintf('Saved cell info: %s (threshold=%d)\n', cell_info_path, br_threshold);

    elapsed = toc(t_start);
    fprintf('\n========== Cell recognition complete ==========\n');
    fprintf('Total cells found: %d across %d planes\n', total_cells, dim(3));
    fprintf('Elapsed time: %.1f seconds\n', elapsed);
    fprintf('Outputs:\n  %s\n  %s\n', cellmask_path, cell_info_path);
    fprintf('================================================\n\n');
end
