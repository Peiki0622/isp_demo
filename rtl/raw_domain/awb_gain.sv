module awb_gain #(
    parameter int PIXEL_W = 12,
    parameter int GAIN_W  = 16,
    parameter int FRAC_W  = 8
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                in_valid,
    input  logic [PIXEL_W-1:0]  in_pixel,
    input  logic [1:0]          bayer_phase,
    input  logic [GAIN_W-1:0]   gain_r,
    input  logic [GAIN_W-1:0]   gain_g,
    input  logic [GAIN_W-1:0]   gain_b,
    output logic                out_valid,
    output logic [PIXEL_W-1:0]  out_pixel
);
    // TODO: RGGB phase select, widened multiply, rounding, saturation.
    always_ff @(posedge clk) begin
        if (!rst_n) begin out_valid <= 1'b0; out_pixel <= '0; end
        else begin out_valid <= in_valid; out_pixel <= in_pixel; end
    end
endmodule
