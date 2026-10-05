module edge_enhance #(
    parameter int W = 12
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         enable,
    input  logic         in_valid,
    input  logic [W-1:0] in_y,
    output logic         out_valid,
    output logic [W-1:0] out_y
);
    // Phase-1 bypass. Planned baseline: luminance-domain unsharp mask.
    always_ff @(posedge clk) begin
        if (!rst_n) begin out_valid <= 1'b0; out_y <= '0; end
        else begin out_valid <= in_valid; out_y <= in_y; end
    end
endmodule
