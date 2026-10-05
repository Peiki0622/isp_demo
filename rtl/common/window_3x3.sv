module window_3x3 #(
    parameter int PIXEL_W = 12,
    parameter int MAX_WIDTH = 2048
) (
    input logic clk,
    input logic rst_n,
    input logic in_valid,
    input logic [PIXEL_W-1:0] in_pixel,
    input logic [15:0] image_width
);
    // TODO: infer or instantiate line memories and emit a valid 3x3 neighborhood.
endmodule
