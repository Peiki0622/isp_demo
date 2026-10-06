# Design Decisions

This repository is a reconstruction of an earlier internship project whose original source code is unavailable.

## Confirmed from the original block diagram

- Cortex-M0 control core
- AHB system/peripheral buses
- ISP stages include BLC, RAW NR, AWB gain, demosaic, CCM, color-space conversion, chroma NR, hue, LCC/AI, edge enhancement, and output

## Reconstruction choices

- Phase-1 input source: SRAM
- Baseline Bayer pattern: RGGB
- RAW precision: 12 effective bits in a 16-bit word
- Software golden model: Python
- RTL language: SystemVerilog where convenient
- Complex post-processing modules start in bypass mode

## Not yet confirmed

- Exact original RAW-noise-reduction algorithm
- Exact original demosaic algorithm
- Exact meaning/algorithm of the original AI/LCC block
- Original fixed-point widths and coefficients

These must be documented as reconstruction choices rather than historical facts.

## P2 BLC reconstruction choices

- Use one global, nonnegative RAW12 offset, rather than four Bayer offsets or
  automatic estimation. This is an engineering choice, not a recovered fact
  about the original internship implementation.
- Capture configuration at valid sof, not start. Mid-frame input changes apply
  only to the next frame; the first pixel must use the newly sampled value.
- Preserve the verified Reader-only boundary as `sram_raw_source`; keep its
  C0/C1/C2 timing independently testable when the formal top gains BLC.
- Extend pipeline busy through the final BLC output. Filter external start
  edges using the whole pipeline's busy, remembering busy-time transitions so
  a high level held across completion cannot silently restart a frame.
- Keep the current VCS flow and Python/NumPy dependencies. No bypass, further
  algorithm, register bus or synthesis/PPA milestone is added in P2.

The implementation uses separate register blocks for frame configuration,
pixel arithmetic, coordinates, valid and flags. Source still uses the existing
three-part Reader FSM; neither the top wrapper nor the single-stage
BLC introduces an unnecessary FSM. Synthesizable additions contain no function,
initialization, testbench system task or algorithm beyond BLC.

## P3 AWB Gain reconstruction choices

Use RGGB with three external UQ4.12 R/G/B gains and shared green, integer
round-half-up and RAW12 saturation. This implements gain application only;
automatic estimation, statistics and other Bayer patterns are outside P3.
Capture gains atomically at valid sof, use new configuration for that first
pixel and reset saved gains to unity. Keep one register stage with separate
configuration, data, coordinates, valid and flag blocks, and no RTL functions.
No new FSM is needed; the Reader retains its three-part FSM.

Preserve Reader-only C2 as sram_raw_source and move the unchanged P2 C3
implementation to blc_pipeline. The formal isp_pipeline_top adds AWB and its
own external start history so the AWB drain period remains busy. No speculative
retiming, bus, automatic AWB, further algorithm or synthesis/PPA claim is added.
Default enables reflect completed stages: only BLC and AWB Gain are enabled.
Small-frame integration golden files use their actual dimensions; reusing the
first N pixels of a 16x16 golden would select wrong Bayer phases at odd widths.

## P4 reconstruction choices

Implement fixed RGGB 3x3 bilinear demosaic with phase-preserving reflect borders
and full-size RGB12 output. This is a reconstruction choice, not a recovered
original algorithm. Malvar-He-Cutler, edge-aware interpolation and other ISP
stages remain future work. Three rotating row stores establish correctness;
two-line BRAM optimization and physical implementation are separate milestones.
Use the current HEAD, preserve historical public test interfaces, and keep
configuration defaults disabled until full P4 acceptance. The window introduces
a necessary three-part tail FSM; arithmetic and top wrappers need no new FSM.
All new ports and long blocks receive grouped explanatory comments, and all
synthesizable registers are separated by function. Keep local VCS and the
existing Python/NumPy/unittest dependencies without image/YAML dependencies.

P4 functional acceptance enables BLC, AWB Gain and Demosaic in the default
configuration. Final regression includes complete historical boundaries and
per-channel corruption through the full Make entry, stale-golden rejection,
recovery and two complete deterministic runs. Pixel input stays RAW12/SRAM16;
formal output is RGB12/RGB36. Optional PPM preview remains future tooling.

## P5 reconstruction choices

Use a 3x3 signed matrix without offsets: signed 16-bit coefficients, 12
fractional bits, product29 and accumulator31, positive half-up rounding and
RGB12 clamp. This is a reconstruction choice rather than a recovered original
format. Two fixed register stages avoid a long multiply/add/clamp stage while
retaining throughput. Separate configuration, products, coordinates, valid,
flags and output registers; no RTL function or unnecessary FSM is added.

Preserve current P4 behavior as demosaic_pipeline instead of shifting old
assertions. Complete current-version P0-P4 acceptance precedes changes.
The optional P5 PNG preview reuses P4 tooling and remains outside acceptance
dependencies. No synthesis, physical timing or DSP/BRAM resource claim is made.

After complete initial P0-P5 acceptance, enable default integer identity CCM.
Clean and two further complete runs pass; retain 430 equal deterministic hashes
and unchanged historical 282 files. Defaults add no new color algorithm.
