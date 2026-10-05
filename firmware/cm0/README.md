# Cortex-M0 firmware

Firmware integration is intentionally deferred until the standalone ISP datapath is verified.

Planned responsibilities:

- program ISP registers
- configure image dimensions and algorithm parameters
- start a frame
- handle completion/error interrupts
- report status through the existing SoC debug/serial path
