# Python golden model

This directory contains the software reference implementation used to verify RTL numerically.

Favor clarity and explicit fixed-point emulation over speed. Floating-point prototypes may be used first, but each RTL-facing module should eventually have a matching fixed-point reference path.

P2 implements `blc.apply_blc` and `isp_model.run_pipeline` using exact integer
RAW12 arithmetic. Run `make test-blc-model` for threshold, array, configuration
and golden-file CLI tests. Generate a frame with `python3 -m
model.generate_blc_golden --input INPUT.npy --output OUTPUT.mem --black-level B`.
The caller provides ordinary configuration dictionaries; YAML parsing is not
part of this milestone. Pipeline cycle/sof configuration capture is checked in
RTL tests rather than inferred from this per-frame numerical model.

P3 adds awb_gain.scale_pixel(pixel, gain_code) and apply_awb_gain(raw_2d, r, g, b).
The format is fixed UQ4.12 (4096=unity); images must be nonempty 2D integer
RAW12 arrays. All intermediate arithmetic widens before multiplication, and
outputs are new uint16 arrays. run_pipeline applies BLC then AWB, with missing
enables defaulting to false and missing gains to 4096. Run make test-awb-model.

Generate full-chain P3 golden files with:

```sh
python3 -m model.generate_awb_golden --input INPUT.npy --output OUTPUT.mem \
  --black-level 64 --gain-r 8192 --gain-g 2048 --gain-b 6144
```

The CLI always applies BLC then AWB to the original SRAM array; it removes
its old target before generation and returns nonzero for invalid data/config.
Golden files use each frame's real dimensions, including odd-width frames.

P4 adds demosaic.apply_demosaic(raw_2d): require integer RAW12 of at least 2x2,
use phase-preserving reflect and return a new uint16 (H,W,3) RGB12 array.
run_pipeline applies BLC, AWB, then Demosaic when pipeline.demosaic is true;
missing enable remains false for historical RAW callers. Default project YAML
enables BLC/AWB/Demosaic; P5 also enables CCM, while parsing remains caller-owned.
Use make test-demosaic-model and make test-demosaic-tools. Generate full-chain
RGB36 with python3 -m model.generate_demosaic_golden using the same --input,
--output, --black-level and three gain-code options as P3. Each pixel is exactly
nine hexadecimal digits, R/G/B each occupying 12 bits. The CLI removes stale
and partial targets on computation/I/O failure and protects identical input/
output paths. No image library is required; numerical comparison is acceptance.

P5 adds ccm.apply_ccm(rgb, matrix): require nonempty integer (H,W,3) RGB12 and
exactly a 3x3 matrix of signed16 integer codes (-32768..32767, 4096=unity).
Rows select output channels; use int64 dot products, clamp accumulators <=0,
round positive values half-up with +2048 and >>12, then saturate to 4095 before
uint16 conversion. Inputs are never modified. Boolean/floating coefficients
are rejected even in mixed lists. run_pipeline applies CCM after Demosaic;
missing enable remains false and missing matrix defaults to integer identity.
Enabling CCM on a 2D RAW result raises ValueError. make test-ccm-model runs
8 numerical/configuration tests and 7 full-chain golden CLI tests.

```sh
python3 -m model.generate_ccm_golden --input INPUT.npy --output OUTPUT.mem \
  --black-level 64 --gain-r 6144 --gain-g 4096 --gain-b 8192 \
  --matrix 5120 -512 -512 -256 4608 -256 -512 -512 5120
```

The nine codes are row-major integers. The CLI starts from original SRAM Bayer
and applies BLC->AWB->Demosaic->CCM; RGB36 format and strict dimensions match P4.
It removes stale/partial targets on invalid matrix/input/config or I/O failure,
protects identical input/output paths, and needs no image library. Frame-level
numerical modeling does not replace cycle/configuration capture checks in RTL.
