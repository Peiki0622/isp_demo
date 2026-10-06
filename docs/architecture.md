# Architecture

## Phase 1: standalone ISP pipeline

```text
SRAM -> SRAM reader -> RAW domain -> RGB domain -> YCbCr domain -> output
```

The first milestone deliberately excludes SD-card input and Cortex-M0 control so that the pixel datapath can be verified independently.

P0/P1's verified `SRAM -> sram_reader -> RAW pixel stream` is now exposed
through `sram_raw_source`. This wrapper adds no registers or algorithm and
retains the C2 first-pixel contract independently of the formal ISP top.
See `memory_map.md` for the Source/Reader cycle contract.

## P2 implementation contract

The Reader-only boundary is implemented by `sram_raw_source` without extra registers.
The formal top implements `SRAM -> sram_raw_source -> blc -> RAW12 output`.
Its added `black_level[PIXEL_W-1:0]` input configures the global offset.
BLC consumes in_valid/in_pixel/in_x/in_y/in_sof/in_eol/in_frame_done and
produces their registered out_* equivalents; coordinates remain 16 bits.
There is no backpressure interface.

For an accepted start at C0 and N pixels, SRAM requests remain C1..CN,
Source outputs remain C2..C(N+1), and BLC outputs occur at C3..C(N+2).
The top asserts busy at C0 and keeps it high at final frame_done C(N+2), then
clears it at C(N+3). Busy is the OR of Source busy and registered BLC valid.
Only a new start edge sampled while this complete pipeline is idle reaches
the Source. Zero-size and oversized frame handling remains in the Reader.

The first BLC capture is C3: changing black_level between start and that
capture changes the frame configuration. Later changes do not affect the
frame. Reset simultaneously aborts Source and BLC and clears start history.

## Future datapath

```text
SRAM
 -> BLC
 -> Raw NR        [initially bypassed]
 -> AWB Gain
 -> Demosaic
 -> CCM
 -> RGB-to-YCbCr
 -> Chroma NR     [initially bypassed]
 -> Hue           [initially bypassed]
 -> LCC           [initially bypassed]
 -> Edge Enhance  [initially bypassed]
 -> Output
```

## Phase 2: SoC reintegration

Cortex-M0 will configure the ISP through AHB (Advanced High-performance Bus) mapped registers. Pixel processing remains in the hardware pipeline.

## P3 target interface and timing

The formal top will implement `SRAM -> blc_pipeline -> awb_gain -> RAW12`.
The independent blc_pipeline preserves P2's C3 first pixel and all previous
control assertions. AWB adds unsigned 16-bit gain_r/gain_g/gain_b ports and
uses input x/y for RGGB phase selection. It outputs one registered stage
with all data/coordinates/flags and no backpressure.

For N pixels accepted at C0, requests remain C1..CN, Reader C2..C(N+1),
BLC C3..C(N+2), final AWB C4..C(N+3). Final busy stays high through
C(N+3) and becomes zero at C(N+4). BLC configuration captures at C3 and
AWB configuration at C4, independently of C0. Top start filtering uses
`blc_busy || final_valid` and remembers every external start sample, including
busy cycles. Busy pulses and held-high start across completion cannot restart.
Reset aborts all stages and clears the external start history.
