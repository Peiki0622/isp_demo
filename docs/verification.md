# Verification Strategy

For each algorithm:

```text
test vector
  |----> Python golden model ----> expected data
  |
  +----> RTL + testbench --------> actual data
                                   |
                                   +--> pixel-by-pixel comparison
```

Recommended order: 16x16 flat, gradient, checkerboard, impulse/edge patterns, 768x512 real Bayer RAW, then larger ColorChecker RAW.

Visual inspection is useful for image quality, but it does not replace numerical comparison.

## P0/P1 acceptance contract

Use the current workspace and the container's installed VCS only. SRAM timing
and all public stream semantics are specified in `memory_map.md`; in particular,
the first reader pixel is at C2 relative to an accepted start at C0. The testbench
drives controls on falling edges and checks after rising-edge NBA updates, so
neither race conditions nor a delayed oracle can hide an alignment error.

The principal vector is addr_ramp: pixel i = i modulo 4096. The oracle uses the
external frame dimensions and output index, never DUT internal counters. Check
each logical address, all data and coordinates, consecutive throughput, exact
flag counts, busy timing and absence of extra output. Unknown values are errors.

Required cases include 16x16 twice, 1x1, 2x2, single row/column, a rectangle, zero
dimensions, busy start, held start, changing dimensions during busy, reset during
a frame and restart. A reduced address space tests exact capacity and overflow.
Overflow is an isolated expected failure with a specific diagnostic, never a
license or compilation failure. All simulations have a cycle watchdog.

The installed VCS W-2024.09 can return zero after `$fatal(1, ...)`. Therefore a
normal test passes only when its process status is zero, its log contains no
fatal/error marker, and its unique final PASS marker is present exactly once.
That marker is emitted only after every check, including trailing idle cycles.
The command wrapper must translate a failed verdict into a nonzero exit status.
An intentional failure verifies this translation. Pixel dump comparison is
exact, checks count and format, and returns nonzero on any difference.

## Reproducible commands and evidence

Run from the repository root with the existing local VCS installation:

```sh
make test-p0-p1
make test-sram-reader
make compare-p0-p1
```

`make test-p0-p1` runs 11 Python CLI tests, the independent SRAM timing test,
the reader regression and top-level simulations for addr_ramp, flat, checker and
gradient. Each top-level run checks and dumps two 256-pixel frames. The latter
patterns exercise the full RAW12 range as well as the address-ramp oracle.
The reader also tests a busy start at half-frame, holding that busy start beyond
completion, and size changes to zero/65535 during a frame. Its SYNTHESIS-defined
build confirms both 17x16 and 65535x65535 are rejected in hardware without relying
on simulation-only diagnostics. The normal build checks their exact fatal tag.

All build databases, binaries and logs live under `build/p0_p1/`. Each simulator
directory contains `version.txt`, `context.txt`, `command.txt`, `compile.log`,
and per-case `.command`, `.stdout`, `.log` and `.status` files. The status records
the raw process exit separately from the checked verdict; for the forced fatal
case the installed VCS records `process_exit=0` and `verdict=FAIL`.
Compilation removes the task executable and its VCS timestamp before rebuilding,
so repeated runs cannot succeed using a stale executable or skip a missing one.

Pixel dumps are in `testdata/output/p0_p1/unit/frame_{0,1}.mem` and
`testdata/output/p0_p1/integration/<pattern>/frame_{0,1}.mem`. Generated vectors
are in `testdata/synthetic/`, ignored by Git, and include MEM/NPY/JSON files.
`make clean` only removes these named task products and preserves other runs.

Reproduce an intentional command failure with
`READER_CASE=forced_failure make test-sram-reader`, or provide an absent input via
`MEM_FILE=/absolute/absent.mem make test-sram-reader`. Both must return nonzero.
To check dump failure propagation, modify a copy or a generated dump, then use
`compare_output.py` or `make compare-p0-p1`; restore or regenerate the dump after
the check. A differing pixel reports its index, x/y and expected/actual value.

The final acceptance is `make clean`, a full `make test-p0-p1`, then a second full
run. The deterministic vectors and all ten principal frame dumps must have
identical hashes. Compilation/simulation checks use VCS only; this milestone
does not perform synthesis, timing analysis or make PPA claims.

