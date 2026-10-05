module demosaic #(
    parameter int RAW_W = 12,
    parameter int RGB_W = 12
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             in_valid,
    input  logic [RAW_W-1:0] in_pixel,
    input  logic [15:0]      image_width,
    output logic             out_valid,
    output logic [RGB_W-1:0] out_r,
    output logic [RGB_W-1:0] out_g,
    output logic [RGB_W-1:0] out_b
);
    // TODO: freeze the baseline interpolation algorithm and add line buffers.
    always_ff @(posedge clk) begin
        if (!rst_n) begin out_valid <= 1'b0; out_r <= '0; out_g <= '0; out_b <= '0; end
        else out_valid <= 1'b0;
    end
endmodule
