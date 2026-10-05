module sram_model #(
    // 仿真容量与字宽；测试使用小容量，实际 reader 默认仍为 20 位地址。
    parameter int ADDR_W = 20,
    parameter int DATA_W = 16,
    parameter int DEPTH  = 1 << ADDR_W,
    parameter string INIT_FILE = ""
) (
    // 时钟接口：上升沿采样地址，NBA 区更新返回值，不能改为异步读。
    input  logic              clk,
    // SRAM 读接口：每周期持续读取；有效请求窗口由外部 reader 定义。
    input  logic [ADDR_W-1:0] addr,
    output logic [DATA_W-1:0] rdata
);
    logic [DATA_W-1:0] mem [0:DEPTH-1];
    string resolved_file;
    integer init_fd;

    // 文件接口：运行时绝对路径优先于参数，允许在隔离目录内运行同一仿真程序。
    // 先验证文件能打开；否则 readmemh 警告可能留下 X 而被误当成正常运行。
    initial begin
        resolved_file = INIT_FILE;
        void'($value$plusargs("MEM_FILE=%s", resolved_file));
        if (resolved_file != "") begin
            init_fd = $fopen(resolved_file, "r");
            if (init_fd == 0)
                $fatal(1, "SRAM_INIT_FILE_ERROR: cannot open %s", resolved_file);
            $fclose(init_fd);
            $readmemh(resolved_file, mem);
        end
    end

    // 同步读寄存器：本沿得到的 rdata 只能在下一沿被 reader 的寄存器消费。
    always_ff @(posedge clk) rdata <= mem[addr];
endmodule