## P2 acceptance contract

Retain all P0/P1 cycle assertions on the Reader-only `sram_raw_source`.
The BLC unit oracle uses external stimulus and independent integer arithmetic;
integration expected files come from the Python BLC reference, not a duplicate
testbench algorithm. Tests drive on falling edges and check after NBA updates.

Check offset 0/64/1024/4095 and legal threshold neighbors, exact one-register
alignment of data/valid/x/y/all flags, bubbles, invalid sof, simultaneous 1x1
flags, consecutive frames, frame-stable configuration and reset/restart.
Use a nonzero first pixel across a configuration change to expose stale offsets.
At top level additionally check C3 first output, C(N+2) last output with busy,
C(N+3) idle, and start pulses during the BLC-only drain interval.

Four 16x16 patterns run two frames each with offsets: addr_ramp 64/128,
flat 1024/64, checker 512/4095, gradient 256/0. Each frame must have 256 pixels,
one sof, 16 eol and one frame_done. Every valid coordinate and pixel is checked.
No unknown data, extra pixels or invalid-cycle flags are allowed.

Use the existing VCS process/log/unique-PASS verdict and watchdogs for P2.
Forced fatal and corrupted-output cases must propagate failure to Make.
Golden generation must stop on error rather than compare stale data.

## P2 reproducible commands and evidence

```sh
make test-p2-blc
make test-blc-model
make test-blc-unit
make test-blc-pipeline
make compare-p2-blc
```

The complete entry runs P0/P1 first, then 11 Python model/CLI tests, the BLC
unit regression, top-level controls and four-pattern two-frame exact comparison.
The unit also checks output stability before the register edge, invalid sof,
back-to-back 1x1 frames, eight deterministic 64-pixel frames with valid holes,
and synchronous reset while valid. Top controls check 12 small frames, zero-size
rejection, held start, start pulses at final output and the BLC-only drain edge,
mid-frame size changes, reset/restart and exact address-capacity rejection.
Ordinary and SYNTHESIS-defined top builds verify both capacity overflow cases;
the latter proves hardware rejection independently of simulation diagnostics.

`build/p2_blc/unit/`, `pipeline/` and `pipeline_hardware/` retain the exact VCS
version, command, work directory, compile log and per-case checked verdicts.
`testdata/output/p2_blc/golden/<pattern>/frame_{0,1}.mem` and
`integration/<pattern>/frame_{0,1}.mem` are independently compared per frame.
The existing Git ignore rules cover all these generated files; no new ignore
pattern is needed. Clean removes only the named P0/P1 and P2 task directories
and four generated input patterns, preserving reports and other runs.

Normal tests require process exit zero, no fatal/error, and exactly one complete
PASS marker. Isolated forced-fatal, missing-golden and overflow cases require
specific fatal diagnostics and no normal PASS. Golden-file CLI tests confirm
invalid offsets/missing inputs fail and stale targets are removed.

To test propagation through the complete chain, run
`BLC_CORRUPT_OUTPUT=1 make test-p2-blc`: the first pattern's frame 0 dump pixel 42
is changed after simulation and before comparison, so Make must exit nonzero
and report index=42, x=10, y=2. `make compare-p2-blc` must also fail on that dump.
Restore it with `make test-blc-pipeline` without the injection variable.
`BLC_CASE=forced_failure make test-blc-unit` separately demonstrates that the
installed VCS's zero process exit after fatal cannot bypass the wrapper verdict.

Final acceptance is clean, two complete `make test-p2-blc` runs, identical vector/
golden/dump hashes, corruption failure and restoration. This task's evidence is
in `reports/p2_blc_execution/`, preserved outside cleanable simulator databases.
Compilation with SYNTHESIS defined is a functional simulation check, not a
synthesis, timing, FPGA or PPA result.

## P3 acceptance contract

Keep P0/P1 C2 and P2 C3 regressions independently unchanged. Verify AWB
against external integer stimulus at the unit boundary and Python BLC->AWB
golden files at the full pipeline. Falling-edge input drive, pre-edge register
hold checks and post-NBA checks must expose bypass or sideband misalignment.

