# Architecture

## Phase 1: standalone ISP pipeline

```text
SRAM -> SRAM reader -> RAW domain -> RGB domain -> YCbCr domain -> output
```

The first milestone deliberately excludes SD-card input and Cortex-M0 control so that the pixel datapath can be verified independently.

## Planned datapath

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
