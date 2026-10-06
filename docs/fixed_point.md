# Fixed-point Plan

Initial conventions:

- RAW input: unsigned 12-bit value stored in a 16-bit SRAM word.
- Internal arithmetic should preserve guard bits until the final stage of a module.
- Saturation is preferred over wraparound for pixel outputs.
- Implemented coefficient formats are frozen below; future modules will document their formats before implementation.

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

## P3 AWB Gain frozen contract

AWB Gain applies external gains; it does not estimate automatic white balance.
Pixels are unsigned RAW12 (0..4095). Gains are unsigned 16-bit UQ4.12 register
codes (0..65535), with FRAC_W=12 and 4096=1.0. Compute exactly
`min((pixel * gain_code + 2048) >> 12, 4095)`. Preserve the 28-bit product
and a 29-bit biased sum; compare the full scaled value before narrowing to
12 bits. Round-half-up sends pixel=1, gain=2048 to 1. Pixel=4095, gain=4097
rounds to 4096 and must saturate to 4095. No floating exchange format is used.

RGGB uses input coordinates: even y/even x selects R, even y/odd x and odd
y/even x select the shared G, odd y/odd x selects B. All three frame gains
update together only at valid sof. That first pixel uses external configuration
at the capture edge; subsequent pixels use saved gains despite input changes.
Invalid sof does not update configuration. Synchronous active-low reset restores
all saved gains to 4096 and clears outputs. AWB always registers exactly one
stage, including unity or zero gain: valid, data, x/y and flags remain aligned.
Invalid output has zero sof/eol/frame_done; data and coordinates may hold.
