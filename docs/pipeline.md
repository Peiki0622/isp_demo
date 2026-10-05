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
