# Unit testbenches

P0/P1 has two self-checking testbenches:

- `tb_sram_model.sv`: prove registered reads, including unchanged data before the sampling edge.
- `tb_sram_reader.sv`: verify the fixed C0/C1/C2 contract, raster addresses/data/coordinates,
  flags, throughput, frame restart, illegal dimensions, start filtering and reset.

Use `make test-sram-model` or `make test-sram-reader` from the repository root.
The latter includes exact comparison of both principal 16x16 frame dumps,
isolated fatal cases and a SYNTHESIS-defined capacity-rejection run. The shared
VCS runner checks logs and the final PASS marker in addition to the raw exit
code; running simv alone is insufficient on the installed VCS version.

All transient files are kept in `build/p0_p1/` and `testdata/output/p0_p1/`.

Add one testbench per RTL algorithm block, for example `tb_blc.sv`, `tb_awb_gain.sv`, `tb_demosaic.sv`, `tb_ccm.sv`, and `tb_rgb2ycbcr.sv`.

Each testbench should consume deterministic vectors that can also be processed by the Python golden model.

P2 adds `tb_blc.sv`: `make test-blc-unit` verifies exact registered latency,
threshold arithmetic, coordinates/flags, valid holes, invalid sof, frame-stable
offsets, consecutive frames and reset. It also checks output before the sampling
edge to expose combinational bypass. Logs and binaries are in `build/p2_blc/unit/`.
P0/P1 top integration now targets `sram_raw_source` and retains all original
cycle assertions independently of the formal ISP top.

P3 adds tb_awb_gain.sv: make test-awb-unit checks 45,664 registered cycles,
including exhaustive RAW12 inputs for eleven boundary gains, independent
quotient/remainder rounding, all four RGGB positions, shared green, atomic
frame gains, valid holes, invalid sof and reset unity. Hand-calculated cases
check half-up and saturation before narrowing, while pre-edge checks reject
zero/unity combinational bypass. Logs and binaries stay in build/p3_awb/unit.
Forced fatal must propagate through Make even when simv returns zero.

P4 adds tb_window_3x3: make test-window-3x3 checks 64 frames and 22,004 windows,
all 198,036 samples, actual raster order, exact warm-up/continuous/tail cycles,
widths 4095/4096, changing sizes and reset without clearing line arrays.
make test-demosaic-unit checks 64 frames, 2,566 RGB pixels and an independent
nearest-color quotient/remainder oracle. Both check pre-edge register hold,
all coordinates/flags, final-output busy, tagged fatal and normal/SYNTHESIS
functional dimension handling. Synthesizable RTL contains no function; helper
functions exist only in testbenches to keep the independent oracle readable.
All P4 logs and binaries are isolated under build/p4_demosaic.

P5 adds tb_ccm.sv: make test-ccm-unit runs normal and SYNTHESIS-defined functional
builds, each checking 6,504 cycles, 6,494 RGB pixels and 19,482 channel results.
An independent longint quotient/remainder oracle tests eleven matrices against
216 boundary RGB combinations each, then 4,096 continuous pixels. Asymmetric
rows detect transposition; signed16 extremes, product cancellation, fractional
rounding, lower clamp and upper saturation are included. Checks cover two-stage
pre-edge hold, metadata delay, valid holes/invalid sof, all-nine atomic capture,
first-pixel new coefficients, deterministic random mid-frame disturbances,
consecutive 1x1 frames and reset in either stage. Busy covers both valid stages
without blocking incoming pixels. Forced fatal is checked by log and unique
PASS verdict, with binaries/logs isolated under build/p5_ccm/unit. Functions
used for the testbench oracle are never included in synthesizable CCM RTL.
