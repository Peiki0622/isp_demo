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
