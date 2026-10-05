`timescale 1ns/1ps
// 从顶层公开接口验证两帧完整 RAW 流，不探查顶层或 reader 的内部状态。
module tb_isp_pipeline;
    // 控制模块：使用顶层默认 20 位地址和 RAW12 配置。
    logic clk = 1'b0, rst_n = 1'b0, start = 1'b0;
    logic [15:0] image_width = 16, image_height = 16;
    logic busy;
    // SRAM 模块：模型容量缩为 256 字，地址总线保留真实默认宽度。
    logic [19:0] sram_addr;
    logic [15:0] sram_rdata;
    logic [15:0] expected [0:255];
    // 流模块与文件接口：两个帧文件独立保存，每个文件必须恰好 256 字。
    logic pixel_valid, sof, eol, frame_done;
    logic [11:0] pixel_data;
    logic [15:0] pixel_x, pixel_y;
    string mem_file, dump_dir, io_error;
    integer fd, sampled_addr, count, sof_count, eol_count, done_count;
    always #5 clk = ~clk;

    sram_model #(.ADDR_W(20), .DEPTH(256)) memory (
        .clk(clk), .addr(sram_addr), .rdata(sram_rdata)
    );
    isp_pipeline_top dut (
        // 时钟/帧控制。
        .clk(clk), .rst_n(rst_n), .start(start),
        .image_width(image_width), .image_height(image_height), .busy(busy),
        // 外部同步 SRAM。
        .sram_addr(sram_addr), .sram_rdata(sram_rdata),
        // 顶层 RAW 流。
        .pixel_valid(pixel_valid), .pixel_data(pixel_data),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .sof(sof), .eol(eol), .frame_done(frame_done)
    );

    task automatic tick;
        @(posedge clk);
        sampled_addr = sram_addr;
        #1ps;
    endtask

    task automatic check_idle;
        if ({busy, pixel_valid, sof, eol, frame_done} !== 5'b00000)
            $fatal(1, "ISP_PIPELINE unexpected idle activity");
    endtask

    initial begin
        // 独立加载文件黄金值，按外部输出序号索引，可同样验证其余三种图案。
        // MEM_FILE/DUMP_DIR 必须是明确路径，不能把文件写到任意仿真当前目录。
        if (!$value$plusargs("MEM_FILE=%s", mem_file) ||
            !$value$plusargs("DUMP_DIR=%s", dump_dir))
            $fatal(1, "ISP_PIPELINE MEM_FILE and DUMP_DIR required");
        $readmemh(mem_file, expected);
        repeat (3) begin tick(); check_idle(); end
        @(negedge clk); rst_n = 1; tick(); check_idle();

        for (int frame = 0; frame < 2; frame++) begin
            fd = $fopen($sformatf("%s/frame_%0d.mem", dump_dir, frame), "w");
            if (fd == 0) $fatal(1, "ISP_PIPELINE cannot create frame dump");
            count = 0; sof_count = 0; eol_count = 0; done_count = 0;
            @(negedge clk); start = 1; tick();
            if (busy !== 1'b1 || {pixel_valid, sof, eol, frame_done} !== 4'b0000)
                $fatal(1, "ISP_PIPELINE accepted-start mismatch");

            // 固定契约：C1..C256 请求，C2..C257 输出，C258 清除 busy。
            for (int cycle = 1; cycle <= 258; cycle++) begin
                @(negedge clk); start = 0; tick();
                if (cycle <= 256 && sampled_addr !== cycle - 1)
                    $fatal(1, "ISP_PIPELINE address mismatch at C%0d", cycle);
                if (busy !== (cycle <= 257) ||
                    pixel_valid !== (cycle >= 2 && cycle <= 257))
                    $fatal(1, "ISP_PIPELINE busy/valid mismatch at C%0d", cycle);
                if (pixel_valid) begin
                    if ((^pixel_data === 1'bx) || expected[count][15:12] !== 4'b0000 ||
                        pixel_data !== expected[count][11:0] ||
                        pixel_x !== 16'(count % 16) || pixel_y !== 16'(count / 16))
                        $fatal(1, "ISP_PIPELINE frame=%0d pixel=%0d expected=%h actual=%h xy=(%0d,%0d)",
                               frame, count, expected[count], pixel_data, pixel_x, pixel_y);
                    if (sof !== (count == 0) || eol !== (count % 16 == 15) ||
                        frame_done !== (count == 255))
                        $fatal(1, "ISP_PIPELINE frame=%0d flag mismatch at pixel=%0d", frame, count);
                    sof_count += int'(sof); eol_count += int'(eol); done_count += int'(frame_done);
                    count++;
                    $fwrite(fd, "%04h\n", {4'b0, pixel_data});
                end else if ({sof, eol, frame_done} !== 3'b000) begin
                    $fatal(1, "ISP_PIPELINE flags without valid");
                end
            end
            if (count != 256 || sof_count != 1 || eol_count != 16 || done_count != 1)
                $fatal(1, "ISP_PIPELINE frame counts incorrect");
            $fflush(fd);
            if ($ferror(fd, io_error) != 0) $fatal(1, "ISP_PIPELINE dump write error: %s", io_error);
            $fclose(fd);
            repeat (3) begin @(negedge clk); tick(); check_idle(); end
            $display("[CASE] top frame=%0d pixels=%0d PASS", frame, count);
        end
        $display("[PASS] ISP_PIPELINE");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "ISP_PIPELINE_TIMEOUT");
    end
endmodule
