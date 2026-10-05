module sram_reader #(
    parameter int ADDR_W  = 20,
    parameter int PIXEL_W = 12
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic [15:0]        image_width,
    input  logic [15:0]        image_height,
    output logic [ADDR_W-1:0]  sram_addr,
    input  logic [15:0]        sram_rdata,
    output logic               pixel_valid,
    output logic [PIXEL_W-1:0] pixel_data,
    output logic               frame_done
);
    // TODO: complete address sequencing after the SRAM timing model is fixed.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sram_addr <= '0; pixel_valid <= 1'b0; pixel_data <= '0; frame_done <= 1'b0;
        end else begin
            pixel_valid <= 1'b0; frame_done <= 1'b0;
            if (start) begin
                pixel_data <= sram_rdata[PIXEL_W-1:0];
                pixel_valid <= 1'b1;
            end
        end
    end
endmodule
