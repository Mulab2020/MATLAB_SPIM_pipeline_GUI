# SPIM Pipeline GUI v1.4

A MATLAB application for processing light-sheet microscopy (SPIM) calcium imaging data of zebrafish larvae. Converts registered multi-plane image stacks into fluorescence time-course data for individual neurons through a three-stage pipeline.

## Pipeline Stages

1. **Cell Segmentation** (`recog_wholefish`) — Identifies neuronal cell bodies in a pre-computed average anatomy stack (`ave.tif`) using local contrast enhancement and local-maxima detection. A brightness threshold (set via slider in the GUI or passed as an argument) controls segmentation sensitivity.

2. **Motion Correction** (`check_motion` / `check_motion_gpu`) — Estimates and corrects tissue motion over time using FFT-based 2D cross-correlation on a grid of points across each z-plane. A reference is built from the first time block; each subsequent block is registered against it. A GPU-accelerated variant exists but has a known defect (see [Known Issues](#known-issues)).

3. **Time Course Extraction** (`get_cell_tcourse`) — Reads per-plane time-series stacks (`PlaneXX.stack`), extracts mean fluorescence within each cell's ROI over time, subtracts the background level (bottom 5% of `Background_1.tif`), and normalizes each trace with a rolling-percentile baseline (cf. "Baseline normalization" in Mu et al., 2019, Cell 178, 27–43):

   ```
   F0   = rolling percentile of (F - bg)    (per-sample sliding window)
   dF/F = (F - bg - F0) / (max(F0, 0) + offset)
   ```

   The legacy exponential photobleaching fit is available as an option (applied before detrending when enabled). Optional post-processing: duplicate-cell removal and motion-based cell filtering. The inferred baseline F0 is saved (`cell_resp_baseline.mat`) so it does not need to be recomputed downstream.

   | Parameter | Default | Description |
   |-----------|---------|-------------|
   | `enable_detrending` | `true` | Rolling-percentile dF/F normalization |
   | `detrend_window_frames` | `600` | Sliding-window length (frames) |
   | `detrend_percentile` | `15` | Baseline percentile (0–100) |
   | `detrend_offset` | `10` | Offset added to F0 in the denominator |
   | `enable_photobleach_fit` | `false` | Legacy exponential photobleaching fit |
   | `baseline_window_seconds` | `180` | Exp-fit baseline window (s) |
   | `dedup_corr_threshold` | `0.7` | Duplicate-removal correlation threshold |
   | `motion_threshold_pixels` | `1` | Motion-filtering threshold (pixels) |

   All parameters are exposed in the GUI (Step 3 panel and the batch options dialog).

## Single-Plane Mode

Single-plane (2D) datasets are detected automatically. Detection criteria (both must hold):

- Only `Plane01.stack` is present (no `Plane02.stack`, `Plane03.stack`, …)
- `ave.tif` contains exactly one image plane

When single-plane data is detected:

| Aspect | Behavior |
|--------|----------|
| Cell segmentation | Runs on the single plane; all cells get `slice = 1` |
| Motion correction | XY only — Z estimation and its plots are skipped (Z stats = 0) |
| Duplicate-cell removal | Skipped automatically (no adjacent z-planes); the GUI disables the option |
| Frame rate | Line 1 of `Stack_frequency.txt` is the stack (volume) frequency; the effective per-frame rate is stack frequency × frames per stack (the Z value from `Stack dimensions.log`) |
| Metadata plane count | Overridden to 1, even if `Stack dimensions.log` claims otherwise (its Z value is used as frames-per-stack for the frame-rate correction) |

If the two detection criteria conflict (e.g. only `Plane01.stack` but a multi-page `ave.tif`), a warning is issued and the data is treated as volumetric.

## Requirements

- **MATLAB** R2021b or later (developed on R2025b)
- **Image Processing Toolbox**
- **Parallel Computing Toolbox** (required for `parfor`, `gpuArray`; GPU is optional for motion correction)


## Usage

### GUI

Launch the graphical interface by running MATLAB in the project root:

```matlab
>> launch_gui()
```

This opens the **SPIM Pipeline v1.4** window (1200×820 px) with:

- **Left sidebar** — Data directory browser, brightness threshold slider, stage run buttons, optional processing toggles, batch import, and an output log.
- **Right panel** — Preview/image display area and pipeline output.

Workflow:

1. Click **Browse** and select a data directory containing the expected input files.
2. Adjust the **brightness threshold** slider to tune cell segmentation sensitivity.
3. Click **Stage 1: Segment** to run cell detection. Review the overlaid cell mask in the preview panel and adjust the threshold as needed.
4. Click **Stage 2: Motion** to run motion correction (CPU or GPU, depending on the checkbox).
5. Click **Stage 3: Extract** to run time course extraction with rolling-percentile detrending (default) and optional exponential photobleaching fit / duplicate removal / motion filtering. Detrending parameters (window, percentile, F0 offset) and filter thresholds are editable in the Step 3 panel.

### Command Line

Run the full pipeline headlessly from a script or the command window:

```matlab
>> run_pipeline('Z:\path\to\data_dir', 120)
```

Optional third argument — a `params` struct:

```matlab
>> params = struct(...
    'test_minutes', 5, ...           % limit to first N minutes (dev/testing)
    'use_gpu', false, ...            % use GPU for motion correction
    'enable_detrending', true, ...   % rolling-percentile dF/F normalization (default)
    'detrend_window_frames', 600, ...% sliding-window length in frames
    'detrend_percentile', 15, ...    % baseline percentile (0-100)
    'detrend_offset', 10, ...        % offset added to F0 in the denominator
    'enable_photobleach_fit', false, ... % legacy exponential fit (before detrending)
    'enable_remove_duplicates', false, ... % remove double-counted cells
    'enable_motion_filter', false);  % motion-based cell filtering
>> run_pipeline('Z:\path\to\data_dir', 120, params)
```

### Batch Processing

Process multiple data directories from a text-file list (one path per line):

```matlab
>> results = pipeline.batch_process('batch/batch_list.txt', 120)
```

Batch processing groups work by stage — all directories are segmented first, then all motion-corrected, then all time courses extracted. Progress is displayed and an abort button is available.

## Expected Input Data

Each data directory must contain:

| File | Description |
|------|-------------|
| `ave.tif` | Pre-computed average anatomy stack (multi-page TIFF, one slice per z-plane) |
| `Stack_frequency.txt` | Frame-rate metadata (3 lines: Hz, duration, volume count) |
| `Stack dimensions.log` or `ch0_cam1.xml` | Image dimensions (width × height) |
| `minANDmax.txt` | Frame range metadata |
| `Plane01.stack`, `Plane02.stack`, … | Per-plane time-series stacks in custom binary format (single-plane data has only `Plane01.stack`) |

The `.stackf` files are read via compiled MEX binaries (Windows 64-bit). MEX source code (`.cpp`) is included in `+fileIO/` and `+util/` for recompilation on other platforms.

## Output Files

Written to the same data directory:

| File | Stage | Description |
|------|-------|-------------|
| `cell_info.mat` | 1 | Struct array of detected cells (centroid, area, pixel indices, z-slice) |
| `cellmask_<threshold>.tif` | 1 | RGB cell mask overlay for validation |
| `motion_param.mat` | 2 | Motion estimates per z-plane (tilt, displacements) |
| `motion.tif` | 2 | Per-plane motion visualization |
| `motion_graph.tif` | 2 | Summary motion plot |
| `cell_resp_processed.stackf` | 3 | Normalized (rolling-percentile dF/F) fluorescence time courses (float32 binary) |
| `cell_resp_baseline.mat` | 3 | Inferred rolling-percentile baseline F0 per cell (`f0_all`, float32) plus provenance struct (`rolling_baseline`: window, percentile, offset, background level); written when detrending is on |
| `cell_info_processed.mat` | 3 | Filtered cell info |
| `cell_resp_dim_processed.mat` | 3 | Dimensions of the processed response array |

## Project Structure

```
.
├── launch_gui.m                  # GUI entry point
├── run_pipeline.m                # CLI / headless entry point
├── gui/
│   └── SPIM_Pipeline.m           # Main GUI application figure and callbacks
├── +pipeline/                    # Pipeline stage implementations
│   ├── recog_wholefish.m         #   Stage 1: cell segmentation
│   ├── check_motion.m            #   Stage 2: motion correction (CPU / parfor)
│   ├── check_motion_gpu.m        #   Stage 2: motion correction (GPU-accelerated)
│   ├── get_cell_tcourse.m        #   Stage 3: fluorescence time course extraction
│   └── batch_process.m           #   Batch runner over multiple data directories
├── +fileIO/                      # File I/O (TIFF, custom binary stack format)
│   ├── readtiff.m / writetiff.m  #   TIFF readers & writers (including ImageJ)
│   ├── read_LSstack_fast*.m      #   Custom .stackf format readers
│   ├── write_LSstack_fast*.m     #   Custom .stackf format writers
│   ├── registerStacks*.m         #   FFT-based stack registration utilities
│   ├── *.mexw64                  #   Compiled MEX binaries (Windows 64-bit)
│   └── *.cpp                     #   MEX C++ source code
├── +util/                        # Utility functions
│   ├── auto_params.m             #   Auto-detection of acquisition metadata
│   ├── imNormalize99.m           #   99th-percentile image normalization
│   ├── rolling_percentile_filter.m #   Per-sample sliding-window percentile baseline
│   ├── binary_search.m             #   Sorted-vector insertion point (filter helper)
│   ├── get_optimal_workers.m     #   Optimal parfor worker count
│   └── ...
├── archive/                      # Benchmarks and historical reports
│   ├── benchmark_report.md       #   CPU vs GPU motion correction benchmark (June 2026)
│   └── benchmark_motion.m        #   Benchmark harness script
└── batch/
    └── batch_list.txt            #   Example batch directory list
```

## Configuration

### Physical Constants

The pipeline uses hardcoded microscope parameters:

| Parameter | Value | Used in |
|-----------|-------|---------|
| XY pixel size | 0.406 µm | Cell segmentation, motion correction |
| Z step | 5 µm | Cell segmentation |

These are defined inside `recog_wholefish.m` and `check_motion.m` — adjust them there if your setup differs.

### Parallel Workers

The number of `parfor` workers is auto-selected based on available cores (see `+util/get_optimal_workers.m`). If the Parallel Computing Toolbox is unavailable, the code falls back to serial execution.

## Known Issues

- **`check_motion_gpu.m` is broken** — A missing struct-array pre-allocation before the `parfor` loop causes a broadcast-variable violation at runtime. The CPU version (`check_motion.m`) works correctly. See `archive/benchmark_report.md` for the diagnosis and fix.
- **Resumable operation** — Each stage checks for existing output files and skips if present (unless `force_rerun` is set internally). Delete or rename prior output files to force a fresh run.
- **Windows-only MEX binaries** — The compiled `.mexw64` files are Windows-specific. MEX source (`.cpp`) is provided; recompile with `mex` on macOS/Linux if needed.

## License

Proprietary — contact the author for usage terms.
