module blc #(
    parameter int PIXEL_W = 12
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    input  logic [PIXEL_W-1:0] in_pixel,
    input  logic [PIXEL_W-1:0] black_level,
    output logic               out_valid,
    output logic [PIXEL_W-1:0] out_pixel
);
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0; out_pixel <= '0;
        end else begin
            out_valid <= in_valid;
            if (in_valid)
                out_pixel <= (in_pixel > black_level) ? (in_pixel - black_level) : '0;
        end
    end
endmodule
