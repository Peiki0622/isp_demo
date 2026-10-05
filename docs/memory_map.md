# Register and Memory Map

## SRAM image layout

- Bayer pattern: RGGB
- Effective pixel width: 12 bits
- SRAM word width: 16 bits
- One pixel per word
- Upper four bits are zero
- Raster-scan order

```text
addr = y * width + x
```

## ISP register map

Not frozen yet. Intended controls include image size, start/status, bypass bits, BLC offset, channel gains, CCM coefficients, noise-reduction strength, hue controls, LCC controls, and edge-enhancement gain.
