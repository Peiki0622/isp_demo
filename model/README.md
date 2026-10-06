# Python golden model

This directory contains the software reference implementation used to verify RTL numerically.

Favor clarity and explicit fixed-point emulation over speed. Floating-point prototypes may be used first, but each RTL-facing module should eventually have a matching fixed-point reference path.

P2 implements `blc.apply_blc` and `isp_model.run_pipeline` using exact integer
RAW12 arithmetic. Run `make test-blc-model` for threshold, array, configuration
and golden-file CLI tests. Generate a frame with `python3 -m
model.generate_blc_golden --input INPUT.npy --output OUTPUT.mem --black-level B`.
The caller provides ordinary configuration dictionaries; YAML parsing is not
part of this milestone. Pipeline cycle/sof configuration capture is checked in
RTL tests rather than inferred from this per-frame numerical model.
