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

## P0/P1 SRAM reader contract

SRAM reads are synchronous: an address stable before a rising edge is sampled
at that edge, and `rdata` updates after that edge. The reader consumes that
registered data at the following rising edge. There is no read enable and no
pixel ready/backpressure input.

Let C0 be the rising edge accepting `start`, and N = width * height:

| Edge | Reader / SRAM behavior |
|---|---|
| C0 | Latch dimensions; assert busy; present address 0 |
| C1 | SRAM samples address 0; reader registers request metadata |
| C2 | First valid pixel, with x=0, y=0 and sof=1 |
| C1 through CN | Logical requests sample addresses 0 through N-1 exactly once |
| C2 through C(N+1) | N consecutive valid pixels, without bubbles |
| C(N+1) | Last valid pixel; eol=1, frame_done=1, busy=1 |
| C(N+2) | busy=0; pixel_valid, sof, eol and frame_done are 0 |

Only C1 through CN constitute logical requests. The always-reading model may
sample a held address outside that window; those samples never become valid
pixels. The last address is held until a new accepted start or reset.

- `start` is accepted on a rising transition while idle. Busy transitions are
  ignored, and a high level held across completion does not start another frame.
  A subsequent frame needs a new low-to-high transition after busy is observed low.
- Width and height are unsigned 16-bit values, latched only on accepted start.
  Changes during a frame have no effect.
- Zero width or height is ignored. A nonzero frame larger than `2**ADDR_W` is
  rejected; simulation additionally reports `SRAM_FRAME_TOO_LARGE`.
- Pixel data contains the low `PIXEL_W` bits of each 16-bit SRAM word (default 12).
  x/y are unsigned 16-bit coordinates. sof marks only the first pixel; eol marks
  each row's last pixel; frame_done marks only the frame's last pixel.
- On invalid cycles sof/eol/frame_done are zero; pixel data and coordinates may
  hold their previous values. Synchronous active-low reset clears busy, address,
  pixel data, coordinates, flags and all pending requests, aborting any frame.
- The final pixel and completion flag are simultaneous. In a 1x1 frame, sof,
  eol and frame_done are all asserted with that sole valid pixel.

## ISP register map

Not frozen yet. Intended controls include image size, start/status, bypass bits, BLC offset, channel gains, CCM coefficients, noise-reduction strength, hue controls, LCC controls, and edge-enhancement gain.
