# Fixed-point Plan

Initial conventions:

- RAW input: unsigned 12-bit value stored in a 16-bit SRAM word.
- Internal arithmetic should preserve guard bits until the final stage of a module.
- Saturation is preferred over wraparound for pixel outputs.
- Coefficient formats are intentionally not frozen yet; each module will document its chosen format before implementation.

Record every coefficient width, fractional width, rounding rule, and saturation rule here as implementation proceeds.
