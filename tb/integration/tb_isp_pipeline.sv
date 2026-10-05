module tb_isp_pipeline;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;
    initial begin
        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        // TODO: load SRAM input, start pipeline, dump output pixels.
        repeat (100) @(posedge clk);
        $finish;
    end
    isp_pipeline_top dut (.clk(clk), .rst_n(rst_n));
endmodule
