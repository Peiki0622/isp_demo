module hue #(
    parameter int W = 12
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         enable,
    input  logic         in_valid,
    input  logic [W-1:0] in_y,
    input  logic [W-1:0] in_cb,
    input  logic [W-1:0] in_cr,
    output logic         out_valid,
    output logic [W-1:0] out_y,
    output logic [W-1:0] out_cb,
    output logic [W-1:0] out_cr
);
    // Phase-1 bypass. Later implementation will rotate the chroma vector.
    always_ff @(posedge clk) begin
        if (!rst_n) begin out_valid <= 1'b0; out_y <= '0; out_cb <= '0; out_cr <= '0; end
        else begin out_valid <= in_valid; out_y <= in_y; out_cb <= in_cb; out_cr <= in_cr; end
    end
endmodule