Cover both green phases, distinct R/B gains, zero/unity/half/fractional/max
gains, rounding midpoint neighbors, saturation, continuous streams, valid
holes, invalid sof, atomic frame configuration, consecutive 1x1 frames and
synchronous reset. The independent AWB-only top must check C4 first output, C(N+3) last
output/busy and C(N+4) idle, AWB-only drain start pulses, held start, latched
dimensions, zero/capacity rejection and reset/restart. Small-frame golden files
must use their actual dimensions because RGGB phase depends on raster width.

Four 16x16 patterns each run two independently configured frames with exactly
256 pixels, one sof, 16 eol and one frame_done, plus external MEM comparison.
Strict VCS verdicts, missing golden, forced fatal, corrupt actual output and
failed golden generation must propagate nonzero. Final acceptance requires
two full P3 regressions with identical deterministic vectors/golden/dump hashes.
Artifacts stay in build/p3_awb and testdata/output/p3_awb; retained evidence
stays in reports/p3_awb_execution outside cleanable simulator databases.

## P3 reproducible commands and evidence

```sh
make clean
make test-p3-awb
make test-p3-awb
make compare-p2-blc
make compare-p3-awb
```

The complete entry first runs test-p2-blc (including all P0/P1), then
test-awb-model, test-awb-unit and test-awb-pipeline in order. There are 33
Python tests: 11 tools, 11 BLC model/CLI and 11 AWB model/CLI. The AWB
unit checks 45,664 register cycles, including 45,056 exhaustive RAW12/gain
pairs across 11 gains, hand-calculated phase/rounding/saturation cases,
configuration atomicity, holes, invalid sof, pre-edge holding and reset unity.

The AWB top controls run ten complete frames for each of 1x1, 2x2, 7x1,
1x7, 3x5 and 4x4. Each dimension uses its own raw input and golden arrays.
They check seven start/size modes, two configuration switches, three zero-size
rejections, synchronous abort and restart. Inputs at start intentionally
differ from the target: black level changes just before C3, gain codes just
before C4, and both are disturbed afterward. Four 16x16 patterns then run
two frames each, with independent golden files and external comparisons.

| Pattern | Frame | Black level | R / G / B codes |
|---|---|---|---|
| addr_ramp | 0 | 64 | 6144 / 4096 / 8192 |
| addr_ramp | 1 | 128 | 4096 / 5120 / 2048 |
| flat | 0 | 1024 | 8192 / 4096 / 6144 |
| flat | 1 | 64 | 4096 / 4096 / 4096 |
| checker | 0 | 512 | 65535 / 2048 / 4096 |
| checker | 1 | 4095 | 0 / 65535 / 4096 |
| gradient | 0 | 256 | 4097 / 6144 / 8192 |
| gradient | 1 | 0 | 2048 / 4096 / 5120 |

Run isolated controls with `bash scripts/run_awb_pipeline.sh controls`.
Normal and SYNTHESIS-defined builds verify capacity rejection; defining
SYNTHESIS is a simulation of the hardware path, not a synthesis result.
`build/p3_awb/{unit,pipeline,pipeline_hardware}/` retains versions, exact
commands, work directories, compile logs and per-case raw/checked verdicts.
Inputs are in `testdata/output/p3_awb/inputs/<WxH>/`, goldens in
`golden/controls/<WxH>/` and `golden/<pattern>/`, and eight actual frame
dumps in `integration/<pattern>/`. No generated artifact belongs in Git.
Clean removes only the named P0/P1/P2/P3 products and standard synthetic
patterns, preserving reports and other run directories.

Failure propagation commands:

```sh
AWB_CASE=forced_failure make test-awb-unit
AWB_CORRUPT_OUTPUT=1 make test-p3-awb
make compare-p3-awb
AWB_GOLDEN_INPUT=/absolute/missing.npy make test-awb-pipeline
```

