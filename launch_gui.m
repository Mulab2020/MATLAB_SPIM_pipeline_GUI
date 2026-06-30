function launch_gui()
% LAUNCH_GUI  Open the SPIM Pipeline GUI.
%
%   launch_gui()
%
% Ensures v1_pipeline and its gui/ subfolder are on the MATLAB path,
% then opens the pipeline application window.

    v1_root = fileparts(mfilename('fullpath'));

    if isempty(which('pipeline.recog_wholefish'))
        addpath(v1_root);
    end

    gui_dir = fullfile(v1_root, 'gui');
    if isempty(which('SPIM_Pipeline'))
        addpath(gui_dir);
    end

    SPIM_Pipeline();
end
