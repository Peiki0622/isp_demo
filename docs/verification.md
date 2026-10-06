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
