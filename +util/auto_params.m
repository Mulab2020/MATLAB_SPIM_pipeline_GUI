classdef auto_params
% AUTO_PARAMS  Auto-detect acquisition metadata from a data directory.
%
%   summary = util.auto_params.detect_all(data_dir)
%
% Static methods for reading SPIM acquisition metadata:
%   detect_all        - Master: returns struct with all parameters
%   detect_mode       - Detect single-plane vs volumetric data from files
%   read_frame_rate   - Parse Stack_frequency.txt
%   read_dimensions   - Parse Stack dimensions.log or ch0_cam1.xml
%   read_frame_range  - Parse minANDmax.txt

    methods (Static)

        function summary = detect_all(data_dir)
        % DETECT_ALL  Auto-detect all acquisition metadata.
        %
        %   summary = util.auto_params.detect_all(data_dir)
        %
        % Returns a struct with fields:
        %   .frame_rate, .n_total_frames, .stack_height, .stack_width,
        %   .n_zplanes, .frame_start, .frame_end, .is_single_plane
        %
        % When single-plane data is detected, .n_zplanes is forced to 1
        % regardless of what the metadata files say.
            fprintf('\n========== Auto-detecting parameters from: %s ==========\n', data_dir);

            summary = struct();

            [summary.frame_rate, summary.n_total_frames] = ...
                util.auto_params.read_frame_rate(data_dir);

            [summary.stack_height, summary.stack_width, summary.n_zplanes] = ...
                util.auto_params.read_dimensions(data_dir);

            [summary.frame_start, summary.frame_end] = ...
                util.auto_params.read_frame_range(data_dir);

            summary.is_single_plane = util.auto_params.detect_mode(data_dir);
            if summary.is_single_plane && summary.n_zplanes ~= 1
                fprintf('  [auto_params] Overriding metadata n_zplanes=%d with 1 (single-plane data)\n', ...
                        summary.n_zplanes);
                summary.n_zplanes = 1;
            end

            fprintf('\n========== Parameter summary ==========\n');
            fprintf('  Frame rate:       %.2f Hz\n', summary.frame_rate);
            fprintf('  Stack dimensions: %d x %d x %d (H x W x Z)\n', ...
                    summary.stack_height, summary.stack_width, summary.n_zplanes);
            fprintf('  Total frames:     %d (range %d-%d)\n', ...
                    summary.n_total_frames, summary.frame_start, summary.frame_end);
            if summary.is_single_plane
                fprintf('  Data mode:        single-plane\n');
            else
                fprintf('  Data mode:        volumetric\n');
            end
            fprintf('========================================\n\n');
        end


        function [frame_rate, n_total_frames] = read_frame_rate(data_dir)
        % READ_FRAME_RATE  Parse Stack_frequency.txt.
        %
        % File format (3 lines):
        %   Line 1: volume frame rate in Hz
        %   Line 2: total scan duration in seconds
        %   Line 3: total number of acquired volumes
            freq_file = fullfile(data_dir, 'Stack_frequency.txt');

            if ~exist(freq_file, 'file')
                error('auto_params:missingFile', ...
                      'Stack_frequency.txt not found in: %s', data_dir);
            end

            fid = fopen(freq_file, 'r');
            data = textscan(fid, '%f');
            fclose(fid);
            data = data{1};

            if length(data) < 3
                error('auto_params:badFormat', ...
                      'Stack_frequency.txt has %d values (expected 3)', length(data));
            end

            frame_rate = data(1);
            n_total_frames = data(3);

            fprintf('  [auto_params] Stack_frequency.txt -> frame_rate = %.2f Hz, total_frames = %d\n', ...
                    frame_rate, n_total_frames);
        end


        function [height, width, n_planes] = read_dimensions(data_dir)
        % READ_DIMENSIONS  Parse Stack dimensions.log (binary, 3 x uint32).
        %
        % Falls back to ch0_cam1.xml if .log is absent.
            dim_file = fullfile(data_dir, 'Stack dimensions.log');

            if exist(dim_file, 'file')
                fid = fopen(dim_file, 'rb');
                dims = fread(fid, 3, 'uint32=>double');
                fclose(fid);

                if length(dims) < 3
                    error('auto_params:badFormat', ...
                          'Stack dimensions.log has %d values (expected 3)', length(dims));
                end

                height = dims(1);
                width = dims(2);
                n_planes = dims(3);

                fprintf('  [auto_params] Stack dimensions.log -> %d x %d x %d (H x W x Z)\n', ...
                        height, width, n_planes);
            else
                fprintf('  [auto_params] Stack dimensions.log not found, trying ch0_cam1.xml...\n');
                [height, width, n_planes] = util.auto_params.parse_xml_dimensions(data_dir);
            end
        end


        function [frame_start, frame_end] = read_frame_range(data_dir)
        % READ_FRAME_RANGE  Parse minANDmax.txt.
        %
        % Frames are 0-indexed in the file; converted to 1-indexed on return.
        % Falls back to [1, total_frames] from Stack_frequency.txt if absent.
            range_file = fullfile(data_dir, 'minANDmax.txt');

            if exist(range_file, 'file')
                fid = fopen(range_file, 'r');
                txt = fread(fid, '*char')';
                fclose(fid);

                min_match = regexp(txt, 'minframe\s*=\s*(\d+)', 'tokens', 'once');
                max_match = regexp(txt, 'maxframe\s*=\s*(\d+)', 'tokens', 'once');

                if ~isempty(min_match) && ~isempty(max_match)
                    frame_start = str2double(min_match{1}) + 1;
                    frame_end = str2double(max_match{1}) + 1;

                    fprintf('  [auto_params] minANDmax.txt -> frames %d to %d (1-indexed)\n', ...
                            frame_start, frame_end);
                    return;
                end
            end

            % Fallback
            fprintf('  [auto_params] minANDmax.txt not found, using total_frames from frequency file...\n');
            [~, n_total_frames] = util.auto_params.read_frame_rate(data_dir);
            frame_start = 1;
            frame_end = n_total_frames;
        end


        function [is_single_plane, n_plane_files, n_ave_pages] = detect_mode(data_dir)
        % DETECT_MODE  Detect single-plane vs volumetric data from files.
        %
        %   [is_single_plane, n_plane_files, n_ave_pages] = ...
        %       util.auto_params.detect_mode(data_dir)
        %
        % Single-plane data is identified by two conditions:
        %   1. Only Plane01.stack is present (no Plane02.stack, Plane03.stack, ...)
        %   2. ave.tif contains exactly one image plane
        %
        % If the two conditions conflict (e.g. one plane file but a
        % multi-page ave.tif), a warning is issued and the data is treated
        % as volumetric.
            % Count PlaneXX.stack files (exact pattern: Plane + digits + .stack)
            all_plane_files = dir(fullfile(data_dir, 'Plane*.stack'));
            n_plane_files = 0;
            for f = 1:length(all_plane_files)
                if ~isempty(regexp(all_plane_files(f).name, '^Plane\d+\.stack$', 'once'))
                    n_plane_files = n_plane_files + 1;
                end
            end

            % Count ave.tif pages (0 if ave.tif is absent; downstream stages
            % will raise their own missing-file errors)
            ave_file = fullfile(data_dir, 'ave.tif');
            if exist(ave_file, 'file')
                n_ave_pages = length(imfinfo(ave_file));
            else
                n_ave_pages = 0;
            end

            is_single_plane = (n_plane_files == 1) && (n_ave_pages == 1);

            if is_single_plane
                fprintf(['  [auto_params] Single-plane data detected ' ...
                         '(Plane01.stack only, ave.tif has 1 plane)\n']);
            else
                fprintf('  [auto_params] Volumetric data: %d plane stack files, ave.tif has %d planes\n', ...
                        n_plane_files, n_ave_pages);
                if n_plane_files == 1 && n_ave_pages > 1
                    warning('auto_params:ambiguousMode', ...
                        ['Only Plane01.stack found but ave.tif has %d planes — ' ...
                         'treating data as volumetric. Check the data directory.'], ...
                        n_ave_pages);
                end
            end
        end

    end

    methods (Static, Access = private)

        function [height, width, n_planes] = parse_xml_dimensions(data_dir)
        % PARSE_XML_DIMENSIONS  Extract dimensions from ch0_cam1.xml.
            xml_file = fullfile(data_dir, 'ch0_cam1.xml');

            if ~exist(xml_file, 'file')
                error('auto_params:missingFile', ...
                      'Neither Stack dimensions.log nor ch0_cam1.xml found in: %s', data_dir);
            end

            txt = fileread(xml_file);
            match = regexp(txt, 'dimensions="(\d+)x(\d+)x(\d+)"', 'tokens', 'once');

            if isempty(match)
                error('auto_params:badFormat', ...
                      'Could not parse <dimensions> from ch0_cam1.xml');
            end

            height = str2double(match{1});
            width = str2double(match{2});
            n_planes = str2double(match{3});

            fprintf('  [auto_params] ch0_cam1.xml <dimensions> -> %d x %d x %d (H x W x Z)\n', ...
                    height, width, n_planes);
        end

    end

end
