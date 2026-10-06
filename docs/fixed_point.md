# Fixed-point Plan

Initial conventions:

- RAW input: unsigned 12-bit value stored in a 16-bit SRAM word.
- Internal arithmetic should preserve guard bits until the final stage of a module.
- Saturation is preferred over wraparound for pixel outputs.
- Coefficient formats are intentionally not frozen yet; each module will document its chosen format before implementation.

Record every coefficient width, fractional width, rounding rule, and saturation rule here as implementation proceeds.

## P2 BLC integer contract

Input, output and global black level are unsigned RAW12 integers in 0..4095.
The exact result is `max(input - black_level, 0)`: equality gives zero.
There are no fractional bits, multiplication, rounding or upper saturation;
subtract only when input exceeds the offset. The Python reference widens to a
signed integer before subtracting so uint16 underflow cannot wrap.

BLC always registers one stage, including when the offset is zero. Data,
16-bit x/y coordinates and sof/eol/frame_done all cross the same register edge.
With invalid output, all three flags are zero; payload may hold its last value.
Only valid sof samples the frame offset. The first pixel uses the external
offset sampled at that edge, while subsequent pixels use the saved offset.
Synchronous active-low reset clears the offset and all output registers.

The software API is `model.blc.apply_blc(raw, black_level)`: a scalar returns
Python int and an array returns a new same-shape uint16 array. Reject floating
pixels, invalid RAW12 ranges and non-integer/invalid offsets before arithmetic.
`model.isp_model.run_pipeline` reads `pipeline.blc` (default false) and
`blc.offset` (default zero) from a caller-provided dictionary.
