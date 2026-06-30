# Changelog

All notable changes to the SPIM Pipeline GUI project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
