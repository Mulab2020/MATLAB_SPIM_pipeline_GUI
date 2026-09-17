# Changelog

All notable changes to the SPIM Pipeline GUI project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Time course extraction default baseline normalization** (`+pipeline/get_cell_tcourse.m`): rolling-percentile dF/F (`(F - bg - F0) / (max(F0,0) + offset)`, cf. "Baseline normalization" in Mu et al., 2019, Cell 178, 27–43) is now the default and background subtraction is always applied; the exponential photobleaching fit moved to an optional legacy path (`enable_photobleach_fit`, default off, applied before detrending when enabled)
- `+util/rolling_percentile_filter.m` replaced with the per-sample sliding-window algorithm from `common_20210823/new pipeline` (running sorted window + `binary_search`; new dependency `+util/binary_search.m`), replacing the previous block-based implementation. Two bugs in the original were fixed during the port: insertion of a new running minimum corrupted the sorted window (affects drifting/bleaching traces), and column-vector inputs crashed; verified against a brute-force sliding-window reference
- Output filenames carry a suffix only for non-default options (`_expfit`, `_nodetrend`, `_dedup`, `_motionfiltered`); the default output name `cell_resp_processed.stackf` is unchanged so batch resume keeps working

### Added

- Inferred baseline persistence: stage 3 writes a single `cell_resp_baseline.mat` (v7.3) containing the F0 matrix (`f0_all`) and a provenance struct `rolling_baseline` (window, percentile, offset, background level)
- Stage 3 parameters exposed in the GUI (main Step 3 panel and batch options dialog): detrending window (frames), percentile, F0 offset, exponential-fit toggle + baseline window (s), dedup correlation threshold, motion threshold (px); parameter fields grey out when their option is disabled
- Pipeline params: `detrend_window_frames` (600), `detrend_percentile` (15), `detrend_offset` (10), `enable_photobleach_fit` (false), `baseline_window_seconds` (180), `dedup_corr_threshold` (0.7), `motion_threshold_pixels` (1)

### Removed

- `baseline_fit.mat` is no longer written (exponential-fit internals were diagnostics-only); the exponential fit itself remains available via `enable_photobleach_fit`

### Added

- Single-plane (2D) dataset support with automatic detection (`util.auto_params.detect_mode`): data with only `Plane01.stack` and a single-page `ave.tif` runs with `slice = 1` for all detected cells, XY-only motion estimation (Z skipped, Z stats = 0), and duplicate-cell removal skipped automatically
- Single-plane awareness in the GUI: data mode logged on browse, "Remove double-counted cells" checkbox disabled, plane navigator hidden

### Fixed

- Single-plane frame rate: line 1 of `Stack_frequency.txt` is the stack (volume) frequency, not the per-frame rate — for single-plane data `util.auto_params.detect_all` now returns stack frequency × frames per stack (metadata Z from `Stack dimensions.log`), fixing seconds→frames conversions (`zcycle` in motion correction, exp-fit/dedup baseline window in time course extraction) for single-plane datasets
- GUI: the exponential-fit window parameter now sits next to its option in both the Step 3 panel and the batch options dialog (it was previously grouped with the detrending parameters)
- GUI: parameter labels carry units in both the main window and the batch options dialog (threshold a.u., detrend window frames, percentile %, F0 offset a.u., exp window s)
- GUI: the batch options dialog no longer overwrites the main window's Step 3 checkbox handles (nested-function variable shadowing), which previously caused "Invalid or deleted object" errors after running batch mode

## [1.4] — 2026-06-30

### Added

- GUI application (`gui/SPIM_Pipeline.m`) with interactive cell segmentation threshold slider, stage run buttons, batch import, and output log
- Cell segmentation stage (`+pipeline/recog_wholefish.m`) using local contrast enhancement and local-maxima detection
- Motion correction stage (`+pipeline/check_motion.m`) using FFT-based 2D cross-correlation with `parfor` parallelism
- GPU-accelerated motion correction variant (`+pipeline/check_motion_gpu.m`)
- Time course extraction stage (`+pipeline/get_cell_tcourse.m`) with exponential photobleaching baseline correction
- Batch processing over multiple data directories (`+pipeline/batch_process.m`)
- File I/O package (`+fileIO/`) for TIFF and custom binary `.stackf` formats via compiled MEX binaries
- Utility package (`+util/`) with auto-parameter detection, image normalization, rolling percentile filtering, and worker-count optimization
- Headless pipeline runner (`run_pipeline.m`) for scripted/CLI usage
- GUI launcher (`launch_gui.m`) that handles MATLAB path setup
- Resumable pipeline operation (each stage skips if output files already exist)

### Known Issues

- `check_motion_gpu.m` has a struct-array pre-allocation defect in the `parfor` loop causing runtime broadcast-variable violations
- MEX binaries are compiled for Windows 64-bit only; recompilation from included `.cpp` source is needed for other platforms
- Microscope physical constants (0.406 µm/pixel XY, 5 µm Z step) are hardcoded in the stage implementations
