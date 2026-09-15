function run_pipeline(data_dir, br_threshold, params)
% RUN_PIPELINE  Run the complete SPIM pipeline on a data directory.
%
%   run_pipeline(data_dir, br_threshold)
%   run_pipeline(data_dir, br_threshold, params)
%
% Runs all three stages in sequence:
%   1. Cell segmentation (recog_wholefish)
%   2. Motion correction (check_motion)
%   3. Time course extraction (get_cell_tcourse)
%
% If br_threshold is omitted or empty, you will be prompted for it.
%
% Optional params struct fields (time course extraction unless noted):
%   .test_minutes            - Limit to first N minutes (for dev/testing)
%   .use_gpu                 - Use GPU for motion correction (default: false)
%   .enable_detrending       - Rolling percentile dF/F normalization
%                              (default: true)
%   .detrend_window_frames   - Rolling window length in frames (default: 600)
%   .detrend_percentile      - Baseline percentile, 0-100 (default: 15)
%   .detrend_offset          - Offset added to F0 in the dF/F denominator
%                              (default: 10)
%   .enable_photobleach_fit  - Legacy exponential photobleaching fit,
%                              applied before detrending (default: false)
%   .baseline_window_seconds - Exp-fit baseline window in seconds (default: 180)
%   .enable_remove_duplicates - Remove double-counted cells (default: false)
%   .dedup_corr_threshold    - Correlation threshold for dedup (default: 0.7)
%   .enable_motion_filter    - Motion-based cell filtering (default: false)
%   .motion_threshold_pixels - Motion threshold in pixels (default: 1)
%
% Example:
%   run_pipeline('Z:\GJT\Matlab\SPIM_pipeline_refactor\sample_data\...', 120)
%
% See also pipeline.recog_wholefish, pipeline.check_motion, pipeline.get_cell_tcourse

    % Ensure v1_pipeline is on the path
    v1_root = fileparts(mfilename('fullpath'));
    if isempty(which('pipeline.recog_wholefish'))
        addpath(v1_root);
    end

    if nargin < 2, br_threshold = []; end
    if nargin < 3, params = struct(); end

    % Stage 1: Cell segmentation
    fprintf('\n==================== STAGE 1/3: CELL SEGMENTATION ====================\n');
    pipeline.recog_wholefish(data_dir, br_threshold);

    % Stage 2: Motion correction
    fprintf('\n==================== STAGE 2/3: MOTION CORRECTION ====================\n');
    if isfield(params, 'use_gpu') && params.use_gpu
        pipeline.check_motion_gpu(data_dir, params);
    else
        pipeline.check_motion(data_dir, params);
    end

    % Stage 3: Time course extraction
    fprintf('\n==================== STAGE 3/3: TIME COURSE EXTRACTION ===============\n');
    pipeline.get_cell_tcourse(data_dir, params);

    fprintf('\n==================== PIPELINE COMPLETE ================================\n');
end
