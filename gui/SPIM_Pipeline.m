function SPIM_Pipeline()
% SPIM_PIPELINE  GUI for the SPIM image processing pipeline.
%
%   gui.SPIM_Pipeline()
%
% A single-window application that wraps the three pipeline stages:
%   1. Cell segmentation (recog_wholefish)   — interactive threshold
%   2. Motion correction (check_motion)      — auto-run
%   3. Time course extraction (get_cell_tcourse) — auto-run
%
% Layout: Left sidebar (controls) + Right panel (preview + output)

    % Ensure packages are on path
    v1_root = fileparts(fileparts(mfilename('fullpath')));
    if isempty(which('pipeline.recog_wholefish'))
        addpath(v1_root);
    end

    %%% ---------------------------------------------------------------
    %%% Build the GUI
    %%% ---------------------------------------------------------------
    fig = uifigure('Name', 'SPIM Pipeline v1.4', ...
                   'Position', [100 100 1200 820], ...
                   'Resize', 'on');

    % Main layout: 1 row, 2 columns (left sidebar + right panel)
    main_grid = uigridlayout(fig, [1 2], ...
                             'ColumnWidth', {320, '1x'}, ...
                             'Padding', 5, 'ColumnSpacing', 5);

    %%% ===============================================================
    %%% LEFT SIDEBAR — Controls
    %%% ===============================================================
    left_panel = uipanel(main_grid, 'BorderType', 'none');
    left_panel.Layout.Column = 1;

    left_grid = uigridlayout(left_panel, [7 1], ...
                             'RowHeight', {45, 120, 85, 215, 35, '1x', 35}, ...
                             'Padding', 5, 'RowSpacing', 8);

    % --- Data directory ---
    dir_row = uigridlayout(left_grid, [1 3], ...
                           'ColumnWidth', {50, '1x', 30}, ...
                           'Padding', 0, 'ColumnSpacing', 3);
    dir_row.Layout.Row = 1;
    uilabel(dir_row, 'Text', 'Data:', 'FontWeight', 'bold');
    dir_field = uieditfield(dir_row, 'text', ...
                            'Editable', 'off', ...
                            'Placeholder', 'Browse for data dir...');
    dir_field.Layout.Column = 2;
    browse_btn = uibutton(dir_row, 'push', 'Text', '...', ...
                          'ButtonPushedFcn', @(~,~) browse_callback());
    browse_btn.Layout.Column = 3;

    % --- Step 1: Cell Segmentation ---
    step1_panel = uipanel(left_grid, 'Title', 'Step 1: Cell Segmentation', ...
                          'FontWeight', 'bold');
    step1_panel.Layout.Row = 2;
    step1_grid = uigridlayout(step1_panel, [3 1], ...
                              'RowHeight', {25, 25, '1x'}, ...
                              'Padding', 5, 'RowSpacing', 3);

    % Threshold label + slider
    thresh_row = uigridlayout(step1_grid, [1 3], ...
                              'ColumnWidth', {65, '1x', 50}, ...
                              'Padding', 0, 'ColumnSpacing', 3);
    thresh_row.Layout.Row = 1;
    uilabel(thresh_row, 'Text', 'Threshold:', 'FontWeight', 'bold');
    thresh_slider = uislider(thresh_row, ...
                             'Limits', [50 5000], ...
                             'Value', 120);
    thresh_slider.Layout.Column = 2;
    thresh_field = uieditfield(thresh_row, 'numeric', ...
                               'Limits', [50 5000], ...
                               'Value', 120);
    thresh_field.Layout.Column = 3;

    % Link slider and field
    thresh_slider.ValueChangedFcn = @(s,~) set(thresh_field, 'Value', round(s.Value));
    thresh_field.ValueChangedFcn = @(f,~) set(thresh_slider, 'Value', f.Value);

    % Run button
    seg_btn = uibutton(step1_grid, 'push', 'Text', 'Run Segmentation', ...
                       'BackgroundColor', [0.3 0.7 0.3], ...
                       'FontWeight', 'bold', ...
                       'ButtonPushedFcn', @(~,~) run_segmentation());
    seg_btn.Layout.Row = 2;

    % Cell count label
    cell_count_label = uilabel(step1_grid, 'Text', 'No segmentation yet');
    cell_count_label.Layout.Row = 3;

    % --- Step 2: Check Drift Motion ---
    step2_panel = uipanel(left_grid, 'Title', 'Step 2: Check Drift Motion', ...
                          'FontWeight', 'bold');
    step2_panel.Layout.Row = 3;
    step2_grid = uigridlayout(step2_panel, [3 1], ...
                              'RowHeight', {25, 25, 20}, ...
                              'Padding', 5, 'RowSpacing', 3);

    gpu_check = uicheckbox(step2_grid, 'Text', 'Use GPU (if available)', 'Value', false);
    gpu_check.Layout.Row = 1;

    motion_btn = uibutton(step2_grid, 'push', 'Text', 'Run Drift Motion Check', ...
                          'Enable', 'off', ...
                          'BackgroundColor', [0.3 0.7 0.3], ...
                          'FontWeight', 'bold', ...
                          'ButtonPushedFcn', @(~,~) run_motion());
    motion_btn.Layout.Row = 2;

    motion_status = uilabel(step2_grid, 'Text', 'Waiting for segmentation...', ...
                            'FontAngle', 'italic');
    motion_status.Layout.Row = 3;

    % --- Step 3: Time Course Extraction ---
    step3_panel = uipanel(left_grid, 'Title', 'Step 3: Time Course Extraction', ...
                          'FontWeight', 'bold');
    step3_panel.Layout.Row = 4;
    step3_grid = uigridlayout(step3_panel, [7 4], ...
                              'RowHeight', {24, 24, 24, 24, 24, 28, 22}, ...
                              'ColumnWidth', {95, 45, 90, 55}, ...
                              'Padding', 5, 'RowSpacing', 3, 'ColumnSpacing', 3);

    detrend_cb = uicheckbox(step3_grid, 'Text', 'Rolling detrend', ...
        'Value', true, ...
        'Tooltip', 'Normalize each trace as dF/F = (F - bg - F0) / (max(F0,0) + offset), where F0 is a per-sample sliding-window percentile baseline (default on)');
    detrend_cb.Layout.Row = 1;
    detrend_cb.Layout.Column = [1 2];

    expfit_cb = uicheckbox(step3_grid, 'Text', 'Exp bleach fit', ...
        'Value', false, ...
        'Tooltip', 'Legacy exponential photobleaching baseline correction, applied before detrending (default off)');
    expfit_cb.Layout.Row = 1;
    expfit_cb.Layout.Column = [3 4];

    lbl = uilabel(step3_grid, 'Text', 'Window:', ...
        'Tooltip', 'Sliding-window length for the rolling percentile baseline, in frames (default 600)');
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    detrend_window_field = uieditfield(step3_grid, 'numeric', ...
        'Limits', [1 1e6], 'Value', 600, ...
        'Tooltip', 'Sliding-window length for the rolling percentile baseline, in frames (default 600)');
    detrend_window_field.Layout.Row = 2; detrend_window_field.Layout.Column = 2;

    lbl = uilabel(step3_grid, 'Text', 'Percentile:', ...
        'Tooltip', 'Baseline percentile within each rolling window, 0-100 (default 15)');
    lbl.Layout.Row = 2; lbl.Layout.Column = 3;
    detrend_pct_field = uieditfield(step3_grid, 'numeric', ...
        'Limits', [0 100], 'Value', 15, ...
        'Tooltip', 'Baseline percentile within each rolling window, 0-100 (default 15)');
    detrend_pct_field.Layout.Row = 2; detrend_pct_field.Layout.Column = 4;

    lbl = uilabel(step3_grid, 'Text', 'F0 offset:', ...
        'Tooltip', 'Offset added to F0 in the dF/F denominator to avoid division by near-zero baselines (default 10)');
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    detrend_offset_field = uieditfield(step3_grid, 'numeric', ...
        'Limits', [0 1e6], 'Value', 10, ...
        'Tooltip', 'Offset added to F0 in the dF/F denominator to avoid division by near-zero baselines (default 10)');
    detrend_offset_field.Layout.Row = 3; detrend_offset_field.Layout.Column = 2;

    lbl = uilabel(step3_grid, 'Text', 'Exp window:', ...
        'Tooltip', 'Baseline window for the exponential photobleaching fit, in seconds; also the epoch length for duplicate-cell correlation (default 180)');
    lbl.Layout.Row = 3; lbl.Layout.Column = 3;
    expfit_window_field = uieditfield(step3_grid, 'numeric', ...
        'Limits', [10 1e6], 'Value', 180, ...
        'Tooltip', 'Baseline window for the exponential photobleaching fit, in seconds; also the epoch length for duplicate-cell correlation (default 180)');
    expfit_window_field.Layout.Row = 3; expfit_window_field.Layout.Column = 4;

    dedup_cb = uicheckbox(step3_grid, 'Text', 'Dedup cells', ...
        'Value', false, ...
        'Tooltip', 'Remove double-counted cells on adjacent z-planes by correlation (threshold in "Corr thr", default 0.7)');
    dedup_cb.Layout.Row = 4;
    dedup_cb.Layout.Column = [1 2];

    lbl = uilabel(step3_grid, 'Text', 'Corr thr:', ...
        'Tooltip', 'Correlation threshold for duplicate-cell removal (default 0.7)');
    lbl.Layout.Row = 4; lbl.Layout.Column = 3;
    dedup_corr_field = uieditfield(step3_grid, 'numeric', ...
        'Limits', [0 1], 'Value', 0.7, ...
        'Tooltip', 'Correlation threshold for duplicate-cell removal (default 0.7)');
    dedup_corr_field.Layout.Row = 4; dedup_corr_field.Layout.Column = 4;

    motionfilt_cb = uicheckbox(step3_grid, 'Text', 'Motion filtering', ...
        'Value', false, ...
        'Tooltip', 'Remove cells located near grid points with motion above the threshold in "Motion (px)" (requires motion_param.mat)');
    motionfilt_cb.Layout.Row = 5;
    motionfilt_cb.Layout.Column = [1 2];

    lbl = uilabel(step3_grid, 'Text', 'Motion (px):', ...
        'Tooltip', 'Motion threshold in pixels for motion-based cell filtering (default 1)');
    lbl.Layout.Row = 5; lbl.Layout.Column = 3;
    motion_thr_field = uieditfield(step3_grid, 'numeric', ...
        'Limits', [0 1e6], 'Value', 1, ...
        'Tooltip', 'Motion threshold in pixels for motion-based cell filtering (default 1)');
    motion_thr_field.Layout.Row = 5; motion_thr_field.Layout.Column = 4;

    tcourse_btn = uibutton(step3_grid, 'push', 'Text', 'Run Time Course Extraction', ...
                           'Enable', 'off', ...
                           'BackgroundColor', [0.3 0.7 0.3], ...
                           'FontWeight', 'bold', ...
                           'ButtonPushedFcn', @(~,~) run_tcourse());
    tcourse_btn.Layout.Row = 6;
    tcourse_btn.Layout.Column = [1 4];

    tcourse_status = uilabel(step3_grid, 'Text', 'Waiting for motion correction...', ...
                             'FontAngle', 'italic');
    tcourse_status.Layout.Row = 7;
    tcourse_status.Layout.Column = [1 4];

    % Grey out parameter fields whose option is disabled
    detrend_cb.ValueChangedFcn = @(~,~) update_step3_field_state();
    expfit_cb.ValueChangedFcn = @(~,~) update_step3_field_state();
    dedup_cb.ValueChangedFcn = @(~,~) update_step3_field_state();
    motionfilt_cb.ValueChangedFcn = @(~,~) update_step3_field_state();
    update_step3_field_state();

    % --- Batch + Run All + Abort ---
    action_row = uigridlayout(left_grid, [1 3], ...
                              'ColumnWidth', {'1x', '1x', '1x'}, ...
                              'Padding', 0, 'ColumnSpacing', 5);
    action_row.Layout.Row = 5;
    uibutton(action_row, 'push', 'Text', 'Batch Mode...', ...
             'ButtonPushedFcn', @(~,~) batch_callback());
    uibutton(action_row, 'push', 'Text', 'Run All', ...
             'BackgroundColor', [0.2 0.5 0.9], ...
             'FontWeight', 'bold', 'FontColor', [1 1 1], ...
             'ButtonPushedFcn', @(~,~) run_all());
    abort_btn = uibutton(action_row, 'push', 'Text', 'ABORT BATCH', ...
             'BackgroundColor', [0.85 0.2 0.2], ...
             'FontWeight', 'bold', 'FontColor', [1 1 1], ...
             'Visible', 'off', ...
             'ButtonPushedFcn', @(~,~) abort_batch());

    % Spacer row 6 is '1x' — fills remaining space

    % Version label at bottom
    version_label = uilabel(left_grid, 'Text', 'SPIM Pipeline v1.3', 'FontAngle', 'italic', ...
            'FontColor', [0.5 0.5 0.5]);
    version_label.Layout.Row = 7;

    %%% ===============================================================
    %%% RIGHT PANEL — Preview + Output
    %%% ===============================================================
    right_panel = uipanel(main_grid, 'BorderType', 'none');
    right_panel.Layout.Column = 2;

    right_grid = uigridlayout(right_panel, [2 1], ...
                              'RowHeight', {'2x', '1x'}, ...
                              'Padding', 5, 'RowSpacing', 5);

    % Preview axes (top section — takes 2x space)
    preview_panel = uipanel(right_grid, 'Title', 'Segmentation Preview', ...
                            'FontWeight', 'bold');
    preview_panel.Layout.Row = 1;
    preview_grid = uigridlayout(preview_panel, [2 1], ...
                                'RowHeight', {'1x', 35}, ...
                                'Padding', 3, 'RowSpacing', 3);
    preview_ax = uiaxes(preview_grid, ...
                        'Units', 'normalized');
    preview_ax.Layout.Row = 1;
    preview_ax.Visible = 'off';
    title(preview_ax, 'No preview available');

    % Plane navigator (moved to right panel, below preview)
    plane_nav = uigridlayout(preview_grid, [1 4], ...
                             'ColumnWidth', {30, 60, 30, '1x'}, ...
                             'Padding', 0, 'ColumnSpacing', 3);
    plane_nav.Layout.Row = 2;
    plane_nav.Visible = 'off';
    plane_prev_btn = uibutton(plane_nav, 'push', 'Text', '<', ...
                              'ButtonPushedFcn', @(~,~) nav_plane(-1));
    plane_spinner = uispinner(plane_nav, 'Limits', [1 1], 'Value', 1, ...
                              'ValueChangedFcn', @(~,~) update_preview());
    plane_next_btn = uibutton(plane_nav, 'push', 'Text', '>', ...
                              'ButtonPushedFcn', @(~,~) nav_plane(1));
    plane_info_label = uilabel(plane_nav, 'Text', '');
    plane_info_label.Layout.Column = 4;

    % Output log (bottom section — takes 1x space)
    log_panel = uipanel(right_grid, 'Title', 'Output Log', ...
                        'FontWeight', 'bold');
    log_panel.Layout.Row = 2;
    log_grid = uigridlayout(log_panel, [1 1], ...
                            'Padding', 3, 'RowSpacing', 0);
    log_area = uitextarea(log_grid, 'Editable', 'off', ...
                          'Placeholder', 'Pipeline output will appear here...');

    %%% ---------------------------------------------------------------
    %%% State
    %%% ---------------------------------------------------------------
    state = struct();
    state.data_dir = '';
    state.cell_info = [];
    state.cell_color = [];
    state.stack_dims = [];
    state.current_plane = 1;
    state.seg_done = false;
    state.motion_done = false;
    state.seg_threshold = [];
    state.is_single_plane = false;

    %%% ---------------------------------------------------------------
    %%% Callbacks
    %%% ---------------------------------------------------------------
    function log_msg(msg)
        current = log_area.Value;
        if isempty(current) || (length(current) == 1 && isempty(current{1}))
            log_area.Value = {msg};
        else
            log_area.Value = [current; {msg}];
        end
        scroll(log_area, 'bottom');
        drawnow;
    end

    function browse_callback()
        d = uigetdir('', 'Select registered data directory');
        if d == 0, return; end
        state.data_dir = d;
        dir_field.Value = d;
        log_msg(sprintf('Data directory: %s', d));

        % Auto-detect parameters
        try
            det = util.auto_params.detect_all(d);
            log_msg(sprintf('Detected: %.2f Hz, %dx%dx%d, %d frames', ...
                    det.frame_rate, det.stack_height, det.stack_width, ...
                    det.n_zplanes, det.n_total_frames));

            % Data mode: single-plane vs volumetric
            state.is_single_plane = det.is_single_plane;
            if det.is_single_plane
                log_msg('Data mode: single-plane — Z motion and duplicate removal not applicable');
                dedup_cb.Enable = 'off';
                dedup_cb.Value = false;
                dedup_cb.Tooltip = 'Not applicable for single-plane data (only one z-plane)';
            else
                log_msg(sprintf('Data mode: volumetric (%d planes)', det.n_zplanes));
                dedup_cb.Enable = 'on';
                dedup_cb.Tooltip = ['Remove double-counted cells on adjacent z-planes by ' ...
                                    'correlation (threshold in "Corr thr")'];
            end
            update_step3_field_state();

            % Set threshold default and suggestion
            ave_file = fullfile(d, 'ave.tif');
            if exist(ave_file, 'file')
                info = imfinfo(ave_file);
                sample = imread(ave_file, 1);
                suggestion = prctile(double(sample(:)), 85);
                thresh_slider.Value = 120;
                thresh_field.Value = 120;
                log_msg(sprintf('Threshold: default=120, 85th-percentile suggestion=%d', round(suggestion)));

                % Show histogram popup after data load
                h = figure('Name', 'Intensity Histogram', 'NumberTitle', 'off', ...
                           'Position', [200 200 500 400]);
                histogram(double(sample(:)), 200);
                title('Pixel intensity distribution (first z-plane)');
                xlabel('Intensity'); ylabel('Count');
                hold on;
                xline(120, 'r--', 'LineWidth', 2, 'Label', 'Default threshold');
                xline(round(suggestion), 'g--', 'LineWidth', 2, 'Label', '85th percentile');
                hold off;
            end
        catch ME
            log_msg(sprintf('ERROR detecting params: %s', ME.message));
        end

        % Reset state
        state.seg_done = false;
        state.motion_done = false;
        motion_btn.Enable = 'off';
        tcourse_btn.Enable = 'off';
        motion_status.Text = 'Waiting for segmentation...';
        tcourse_status.Text = 'Waiting for drift motion check...';
        preview_ax.Visible = 'off';
        plane_nav.Visible = 'off';
        cell_count_label.Text = 'No segmentation yet';

        % Check for existing segmentation output
        cell_info_file = fullfile(d, 'cell_info.mat');
        if exist(cell_info_file, 'file')
            log_msg('Found existing cell_info.mat — enabling downstream steps');
            try
                loaded = load(cell_info_file);
                if ~isfield(loaded, 'cell_info') || isempty(loaded.cell_info)
                    log_msg('  cell_info.mat is empty or corrupt — skipping');
                else
                    state.cell_info = loaded.cell_info;
                    state.seg_done = true;
                    n_cells = length(state.cell_info);

                    % Load or infer threshold
                    if isfield(loaded, 'seg_params') && ...
                       isfield(loaded.seg_params, 'br_threshold')
                        state.seg_threshold = loaded.seg_params.br_threshold;
                        log_msg(sprintf('Loaded %d cells (threshold=%d)', ...
                                n_cells, state.seg_threshold));
                    else
                        % Try to infer from cellmask filename
                        inferred = infer_threshold_from_cellmasks(d);
                        if ~isnan(inferred)
                            state.seg_threshold = inferred;
                            % Save it back so we don't have to infer again
                            seg_params = struct('br_threshold', inferred, ...
                                'cont_threshold', 5, 'cell_radius', 5);
                            save(cell_info_file, 'cell_info', 'seg_params', '-append');
                            log_msg(sprintf('Loaded %d cells (threshold=%d, inferred from cellmask)', ...
                                    n_cells, inferred));
                        else
                            % Cannot infer — ask user about cleanup
                            log_msg(sprintf('Loaded %d cells but threshold is unknown', n_cells));
                            log_msg('  Cannot determine which cellmask matches — asking user...');
                            cleanup_orphan_cellmasks(d, cell_info_file);
                            state.seg_threshold = [];
                            % Re-check: maybe files were deleted, maybe threshold saved
                            if exist(cell_info_file, 'file')
                                reloaded = load(cell_info_file);
                                if isfield(reloaded, 'seg_params') && ...
                                   isfield(reloaded.seg_params, 'br_threshold')
                                    state.seg_threshold = reloaded.seg_params.br_threshold;
                                end
                            end
                        end
                    end

                    cell_count_label.Text = sprintf('%d cells found (loaded)', n_cells);

                    % Enable Step 2
                    motion_btn.Enable = 'on';
                    motion_status.Text = 'Ready to run';

                    % Load cell mask matching the threshold for preview
                    if ~isempty(state.seg_threshold)
                        cmask_pattern = sprintf('cellmask_%d_*_*.tif', state.seg_threshold);
                        cmask_files = dir(fullfile(d, cmask_pattern));
                        if isempty(cmask_files)
                            % Fall back to old naming: cellmask_<threshold>.tif
                            old_pattern = sprintf('cellmask_%d.tif', state.seg_threshold);
                            cmask_files = dir(fullfile(d, old_pattern));
                        end
                    else
                        cmask_files = dir(fullfile(d, 'cellmask_*.tif'));
                    end
                    if ~isempty(cmask_files)
                        cmask_path = fullfile(d, cmask_files(1).name);
                        cmask_info = imfinfo(cmask_path);
                        state.stack_dims = [cmask_info(1).Height, cmask_info(1).Width, length(cmask_info)];
                        state.current_plane = 1;
                        plane_spinner.Limits = [1 length(cmask_info)];
                        plane_spinner.Value = 1;
                        set_plane_nav_visible(length(cmask_info));
                        update_preview();
                        log_msg(sprintf('Loaded cell mask preview: %s (%d z-planes)', ...
                                cmask_files(1).name, length(cmask_info)));
                    else
                        log_msg('  No cellmask file found for preview');
                    end

                    % Check if Step 3 can be enabled now
                    check_tcourse_ready();
                end
            catch ME
                log_msg(sprintf('Warning: could not load cell_info.mat — %s', ME.message));
            end
        end

        % Check for existing motion correction results
        motion_file = fullfile(d, 'motion_param.mat');
        if exist(motion_file, 'file')
            log_msg('Found existing motion_param.mat — drift motion check already done');
            state.motion_done = true;
            motion_status.Text = 'Complete (loaded)';
            % Re-evaluate step 3 readiness
            if state.seg_done
                check_tcourse_ready();
            end
        end
    end

    function run_segmentation()
        if isempty(state.data_dir)
            uialert(fig, 'Please select a data directory first.', 'No Data');
            return;
        end
        % Reset downstream stages when re-running segmentation
        motion_btn.Enable = 'off';
        tcourse_btn.Enable = 'off';
        motion_status.Text = 'Waiting for segmentation...';
        tcourse_status.Text = 'Waiting for drift motion check...';
        state.motion_done = false;

        seg_btn.Enable = 'off';
        seg_btn.Text = 'Running...';
        log_msg('--- Starting cell segmentation ---');
        drawnow;

        try
            thresh = round(thresh_slider.Value);
            log_msg(sprintf('Brightness threshold: %d', thresh));

            cell_info = pipeline.recog_wholefish(state.data_dir, thresh, false);
            state.cell_info = cell_info;
            state.seg_done = true;
            state.seg_threshold = thresh;

            % Load cell mask for preview
            cmask_files = dir(fullfile(state.data_dir, ...
                               sprintf('cellmask_%d_*_*.tif', thresh)));
            if ~isempty(cmask_files)
                cmask_path = fullfile(state.data_dir, cmask_files(1).name);
                cmask_info = imfinfo(cmask_path);
                state.stack_dims = [cmask_info(1).Height, cmask_info(1).Width, length(cmask_info)];
                state.current_plane = 1;
                plane_spinner.Limits = [1 length(cmask_info)];
                plane_spinner.Value = 1;
                set_plane_nav_visible(length(cmask_info));
                update_preview();
            end

            n_cells = length(cell_info);
            log_msg(sprintf('Segmentation complete: %d cells found', n_cells));
            log_msg('--- Cell segmentation done ---');
            cell_count_label.Text = sprintf('%d cells found', n_cells);

            % Enable Step 2
            motion_btn.Enable = 'on';
            motion_status.Text = 'Ready to run';

            % Check if Step 3 can be enabled now (e.g. motion filtering disabled)
            check_tcourse_ready();

        catch ME
            log_msg(sprintf('ERROR: %s', ME.message));
            log_msg(getReport(ME, 'extended', 'hyperlinks', 'off'));
        end
        seg_btn.Enable = 'on';
        seg_btn.Text = 'Run Segmentation';
    end

    function update_preview()
        if isempty(state.data_dir) || isempty(state.stack_dims), return; end
        z = round(plane_spinner.Value);
        % Find cellmask matching current threshold (if known)
        if ~isempty(state.seg_threshold)
            cmask_files = dir(fullfile(state.data_dir, ...
                sprintf('cellmask_%d_*_*.tif', state.seg_threshold)));
            if isempty(cmask_files)
                cmask_files = dir(fullfile(state.data_dir, ...
                    sprintf('cellmask_%d.tif', state.seg_threshold)));
            end
        end
        if isempty(state.seg_threshold) || isempty(cmask_files)
            cmask_files = dir(fullfile(state.data_dir, 'cellmask_*.tif'));
        end
        if isempty(cmask_files), return; end
        cmask_path = fullfile(state.data_dir, cmask_files(1).name);
        img = imread(cmask_path, z);
        img = imcomplement(img);  % invert: bright background, dark cells
        imshow(img, 'Parent', preview_ax, 'Border', 'tight');
        preview_ax.Visible = 'on';
        axis(preview_ax, 'tight');
        preview_ax.XTick = [];
        preview_ax.YTick = [];
        preview_ax.Box = 'off';
        title(preview_ax, sprintf('Cell mask — Plane %d/%d', z, state.stack_dims(3)));

        % Count cells on this plane
        if ~isempty(state.cell_info)
            n_on_plane = sum([state.cell_info.slice] == z);
            plane_info_label.Text = sprintf('Plane %d: %d cells', z, n_on_plane);
        end
    end

    function nav_plane(delta)
        new_val = round(plane_spinner.Value) + delta;
        new_val = max(plane_spinner.Limits(1), min(plane_spinner.Limits(2), new_val));
        plane_spinner.Value = new_val;
        update_preview();
    end

    function set_plane_nav_visible(n_planes)
        % Hide the plane navigator for single-plane data — nothing to navigate
        if n_planes > 1
            plane_nav.Visible = 'on';
        else
            plane_nav.Visible = 'off';
        end
    end

    function check_tcourse_ready()
        % Enable Step 3 if: segmentation is done AND
        % (motion is done OR motion-based filtering is disabled)
        if ~state.seg_done
            return;
        end
        if state.motion_done
            tcourse_btn.Enable = 'on';
            tcourse_status.Text = 'Ready to run';
        elseif ~motionfilt_cb.Value
            tcourse_btn.Enable = 'on';
            tcourse_status.Text = 'Ready to run (motion filtering disabled)';
        else
            tcourse_btn.Enable = 'off';
            tcourse_status.Text = 'Waiting for drift motion check...';
        end
    end

    function run_motion()
        if ~state.seg_done
            uialert(fig, 'Run cell segmentation first.', 'Order Error');
            return;
        end
        motion_btn.Enable = 'off';
        motion_btn.Text = 'Running...';
        motion_status.Text = 'Processing...';
        log_msg('--- Starting drift motion check ---');
        drawnow;

        try
            motion_params = struct();
            if gpu_check.Value
                motion_params.use_gpu = true;
                pipeline.check_motion_gpu(state.data_dir, motion_params);
            else
                pipeline.check_motion(state.data_dir, motion_params);
            end
            state.motion_done = true;
            log_msg('--- Drift motion check done ---');
            motion_status.Text = 'Complete';

            % Enable Step 3 (if conditions allow)
            check_tcourse_ready();

        catch ME
            log_msg(sprintf('ERROR: %s', ME.message));
            log_msg(getReport(ME, 'extended', 'hyperlinks', 'off'));
            motion_status.Text = 'Failed — see log';
        end
        motion_btn.Enable = 'on';
        motion_btn.Text = 'Run Drift Motion Check';
    end

    function update_step3_field_state()
        % Enable/disable Step 3 parameter fields to match their checkboxes
        detrend_state = 'off'; if detrend_cb.Value, detrend_state = 'on'; end
        detrend_window_field.Enable = detrend_state;
        detrend_pct_field.Enable = detrend_state;
        detrend_offset_field.Enable = detrend_state;
        expfit_state = 'off'; if expfit_cb.Value, expfit_state = 'on'; end
        expfit_window_field.Enable = expfit_state;
        dedup_state = 'off'; if dedup_cb.Value, dedup_state = 'on'; end
        dedup_corr_field.Enable = dedup_state;
        motion_state = 'off'; if motionfilt_cb.Value, motion_state = 'on'; end
        motion_thr_field.Enable = motion_state;
    end

    function run_tcourse()
        if ~state.seg_done
            uialert(fig, 'Run cell segmentation first.', 'Order Error');
            return;
        end
        if motionfilt_cb.Value && ~state.motion_done
            uialert(fig, 'Motion-based filtering is enabled but motion correction has not been run.\nEither run Step 2 first, or disable motion-based filtering.', 'Order Error');
            return;
        end
        tcourse_btn.Enable = 'off';
        tcourse_btn.Text = 'Running...';
        tcourse_status.Text = 'Processing...';
        log_msg('--- Starting time course extraction ---');
        drawnow;

        try
            tc_params = struct();
            tc_params.enable_detrending = detrend_cb.Value;
            tc_params.detrend_window_frames = round(detrend_window_field.Value);
            tc_params.detrend_percentile = detrend_pct_field.Value;
            tc_params.detrend_offset = detrend_offset_field.Value;
            tc_params.enable_photobleach_fit = expfit_cb.Value;
            tc_params.baseline_window_seconds = round(expfit_window_field.Value);
            tc_params.enable_remove_duplicates = dedup_cb.Value;
            tc_params.dedup_corr_threshold = dedup_corr_field.Value;
            tc_params.enable_motion_filter = motionfilt_cb.Value;
            tc_params.motion_threshold_pixels = motion_thr_field.Value;
            log_msg(sprintf(['Options: detrend=%d (win=%d, pct=%g, offset=%g), ' ...
                    'expfit=%d (win=%ds), dedup=%d (corr=%g), motionfilt=%d (thr=%gpx)'], ...
                    tc_params.enable_detrending, tc_params.detrend_window_frames, ...
                    tc_params.detrend_percentile, tc_params.detrend_offset, ...
                    tc_params.enable_photobleach_fit, tc_params.baseline_window_seconds, ...
                    tc_params.enable_remove_duplicates, tc_params.dedup_corr_threshold, ...
                    tc_params.enable_motion_filter, tc_params.motion_threshold_pixels));

            [~, ~] = pipeline.get_cell_tcourse(state.data_dir, tc_params);
            log_msg('--- Time course extraction done ---');
            tcourse_status.Text = 'Complete';

        catch ME
            log_msg(sprintf('ERROR: %s', ME.message));
            log_msg(getReport(ME, 'extended', 'hyperlinks', 'off'));
            tcourse_status.Text = 'Failed — see log';
        end
        tcourse_btn.Enable = 'on';
        tcourse_btn.Text = 'Run Time Course Extraction';
    end

    function abort_batch()
        fig.UserData.batch_abort = true;
        abort_btn.Visible = 'off';
        abort_btn.Enable = 'off';
        log_msg('*** ABORT requested — finishing current step then stopping ***');
    end

    function run_all()
        if isempty(state.data_dir)
            uialert(fig, 'Please select a data directory first.', 'No Data');
            return;
        end
        % Run segmentation
        run_segmentation();
        if ~state.seg_done, return; end
        % Auto-run motion
        run_motion();
        if ~state.motion_done, return; end
        % Auto-run time course
        run_tcourse();
        log_msg('========== Pipeline complete ==========');
    end

    function batch_callback()
        [file, path] = uigetfile('*.txt', 'Select batch list file');
        if file == 0, return; end
        batch_file = fullfile(path, file);
        log_msg(sprintf('Batch mode: %s', batch_file));

        try
            % Initialize abort flag and show abort button
            fig.UserData.batch_abort = false;
            abort_btn.Visible = 'on';
            abort_btn.Enable = 'on';
            cleanup_abort = onCleanup(@() hide_abort());  % hide on any exit

            % --- Parse batch file ---
            fid = fopen(batch_file, 'r');
            raw = textscan(fid, '%s', 'Delimiter', '\n', 'CommentStyle', '#');
            fclose(fid);
            raw = raw{1};
            dirs = {};
            for i = 1:length(raw)
                trimmed = strtrim(raw{i});
                if ~isempty(trimmed) && ~startsWith(trimmed, '#')
                    dirs{end+1} = trimmed;
                end
            end
            n_dirs = length(dirs);
            log_msg(sprintf('Found %d directories in batch list', n_dirs));

            % Track segmentation results
            seg_ok = false(1, n_dirs);
            seg_thresholds = zeros(1, n_dirs);

            %%% =========================================================
            %%% PHASE 1: Interactive per-folder segmentation
            %%% =========================================================
            log_msg('===== Phase 1: Interactive Segmentation (per folder) =====');

            for i = 1:n_dirs
                % Check abort flag
                if fig.UserData.batch_abort
                    log_msg(sprintf('Abort — skipping remaining %d folders', n_dirs - i + 1));
                    break;
                end
                d = dirs{i};
                log_msg(sprintf('--- Folder %d/%d: %s ---', i, n_dirs, d));

                if ~exist(d, 'dir')
                    log_msg(sprintf('  SKIP: directory not found'));
                    continue;
                end

                % Check for existing segmentation
                cell_info_file = fullfile(d, 'cell_info.mat');
                if exist(cell_info_file, 'file')
                    loaded = load(cell_info_file);
                    n_existing = length(loaded.cell_info);

                    % Determine threshold for display and state
                    thresh_str = 'unknown';
                    if isfield(loaded, 'seg_params') && ...
                       isfield(loaded.seg_params, 'br_threshold')
                        state.seg_threshold = loaded.seg_params.br_threshold;
                        thresh_str = num2str(state.seg_threshold);
                    else
                        state.seg_threshold = infer_threshold_from_cellmasks(d);
                        if ~isnan(state.seg_threshold)
                            thresh_str = sprintf('%d (inferred)', state.seg_threshold);
                        end
                    end

                    % Load preview so user can inspect before deciding
                    state.data_dir = d;
                    state.cell_info = loaded.cell_info;
                    state.seg_done = true;
                    load_preview_for_dir(d);

                    % Non-blocking dialog — user can navigate preview
                    choice = batch_confirm_dialog( ...
                        sprintf('Existing — Folder %d/%d', i, n_dirs), ...
                        sprintf(['Found existing segmentation:\n', ...
                                 '  %d cells\n', ...
                                 '  Threshold: %s\n\n', ...
                                 'Use the plane navigator (< >) to inspect.\n', ...
                                 'Choose:'], n_existing, thresh_str), ...
                        {'Use Existing', 'Re-segment', 'Skip'});
                    switch choice
                        case 'Use Existing'
                            seg_ok(i) = true;
                            seg_thresholds(i) = NaN;
                            log_msg(sprintf('  Using existing segmentation (%d cells, threshold=%s)', ...
                                    n_existing, thresh_str));
                            continue;
                        case 'Skip'
                            log_msg('  Skipped');
                            continue;
                        case 'Re-segment'
                            log_msg('  Re-segmenting...');
                    end
                end

                % Auto-detect parameters and show histogram
                thresh_val = 120;
                try
                    det = util.auto_params.detect_all(d);
                    log_msg(sprintf('  Detected: %.2f Hz, %dx%dx%d', ...
                            det.frame_rate, det.stack_height, det.stack_width, det.n_zplanes));

                    ave_file = fullfile(d, 'ave.tif');
                    if exist(ave_file, 'file')
                        sample = imread(ave_file, 1);
                        suggestion = round(prctile(double(sample(:)), 85));
                        log_msg(sprintf('  Threshold suggestion (85th percentile): %d', suggestion));

                        % Show histogram
                        hfig = figure('Name', sprintf('Histogram — Folder %d/%d', i, n_dirs), ...
                                      'NumberTitle', 'off', 'Position', [200 200 500 400]);
                        histogram(double(sample(:)), 200);
                        title(sprintf('Pixel intensity distribution\\n%s', d), 'Interpreter', 'none');
                        xlabel('Intensity'); ylabel('Count');
                        hold on;
                        xline(120, 'r--', 'LineWidth', 2, 'Label', 'Default=120');
                        xline(suggestion, 'g--', 'LineWidth', 2, 'Label', sprintf('85%%=%d', suggestion));
                        hold off;
                    end
                catch ME
                    log_msg(sprintf('  WARNING: auto-detect failed: %s', ME.message));
                end

                % Interactive threshold → segment → confirm loop
                while true
                    answer = inputdlg( ...
                        {sprintf('Brightness threshold for folder %d/%d:', i, n_dirs), ...
                         'Folder:'}, ...
                        'Cell Segmentation Threshold', 1, ...
                        {num2str(thresh_val), d});
                    if isempty(answer)
                        log_msg('  User cancelled — skipping folder');
                        break;
                    end
                    thresh_val = round(str2double(answer{1}));
                    if isnan(thresh_val) || thresh_val < 1
                        log_msg('  Invalid threshold, please enter a number');
                        continue;
                    end

                    log_msg(sprintf('  Running segmentation with threshold=%d...', thresh_val));
                    drawnow;

                    try
                        cell_info = pipeline.recog_wholefish(d, thresh_val, false);
                        n_cells = length(cell_info);
                        log_msg(sprintf('  Found %d cells', n_cells));

                        % Show preview in main panel
                        state.data_dir = d;
                        state.cell_info = cell_info;
                        state.seg_done = true;
                        state.seg_threshold = thresh_val;
                        load_preview_for_dir(d);

                        % Ask user to confirm (non-blocking so they can navigate preview)
                        choice = batch_confirm_dialog( ...
                            sprintf('Confirm — Folder %d/%d', i, n_dirs), ...
                            sprintf(['Threshold: %d\nCells found: %d\n\n', ...
                                     'Use the plane navigator (< >) to inspect the result.\n', ...
                                     'Then choose:'], thresh_val, n_cells), ...
                            {'Accept', 'Re-run with new threshold', 'Skip'});
                        switch choice
                            case 'Accept'
                                seg_ok(i) = true;
                                seg_thresholds(i) = thresh_val;
                                break;
                            case 'Re-run with new threshold'
                                % Loop continues with current thresh_val as default
                            case 'Skip'
                                seg_ok(i) = false;
                                break;
                        end
                    catch ME
                        log_msg(sprintf('  ERROR: %s', ME.message));
                        choice = batch_confirm_dialog( ...
                            'Error', ...
                            sprintf('Segmentation failed:\n%s\n\nTry again with different threshold?', ...
                                    ME.message), ...
                            {'Try Again', 'Skip'});
                        if strcmp(choice, 'Skip')
                            break;
                        end
                    end
                end

                % Close histogram if still open
                close(findobj('Type', 'figure', 'Name', sprintf('Histogram — Folder %d/%d', i, n_dirs)));
            end

            % Summary of segmentation phase
            n_ok = sum(seg_ok);
            log_msg(sprintf('===== Segmentation phase complete: %d/%d OK =====', n_ok, n_dirs));
            if n_ok == 0
                log_msg('No folders successfully segmented — stopping batch');
                return;
            end

            %%% =========================================================
            %%% OPTIONS: Ask about steps 2 & 3 before auto-running
            %%% =========================================================
            batch_opts = batch_options_dialog();
            if isempty(batch_opts)
                log_msg('Batch cancelled by user');
                return;
            end

            log_msg(sprintf(['Batch options: run_motion=%d, use_gpu=%d, ' ...
                    'detrend=%d (win=%d, pct=%g, offset=%g), expfit=%d (win=%ds), ' ...
                    'dedup=%d (corr=%g), motionfilt=%d (thr=%gpx)'], ...
                    batch_opts.run_motion, batch_opts.use_gpu, ...
                    batch_opts.detrending, batch_opts.detrend_window, ...
                    batch_opts.detrend_percentile, batch_opts.detrend_offset, ...
                    batch_opts.expfit, batch_opts.expfit_window, ...
                    batch_opts.dedup, batch_opts.dedup_corr, ...
                    batch_opts.motionfilt, batch_opts.motion_thr));

            % Build params for remaining phases
            batch_params = struct();
            batch_params.skip_segmentation = true;   % already done above
            batch_params.enable_detrending = batch_opts.detrending;
            batch_params.detrend_window_frames = batch_opts.detrend_window;
            batch_params.detrend_percentile = batch_opts.detrend_percentile;
            batch_params.detrend_offset = batch_opts.detrend_offset;
            batch_params.enable_photobleach_fit = batch_opts.expfit;
            batch_params.baseline_window_seconds = batch_opts.expfit_window;
            batch_params.enable_remove_duplicates = batch_opts.dedup;
            batch_params.dedup_corr_threshold = batch_opts.dedup_corr;
            batch_params.enable_motion_filter = batch_opts.motionfilt;
            batch_params.motion_threshold_pixels = batch_opts.motion_thr;
            if batch_opts.use_gpu
                batch_params.use_gpu = true;
            end
            if ~batch_opts.run_motion
                batch_params.skip_motion = true;
            end

            %%% =========================================================
            %%% PHASES 2 & 3: Auto-run motion + time course
            %%% =========================================================
            if ~fig.UserData.batch_abort
                batch_params.abort_fig = fig;   % pass figure for abort checking
                pipeline.batch_process(batch_file, 0, batch_params);
            end
            log_msg('===== Batch processing complete =====');

        catch ME
            log_msg(sprintf('ERROR in batch: %s', ME.message));
            log_msg(getReport(ME, 'extended', 'hyperlinks', 'off'));
        end
    end

    function hide_abort()
        abort_btn.Visible = 'off';
    end

    function load_preview_for_dir(d)
        % Load cell mask preview for a directory (used during batch mode)
        % Find cellmask matching current threshold (if known)
        if ~isempty(state.seg_threshold)
            cmask_files = dir(fullfile(d, ...
                sprintf('cellmask_%d_*_*.tif', state.seg_threshold)));
            if isempty(cmask_files)
                cmask_files = dir(fullfile(d, ...
                    sprintf('cellmask_%d.tif', state.seg_threshold)));
            end
        end
        if isempty(state.seg_threshold) || isempty(cmask_files)
            cmask_files = dir(fullfile(d, 'cellmask_*.tif'));
        end
        if ~isempty(cmask_files)
            cmask_path = fullfile(d, cmask_files(1).name);
            cmask_info = imfinfo(cmask_path);
            state.stack_dims = [cmask_info(1).Height, cmask_info(1).Width, length(cmask_info)];
            state.current_plane = 1;
            plane_spinner.Limits = [1 length(cmask_info)];
            plane_spinner.Value = 1;
            set_plane_nav_visible(length(cmask_info));
            update_preview();
            n_cells = length(state.cell_info);
            cell_count_label.Text = sprintf('%d cells found (batch)', n_cells);
            log_msg(sprintf('  Preview loaded: %d z-planes', length(cmask_info)));
        end
    end

    function choice = batch_confirm_dialog(title_str, message, options)
        % Non-blocking confirm dialog — pauses batch loop but leaves main
        % GUI interactive so the user can navigate the preview.
        dlg_w = 400;
        dlg_h = 140;
        dlg = figure('Name', title_str, ...
                     'Position', [400 400 dlg_w dlg_h], ...
                     'MenuBar', 'none', 'ToolBar', 'none', ...
                     'NumberTitle', 'off', ...
                     'Resize', 'off');   % no WindowStyle='modal' — keep GUI interactive

        uilabel(dlg, 'Text', message, ...
                'Position', [15 dlg_h-80 dlg_w-30 70], ...
                'VerticalAlignment', 'top');

        n_opts = length(options);
        btn_w = min(120, (dlg_w - 20) / n_opts - 10);
        total_btn_w = n_opts * btn_w + (n_opts - 1) * 8;
        x_start = (dlg_w - total_btn_w) / 2;

        result = struct('value', '');
        for j = 1:n_opts
            x_pos = x_start + (j-1) * (btn_w + 8);
            opt = options{j};
            uibutton(dlg, 'push', 'Text', opt, ...
                     'Position', [x_pos 15 btn_w 30], ...
                     'ButtonPushedFcn', @(~,~) set_result(opt));
        end

        function set_result(val)
            result.value = val;
            uiresume(dlg);
        end

        uiwait(dlg);

        if isvalid(dlg)
            choice = result.value;
            close(dlg);
        else
            choice = '';  % figure was closed via X button
        end
    end

    function thresh = infer_threshold_from_cellmasks(d)
        % Try to infer the segmentation threshold from cellmask filenames.
        % Returns NaN if ambiguous (0, >1 unique threshold, or no cellmasks).
        cmask_files = dir(fullfile(d, 'cellmask_*.tif'));
        if isempty(cmask_files)
            thresh = NaN;
            return;
        end
        thresholds = [];
        for f = 1:length(cmask_files)
            name = cmask_files(f).name;
            % New format: cellmask_<br>_<cont>_<rad>.tif
            tokens = regexp(name, '^cellmask_(\d+)_\d+_\d+\.tif$', 'tokens');
            if ~isempty(tokens)
                thresholds(end+1) = str2double(tokens{1}{1});
            else
                % Old format: cellmask_<br>.tif
                tokens = regexp(name, '^cellmask_(\d+)\.tif$', 'tokens');
                if ~isempty(tokens)
                    thresholds(end+1) = str2double(tokens{1}{1});
                end
            end
        end
        unique_thresh = unique(thresholds);
        if length(unique_thresh) == 1
            thresh = unique_thresh;
            log_msg(sprintf('  Inferred threshold=%d from cellmask filenames', thresh));
        else
            thresh = NaN;
            log_msg(sprintf('  Cannot infer threshold: %d unique values in %d cellmask files', ...
                    length(unique_thresh), length(cmask_files)));
        end
    end

    function cleanup_orphan_cellmasks(d, cell_info_file)
        % Cell info has no threshold and we cannot infer it from filenames.
        % Ask user whether to delete the orphan files.
        cmask_files = dir(fullfile(d, 'cellmask_*.tif'));
        file_list = {cmask_files.name};
        if isempty(file_list)
            log_msg('  No cellmask files to clean up');
            return;
        end

        % Build message listing files
        msg_lines = {'Cannot determine which threshold produced these files:', ''};
        msg_lines{end+1} = sprintf('  Directory: %s', d);
        msg_lines{end+1} = '';
        msg_lines{end+1} = 'Files that would be deleted:';
        msg_lines{end+1} = '  cell_info.mat';
        for k = 1:min(length(file_list), 10)
            msg_lines{end+1} = sprintf('  %s', file_list{k});
        end
        if length(file_list) > 10
            msg_lines{end+1} = sprintf('  ... and %d more cellmask files', ...
                                       length(file_list) - 10);
        end
        msg_lines{end+1} = '';
        msg_lines{end+1} = 'Delete these files? (This cannot be undone)';

        choice = uiconfirm(fig, strjoin(msg_lines, '\n'), ...
            'Orphan Cell Masks Detected', ...
            'Options', {'Delete All', 'Keep All'}, ...
            'DefaultOption', 2, 'CancelOption', 2);

        if strcmp(choice, 'Delete All')
            log_msg('  Deleting orphan segmentation files...');
            % Delete cellmasks
            for k = 1:length(cmask_files)
                fpath = fullfile(d, cmask_files(k).name);
                delete(fpath);
                log_msg(sprintf('  Deleted: %s', cmask_files(k).name));
            end
            % Delete cell_info.mat
            delete(cell_info_file);
            log_msg('  Deleted: cell_info.mat');
            % Reset state
            state.seg_done = false;
            state.seg_threshold = [];
            state.cell_info = [];
            motion_btn.Enable = 'off';
            motion_status.Text = 'Waiting for segmentation...';
            tcourse_btn.Enable = 'off';
            tcourse_status.Text = 'Waiting for drift motion check...';
            cell_count_label.Text = 'No segmentation yet';
            preview_ax.Visible = 'off';
            plane_nav.Visible = 'off';
        else
            log_msg('  Keeping all files (threshold will remain unknown)');
        end
    end

    function opts = batch_options_dialog()
        % Modal dialog for batch phases 2 & 3 options
        dlg_w = 400;
        dlg_h = 440;
        dlg = figure('Name', 'Batch — Steps 2 & 3 Options', ...
                     'Position', [300 300 dlg_w dlg_h], ...
                     'MenuBar', 'none', 'ToolBar', 'none', ...
                     'NumberTitle', 'off', 'WindowStyle', 'modal', ...
                     'Resize', 'off');

        y0 = dlg_h - 35;
        row_h = 32;

        uilabel(dlg, 'Text', 'Configure auto-run steps for all folders:', ...
                'FontWeight', 'bold', ...
                'Position', [15 y0 dlg_w-30 20]);
        y0 = y0 - row_h;

        % Step 2: Check Drift Motion
        run_motion_cb = uicheckbox(dlg, 'Text', 'Run Step 2: Check Drift Motion', ...
                                   'Value', true, ...
                                   'Position', [20 y0 dlg_w-40 22]);
        y0 = y0 - row_h;

        % GPU
        gpu_cb = uicheckbox(dlg, 'Text', 'Use GPU (if available)', ...
                            'Value', false, ...
                            'Position', [40 y0 dlg_w-60 22]);
        y0 = y0 - row_h + 5;

        % Separator
        uilabel(dlg, 'Text', 'Step 3: Time Course Extraction options:', ...
                'FontWeight', 'bold', ...
                'Position', [15 y0 dlg_w-30 20]);
        y0 = y0 - row_h;

        % NOTE: dialog-local controls use dlg_ prefix so they do not
        % clobber the main window's checkbox handles (nested functions
        % share the workspace)
        dlg_detrend_cb = uicheckbox(dlg, 'Text', 'Detrending (rolling-percentile dF/F)', ...
                                    'Value', true, ...
                                    'Position', [20 y0 dlg_w-40 22]);
        y0 = y0 - row_h;

        % Detrending parameters (label / field / label / field in one row)
        uilabel(dlg, 'Text', 'Window (frames):', ...
                'Position', [40 y0 120 20]);
        dlg_detrend_window_field = uieditfield(dlg, 'numeric', ...
            'Limits', [1 1e6], 'Value', 600, ...
            'Position', [165 y0-2 55 24]);
        uilabel(dlg, 'Text', 'Percentile:', ...
                'Position', [230 y0 80 20]);
        dlg_detrend_pct_field = uieditfield(dlg, 'numeric', ...
            'Limits', [0 100], 'Value', 15, ...
            'Position', [315 y0-2 50 24]);
        y0 = y0 - row_h;

        uilabel(dlg, 'Text', 'F0 offset:', ...
                'Position', [40 y0 120 20]);
        dlg_detrend_offset_field = uieditfield(dlg, 'numeric', ...
            'Limits', [0 1e6], 'Value', 10, ...
            'Position', [165 y0-2 55 24]);
        uilabel(dlg, 'Text', 'Exp window (s):', ...
                'Position', [230 y0 80 20]);
        dlg_expfit_window_field = uieditfield(dlg, 'numeric', ...
            'Limits', [10 1e6], 'Value', 180, ...
            'Position', [315 y0-2 50 24]);
        y0 = y0 - row_h;

        dlg_expfit_cb = uicheckbox(dlg, 'Text', 'Exponential photobleaching fit (legacy)', ...
                                   'Value', false, ...
                                   'Position', [20 y0 dlg_w-40 22]);
        y0 = y0 - row_h;

        dlg_dedup_cb = uicheckbox(dlg, 'Text', 'Remove double-counted cells', ...
                                  'Value', false, ...
                                  'Position', [20 y0 dlg_w-40 22]);
        y0 = y0 - row_h;

        dlg_motionfilt_cb = uicheckbox(dlg, 'Text', 'Motion-based filtering', ...
                                       'Value', false, ...
                                       'Position', [20 y0 dlg_w-40 22]);
        y0 = y0 - row_h;

        % Dedup / motion filtering thresholds
        uilabel(dlg, 'Text', 'Dedup corr thr:', ...
                'Position', [40 y0 120 20]);
        dlg_dedup_corr_field = uieditfield(dlg, 'numeric', ...
            'Limits', [0 1], 'Value', 0.7, ...
            'Position', [165 y0-2 55 24]);
        uilabel(dlg, 'Text', 'Motion thr (px):', ...
                'Position', [230 y0 80 20]);
        dlg_motion_thr_field = uieditfield(dlg, 'numeric', ...
            'Limits', [0 1e6], 'Value', 1, ...
            'Position', [315 y0-2 50 24]);
        y0 = y0 - row_h - 10;

        % OK / Cancel buttons
        btn_w = 80;
        uibutton(dlg, 'push', 'Text', 'Start Batch', ...
                 'BackgroundColor', [0.3 0.7 0.3], 'FontWeight', 'bold', ...
                 'Position', [dlg_w/2 - btn_w - 10 y0 btn_w 28], ...
                 'ButtonPushedFcn', @(~,~) uiresume(dlg));
        uibutton(dlg, 'push', 'Text', 'Cancel', ...
                 'Position', [dlg_w/2 + 10 y0 btn_w 28], ...
                 'ButtonPushedFcn', @(~,~) delete(dlg));

        uiwait(dlg);

        if ~isvalid(dlg)
            opts = [];
            return;
        end

        opts = struct();
        opts.run_motion = run_motion_cb.Value;
        opts.use_gpu = gpu_cb.Value;
        opts.detrending = dlg_detrend_cb.Value;
        opts.detrend_window = round(dlg_detrend_window_field.Value);
        opts.detrend_percentile = dlg_detrend_pct_field.Value;
        opts.detrend_offset = dlg_detrend_offset_field.Value;
        opts.expfit = dlg_expfit_cb.Value;
        opts.expfit_window = round(dlg_expfit_window_field.Value);
        opts.dedup = dlg_dedup_cb.Value;
        opts.dedup_corr = dlg_dedup_corr_field.Value;
        opts.motionfilt = dlg_motionfilt_cb.Value;
        opts.motion_thr = dlg_motion_thr_field.Value;

        close(dlg);
    end
end
