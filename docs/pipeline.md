# ISP Pipeline Plan

## Milestone order

1. SRAM reader
2. BLC
3. AWB gain
4. Demosaic
5. CCM
6. RGB to YCbCr
7. Edge enhancement and hue
8. RAW and chroma noise reduction
9. LCC
10. AHB register block and Cortex-M0 integration

Each stage must first match the Python golden model before it is enabled in the end-to-end path.

P3 completes stages 1 through 3: SRAM -> Reader -> BLC -> AWB Gain.
AWB here applies externally supplied UQ4.12 gains; automatic white-balance
statistics and gain estimation are outside this implementation. P0/P1 C2
and P2 C3 remain independent boundaries; the formal top outputs first at C4.
See plans/003_p3_awb_gain.md and verification.md for completed acceptance.

## P4 execution target

Advance the current implementation to SRAM -> Reader -> BLC -> AWB Gain ->
3x3 Bilinear Demosaic -> RGB12. Keep AWB-only C4 as awb_pipeline. Spatial
warm-up changes final timing to C(width+7), followed by width*height consecutive
RGB pixels and busy clearing one cycle after the last. See architecture.md and
fixed_point.md for interfaces, three-row scheduling and exact border arithmetic.