The corruption command changes only addr_ramp frame 0 actual pixel 42 after
RTL simulation and before comparison. Both the complete command and compare-only
command must fail at index=42, x=10, y=2. Fatal and missing golden cases are
also checked automatically using exact diagnostics and no normal PASS marker.
The missing-input injection must remove the old first golden and stop before
compilation/simulation/comparison. Restore with `make test-awb-pipeline` without
injection variables, then recheck existing dumps. Retained final evidence and
deterministic hashes are in `reports/p3_awb_execution/`; logs and generated
databases are excluded from hash comparisons. No Fmax or PPA conclusion is made.

## P4 acceptance contract

Before changes, rerun the complete current P3. Preserve Reader/BLC/AWB historical
cycle assertions. Window tests independently check all nine samples, exact
raster order, width*height outputs, first-window timing, no gaps and width+1
tail cycles. Test 2x2, 3x2, 2x3, 3x5, 4x4, odd/even combinations, maximum widths,
changing frame sizes, old-row overwrite at width=2, reset in warm-up/stream/tail
and tagged failures. Ordinary and SYNTHESIS-defined simulation must confirm
functional dimension rejection independently of simulation diagnostics.

Demosaic tests cover four phases, half-up midpoint neighbors, zero/4095, all
borders, exact one-register arithmetic timing and busy through final RGB.
Drive testbench input on falling edges and check after NBA updates, using only
public interfaces. Full-chain goldens start at raw SRAM NPY and apply Python
BLC->AWB->Demosaic. Each actual frame dimension gets separate inputs/goldens.
Four 16x16 RGB patterns run two different configurations; RGB36 comparison
requires nine hex digits, exactly width*height entries and channel diagnostics.
Check C(width+7) first RGB, C(N+width+6) last and C(N+width+7) idle, configuration
captures at C3/C4, busy-time starts, held starts, reset/restart and illegal sizes.

Use the existing process/log/unique-PASS VCS verdict and watchdog. Fatal,
missing golden, each corrupted RGB channel and failed golden generation must
propagate nonzero. Failed generation removes stale/partial targets and stops
before compilation. Compare-only never regenerates files. Final acceptance is
clean followed by two complete P4 runs with identical deterministic file hashes.
P4 products live only under build/p4_demosaic and testdata/output/p4_demosaic;
persistent logs/hashes live under reports/p4_demosaic_execution. No synthesis,
timing, PPA or visual-only acceptance is performed.

## P4 reproducible commands and evidence

Run make test-p4-demosaic for sequential P0-P3 plus P4 tools/model/window/unit/
full-chain acceptance. Independent P4 targets are test-demosaic-tools,
test-demosaic-model, test-window-3x3, test-demosaic-unit and
test-demosaic-pipeline. Compare-p4-demosaic only reads existing files.
Five actual small dimensions (2x2,3x2,2x3,3x5,4x4) each run 14 complete control
frames and four aborted/restarted frames. Main constant_rgb, rgb_gradient,
color_blocks and edge_pattern are 16x16 with per-frame offset/gain settings:
frame0=64 and 6144/4096/8192, frame1=128 and 4096/5120/2048. Each frame uses
its own RGB36 golden and actual dump. The total Python test count is 50.

P4 uses normal and SYNTHESIS-defined window, arithmetic and full-chain builds.
Top test MAX_WIDTH=16, ADDR_W=8 separates width overflow (17x2) from address
capacity overflow (16x17 and 2x65535); 16x16 fits exactly. The window tests
also use the real default width capacity 4096. SYNTHESIS-defined compilation
is functional simulation, not synthesis or a physical timing result.

WINDOW_CASE=forced_failure and DEMOSAIC_CASE=forced_failure must fail their
unit Make targets. DEMOSAIC_CORRUPT_OUTPUT=R/G/B must each fail complete
make test-p4-demosaic at index=42,x=10,y=2 and name that channel; existing-file
comparison must fail afterward. Input/golden hashes remain unchanged.
DEMOSAIC_GOLDEN_INPUT pointing to a missing NPY must delete the old target,
leave no partial golden and keep the compilation command timestamp unchanged.
Cancel injection variables and rerun test-demosaic-pipeline to restore all
frames. Final logs, raw/checked fatal verdicts, generation-failure evidence,
recovery, two complete runs and deterministic hashes are retained under
reports/p4_demosaic_execution, outside the clean whitelist.
