# Unit testbenches

P0/P1 has two self-checking testbenches:

- `tb_sram_model.sv`: prove registered reads, including unchanged data before the sampling edge.
- `tb_sram_reader.sv`: verify the fixed C0/C1/C2 contract, raster addresses/data/coordinates,
  flags, throughput, frame restart, illegal dimensions, start filtering and reset.

Use `make test-sram-model` or `make test-sram-reader` from the repository root.
The latter includes exact comparison of both principal 16x16 frame dumps,
isolated fatal cases and a SYNTHESIS-defined capacity-rejection run. The shared
VCS runner checks logs and the final PASS marker in addition to the raw exit
code; running simv alone is insufficient on the installed VCS version.

All transient files are kept in `build/p0_p1/` and `testdata/output/p0_p1/`.

Add one testbench per RTL algorithm block, for example `tb_blc.sv`, `tb_awb_gain.sv`, `tb_demosaic.sv`, `tb_ccm.sv`, and `tb_rgb2ycbcr.sv`.

Each testbench should consume deterministic vectors that can also be processed by the Python golden model.

P2 adds `tb_blc.sv`: `make test-blc-unit` verifies exact registered latency,
threshold arithmetic, coordinates/flags, valid holes, invalid sof, frame-stable
offsets, consecutive frames and reset. It also checks output before the sampling
edge to expose combinational bypass. Logs and binaries are in `build/p2_blc/unit/`.
P0/P1 top integration now targets `sram_raw_source` and retains all original
cycle assertions independently of the formal BLC pipeline.
