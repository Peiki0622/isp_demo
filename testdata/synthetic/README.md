# P0/P1 synthetic vectors

`make patterns` produces four deterministic 16x16 patterns: addr_ramp, flat,
checker and gradient. Each has a uint16 `(height, width)` NPY array, a MEM file
with one four-digit hexadecimal RAW12 value per line, and JSON metadata.
Generated files are ignored by Git and can be rebuilt from the generator.

The primary SRAM oracle is `addr_ramp_16x16.mem`: value at `(x,y)` is
`(y * width + x) % 4096`. The upper four bits of every 16-bit word are zero.

Other dimensions can be generated with
`python3 tools/generate_patterns.py --width W --height H --output DIRECTORY`.
