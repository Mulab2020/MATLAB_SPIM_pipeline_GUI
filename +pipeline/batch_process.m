function results = batch_process(list_file, br_threshold, params)
% BATCH_PROCESS  Run the pipeline on multiple data directories from a text file.
%
%   results = pipeline.batch_process(list_file, br_threshold)
%   results = pipeline.batch_process(list_file, br_threshold, params)
%
% Input list_file: path to a text file with one data directory per line.
% Empty lines and lines starting with '#' are ignored.
%
% Processing order (grouped by stage, not by directory):
%   Phase 1: Cell segmentation on ALL directories
%   Phase 2: Motion correction on ALL directories
%   Phase 3: Time course extraction on ALL directories
%
% Each stage checks for existing output and skips if already present
% (resumable). Errors in one directory do not stop the batch.
%
% Optional params fields:
%   .skip_segmentation — skip Phase 1 (use when seg was done interactively)
%   .skip_motion       — skip Phase 2 entirely
%   .force_rerun       — re-run even if output files exist
%   .use_gpu           — use GPU variant of check_motion
%   .enable_detrending, .enable_remove_duplicates, .enable_motion_filter
%     — passed through to get_cell_tcourse
%
% Returns a table summarizing results for each directory.

    import pipeline.*;

    %%% ---------------------------------------------------------------
    %%% 1. Parse the batch file
    %%% ---------------------------------------------------------------
    fprintf('\n========== Batch Processing ==========\n');
    fprintf('Batch file: %s\n', list_file);

    if nargin < 3, params = struct(); end
    if ~isfield(params, 'force_rerun'), params.force_rerun = false; end
    if ~isfield(params, 'skip_segmentation'), params.skip_segmentation = false; end
    if ~isfield(params, 'skip_motion'), params.skip_motion = false; end

    % Abort support: if an abort_fig handle is provided, check its
    % UserData.batch_abort flag between directories.
    has_abort = isfield(params, 'abort_fig') && isvalid(params.abort_fig);
    if has_abort
        abort_fig = params.abort_fig;
    end

    function aborted = check_abort()
        aborted = false;
        if has_abort && isvalid(abort_fig)
            try
                if isprop(abort_fig, 'UserData') && ...
                   isstruct(abort_fig.UserData) && ...
                   isfield(abort_fig.UserData, 'batch_abort') && ...
                   abort_fig.UserData.batch_abort
                    aborted = true;
                end
            catch
            end
        end
    end

    fid = fopen(list_file, 'r');
    raw_lines = textscan(fid, '%s', 'Delimiter', '\n', 'CommentStyle', '#');
    fclose(fid);
    raw_lines = raw_lines{1};

    % Filter: trim whitespace, skip empty lines
    dir_list = {};
    for i = 1:length(raw_lines)
        trimmed = strtrim(raw_lines{i});
        if ~isempty(trimmed) && ~startsWith(trimmed, '#')
            dir_list{end+1} = trimmed;
        end
    end

    n_dirs = length(dir_list);
    fprintf('Found %d directories in batch list\n', n_dirs);

    % Validate paths
    valid_mask = true(1, n_dirs);
    for i = 1:n_dirs
        if ~exist(dir_list{i}, 'dir')
            fprintf('  WARNING: directory not found, will skip: %s\n', dir_list{i});
            valid_mask(i) = false;
        end
    end
    dir_list = dir_list(valid_mask);
    n_dirs = length(dir_list);
    fprintf('%d valid directories to process\n', n_dirs);

    % Initialize results tracking
    results = table();
    results.Directory = dir_list(:);
    results.Segmentation = repmat({'pending'}, n_dirs, 1);
    results.Motion = repmat({'pending'}, n_dirs, 1);
    results.Timecourse = repmat({'pending'}, n_dirs, 1);
    results.NCells = zeros(n_dirs, 1);

    %%% ---------------------------------------------------------------
    %%% 2. Phase 1: Cell segmentation (ALL directories)
    %%% ---------------------------------------------------------------
    if params.skip_segmentation
        fprintf('\n===== Phase 1: Cell Segmentation (SKIPPED — already done) =====\n');
        for i = 1:n_dirs
            d = dir_list{i};
            cell_info_file = fullfile(d, 'cell_info.mat');
            if exist(cell_info_file, 'file')
                results.Segmentation{i} = 'OK';
                loaded = load(cell_info_file, 'cell_info');
                results.NCells(i) = length(loaded.cell_info);
            else
                results.Segmentation{i} = 'FAIL';
                results.NCells(i) = 0;
            end
        end
    else
        fprintf('\n===== Phase 1: Cell Segmentation =====\n');
        for i = 1:n_dirs
            d = dir_list{i};
            fprintf('\n--- Directory %d/%d: %s ---\n', i, n_dirs, d);

            % Check if already done
            cell_info_file = fullfile(d, 'cell_info.mat');
            if exist(cell_info_file, 'file') && ~params.force_rerun
                fprintf('  cell_info.mat exists — skipping segmentation\n');
                results.Segmentation{i} = 'skipped';
                loaded = load(cell_info_file, 'cell_info');
                results.NCells(i) = length(loaded.cell_info);
                continue;
            end

            try
                cell_info = recog_wholefish(d, br_threshold);
                results.Segmentation{i} = 'OK';
                results.NCells(i) = length(cell_info);
            catch ME
                fprintf('  ERROR in segmentation: %s\n', ME.message);
                results.Segmentation{i} = 'FAIL';
            end
        end
    end

    %%% ---------------------------------------------------------------
    %%% 3. Phase 2: Motion correction (ALL directories)
    %%% ---------------------------------------------------------------
    if params.skip_motion
        fprintf('\n===== Phase 2: Motion Correction (SKIPPED) =====\n');
        for i = 1:n_dirs
            if strcmp(results.Segmentation{i}, 'FAIL')
                results.Motion{i} = 'SKIP';
            else
                results.Motion{i} = 'skipped';
            end
        end
    else
        fprintf('\n===== Phase 2: Motion Correction =====\n');
        for i = 1:n_dirs
            % Abort check
            if check_abort()
                fprintf('  ABORT requested — stopping motion correction\n');
                results.Motion(i:end) = {'aborted'};
                break;
            end
            d = dir_list{i};
            fprintf('\n--- Directory %d/%d: %s ---\n', i, n_dirs, d);

            % Skip if segmentation failed
            if strcmp(results.Segmentation{i}, 'FAIL')
                fprintf('  Segmentation failed — skipping motion correction\n');
                results.Motion{i} = 'SKIP';
                continue;
            end

            % Check if already done
            motion_file = fullfile(d, 'motion_param.mat');
            if exist(motion_file, 'file') && ~params.force_rerun
                fprintf('  motion_param.mat exists — skipping motion correction\n');
                results.Motion{i} = 'skipped';
                continue;
            end

            try
                if isfield(params, 'use_gpu') && params.use_gpu
                    check_motion_gpu(d, params);
                else
                    check_motion(d, params);
                end
                results.Motion{i} = 'OK';
            catch ME
                fprintf('  ERROR in motion correction: %s\n', ME.message);
                results.Motion{i} = 'FAIL';
            end
        end
    end

    %%% ---------------------------------------------------------------
    %%% 4. Phase 3: Time course extraction (ALL directories)
    %%% ---------------------------------------------------------------
    fprintf('\n===== Phase 3: Time Course Extraction =====\n');
    for i = 1:n_dirs
        % Abort check
        if check_abort()
            fprintf('  ABORT requested — stopping time course extraction\n');
            results.Timecourse(i:end) = {'aborted'};
            break;
        end
        d = dir_list{i};
        fprintf('\n--- Directory %d/%d: %s ---\n', i, n_dirs, d);

        % Skip if either prior stage failed
        if strcmp(results.Segmentation{i}, 'FAIL') || strcmp(results.Motion{i}, 'FAIL')
            fprintf('  Prior stage failed — skipping time course extraction\n');
            results.Timecourse{i} = 'SKIP';
            continue;
        end

        % Check if already done
        processed_file = fullfile(d, 'cell_resp_processed.stackf');
        if exist(processed_file, 'file') && ~params.force_rerun
            fprintf('  cell_resp_processed.stackf exists — skipping time course\n');
            results.Timecourse{i} = 'skipped';
            continue;
        end

        try
            get_cell_tcourse(d, params);
            results.Timecourse{i} = 'OK';
        catch ME
            fprintf('  ERROR in time course extraction: %s\n', ME.message);
            results.Timecourse{i} = 'FAIL';
        end
    end

    %%% ---------------------------------------------------------------
    %%% 5. Print summary
    %%% ---------------------------------------------------------------
    fprintf('\n\n========== Batch Processing Summary ==========\n');
    fprintf('%-60s | %-12s | %-12s | %-12s | %8s\n', ...
            'Directory', 'Segmentation', 'Motion', 'Timecourse', 'Cells');
    fprintf('%-60s-+-%-12s-+-%-12s-+-%-12s-+-%8s\n', ...
            repmat('-', 1, 60), repmat('-', 1, 12), repmat('-', 1, 12), ...
            repmat('-', 1, 12), repmat('-', 1, 8));

    for i = 1:n_dirs
        % Truncate directory name for display
        dname = dir_list{i};
        if length(dname) > 58
            dname = ['...' dname(end-55:end)];
        end
        fprintf('%-60s | %-12s | %-12s | %-12s | %8d\n', ...
                dname, results.Segmentation{i}, results.Motion{i}, ...
                results.Timecourse{i}, results.NCells(i));
    end

    n_ok_seg = sum(strcmp(results.Segmentation, 'OK'));
    n_ok_mot = sum(strcmp(results.Motion, 'OK'));
    n_ok_tc  = sum(strcmp(results.Timecourse, 'OK'));
    n_skip_seg = sum(strcmp(results.Segmentation, 'skipped'));
    n_skip_mot = sum(strcmp(results.Motion, 'skipped'));
    n_skip_tc  = sum(strcmp(results.Timecourse, 'skipped'));
    n_fail_seg = sum(strcmp(results.Segmentation, 'FAIL'));
    n_fail_mot = sum(strcmp(results.Motion, 'FAIL'));
    n_fail_tc  = sum(strcmp(results.Timecourse, 'FAIL'));

    fprintf('\nSegmentation:  %d OK, %d skipped, %d failed\n', n_ok_seg, n_skip_seg, n_fail_seg);
    fprintf('Motion:        %d OK, %d skipped, %d failed\n', n_ok_mot, n_skip_mot, n_fail_mot);
    fprintf('Time course:   %d OK, %d skipped, %d failed\n', n_ok_tc, n_skip_tc, n_fail_tc);
    fprintf('================================================\n\n');
end
