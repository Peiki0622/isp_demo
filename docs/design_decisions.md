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
