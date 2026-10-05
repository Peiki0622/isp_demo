module sram_model #(
    parameter int ADDR_W = 20,
    parameter int DATA_W = 16,
    parameter int DEPTH  = 1 << ADDR_W,
    parameter string INIT_FILE = ""
) (
    input  logic              clk,
    input  logic [ADDR_W-1:0] addr,
    output logic [DATA_W-1:0] rdata
);
    logic [DATA_W-1:0] mem [0:DEPTH-1];
    initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    always_ff @(posedge clk) rdata <= mem[addr];
endmodule
