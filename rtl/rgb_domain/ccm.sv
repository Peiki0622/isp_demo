module ccm #(
    parameter int RGB_W  = 12,
    parameter int COEF_W = 16
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                in_valid,
    input  logic [RGB_W-1:0]    in_r,
    input  logic [RGB_W-1:0]    in_g,
    input  logic [RGB_W-1:0]    in_b,
    input  logic signed [COEF_W-1:0] c00, c01, c02,
    input  logic signed [COEF_W-1:0] c10, c11, c12,
    input  logic signed [COEF_W-1:0] c20, c21, c22,
    output logic                out_valid,
    output logic [RGB_W-1:0]    out_r,
    output logic [RGB_W-1:0]    out_g,
    output logic [RGB_W-1:0]    out_b
);
    // TODO: freeze coefficient fixed-point format and add pipelined MACs.
    always_ff @(posedge clk) begin
        if (!rst_n) begin out_valid <= 1'b0; out_r <= '0; out_g <= '0; out_b <= '0; end
        else begin out_valid <= in_valid; out_r <= in_r; out_g <= in_g; out_b <= in_b; end
    end
endmodule
