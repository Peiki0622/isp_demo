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
