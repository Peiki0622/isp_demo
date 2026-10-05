module rgb2ycbcr #(
    parameter int RGB_W = 12,
    parameter int YUV_W = 12
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             in_valid,
    input  logic [RGB_W-1:0] in_r,
    input  logic [RGB_W-1:0] in_g,
    input  logic [RGB_W-1:0] in_b,
    output logic             out_valid,
    output logic [YUV_W-1:0] out_y,
    output logic [YUV_W-1:0] out_cb,
    output logic [YUV_W-1:0] out_cr
);
    // TODO: freeze the digital YCbCr standard and coefficient scaling.
    always_ff @(posedge clk) begin
        if (!rst_n) begin out_valid <= 1'b0; out_y <= '0; out_cb <= '0; out_cr <= '0; end
        else out_valid <= 1'b0;
    end
endmodule
