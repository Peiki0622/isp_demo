`timescale 1ns/1ps
// 独立验证 SRAM 的寄存读时序；即使 reader 尚未实现，也不能放宽此测试。
module tb_sram_model;
    // 时钟与存储器接口：MEM_FILE 由运行命令指定，内容为地址斜坡。
    logic clk = 1'b0;
    logic [7:0] addr = '0;
    logic [15:0] rdata;
    integer previous_value;
    always #5 clk = ~clk;

    sram_model #(.ADDR_W(8), .DEPTH(256)) dut (
        .clk(clk), .addr(addr), .rdata(rdata)
    );

    // 每次在下降沿改变地址，先检查数据不随地址组合变化，再检查下一上升沿。
    initial begin
        @(posedge clk); #1ps;
        if (rdata !== 16'd0) $fatal(1, "SRAM_MODEL initial address 0 mismatch");
        previous_value = 0;
        for (int i = 0; i < 3; i++) begin
            @(negedge clk); addr = 8'(i);
            #1ps;
            if (rdata !== 16'(previous_value))
                $fatal(1, "SRAM_MODEL asynchronous read detected at address %0d", i);
            @(posedge clk); #1ps;
            if (rdata !== 16'(i))
                $fatal(1, "SRAM_MODEL registered read mismatch at address %0d", i);
            previous_value = i;
        end
        // 同一周期两次改变地址，输出必须保持，且下一沿仅采样最终地址。
        @(negedge clk); addr = 7; #1ps;
        if (rdata !== 16'd2) $fatal(1, "SRAM_MODEL data changed before edge");
        addr = 1; #1ps;
        if (rdata !== 16'd2) $fatal(1, "SRAM_MODEL data changed before edge");
        @(posedge clk); #1ps;
        if (rdata !== 16'd1) $fatal(1, "SRAM_MODEL final sampled address mismatch");
        $display("[PASS] SRAM_MODEL");
        $finish;
    end

    // 独立 watchdog：任何等待无法完成都必须失败，不能靠外部肉眼判断。
    initial begin
        #1000;
        $fatal(1, "SRAM_MODEL_TIMEOUT");
    end
endmodule
