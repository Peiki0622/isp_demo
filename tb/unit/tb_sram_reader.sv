`timescale 1ns/1ps
// 自检查 reader 回归：全部期望来自外部尺寸及像素序号，不访问 DUT 内部状态。
module tb_sram_reader;
    // 控制模块：8 位地址让 16x16 恰好占满容量，便于检查末地址与越界。
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic start = 1'b0;
    logic [15:0] image_width = '0, image_height = '0;
    logic busy;
    // SRAM 模块：地址斜坡数据在运行时通过 MEM_FILE 加载。
    logic [7:0] sram_addr;
    logic [15:0] sram_rdata;
    // 流模块：有效数据、坐标和行/帧标志全部需要逐周期检查。
    logic pixel_valid, sof, eol, frame_done;
    logic [11:0] pixel_data;
    logic [15:0] pixel_x, pixel_y;
    string selected_case, dump_dir;
    integer sampled_addr;
    always #5 clk = ~clk;

    sram_model #(.ADDR_W(8), .DEPTH(256)) memory (
        .clk(clk), .addr(sram_addr), .rdata(sram_rdata)
    );
    sram_reader #(.ADDR_W(8)) dut (
        // 时钟与帧控制。
        .clk(clk), .rst_n(rst_n), .start(start),
        .image_width(image_width), .image_height(image_height), .busy(busy),
        // SRAM 接口。
        .sram_addr(sram_addr), .sram_rdata(sram_rdata),
        // RAW 像素流接口。
        .pixel_valid(pixel_valid), .pixel_data(pixel_data),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .sof(sof), .eol(eol), .frame_done(frame_done)
    );

    // 上升沿先记录 SRAM 实际采样的旧地址，NBA 后检查本周期输出。
    task automatic tick;
        @(posedge clk);
        sampled_addr = sram_addr;
        #1ps;
    endtask

    // 使用 case inequality 让 X/Z 也失败；复位还要求载荷、坐标和地址为零。
    task automatic check_quiet(input bit reset_values);
        if ({busy, pixel_valid, sof, eol, frame_done} !== 5'b00000)
            $fatal(1, "SRAM_READER unexpected activity in idle/reset");
        if (reset_values && ({sram_addr, pixel_data, pixel_x, pixel_y} !== '0))
            $fatal(1, "SRAM_READER reset payload/address not cleared");
    endtask

    task automatic check_pixel(input int index, input int width, input int height);
        if (pixel_data !== 12'(index % 4096) ||
            pixel_x !== 16'(index % width) || pixel_y !== 16'(index / width))
            $fatal(1, "SRAM_READER pixel %0d expected=%0d xy=(%0d,%0d), actual=%h xy=(%0d,%0d)",
                   index, index % 4096, index % width, index / width,
                   pixel_data, pixel_x, pixel_y);
        if (sof !== (index == 0) || eol !== ((index % width) == width - 1) ||
            frame_done !== (index == width * height - 1))
            $fatal(1, "SRAM_READER flags mismatch at pixel %0d", index);
    endtask

    // mode: 0 普通脉冲，1 半帧处再次脉冲，2 持续高电平，3 帧中改变尺寸，
    // 4 半帧处再次拉高并保持到帧完成后，验证 busy 期间的边沿不会延后重启。
    // 周期数由契约固定为 C0..C(N+2)，没有根据 DUT 输出动态延迟期望数据。
    task automatic run_frame(input int width, input int height,
                             input int mode, input string dump_name);
        int total, count, sof_count, eol_count, done_count, fd;
        string io_error;
        total = width * height;
        count = 0; sof_count = 0; eol_count = 0; done_count = 0; fd = 0;
        if (dump_name != "") begin
            fd = $fopen({dump_dir, "/", dump_name}, "w");
            if (fd == 0) $fatal(1, "SRAM_READER cannot create dump %s", dump_name);
        end
        @(negedge clk);
        image_width = 16'(width); image_height = 16'(height); start = 1;
        tick(); // C0 接受启动，绝不能立刻把旧 SRAM 返回值输出为有效像素。
        if (busy !== 1'b1 || {pixel_valid, sof, eol, frame_done} !== 4'b0000)
            $fatal(1, "SRAM_READER bad accepted-start timing");

        for (int cycle = 1; cycle <= total + 2; cycle++) begin
            @(negedge clk);
            if (mode != 2)
                start = (mode == 1 && cycle == total / 2) ||
                        (mode == 4 && cycle >= total / 2);
            if (mode == 3 && cycle == 3) begin
                image_width = 0; image_height = 65535;
            end
            tick();
            if (cycle <= total && sampled_addr !== cycle - 1)
                $fatal(1, "SRAM_READER request %0d actual address=%0d", cycle-1, sampled_addr);
            if (busy !== (cycle <= total + 1))
                $fatal(1, "SRAM_READER busy mismatch at C%0d", cycle);
            if (pixel_valid !== (cycle >= 2 && cycle <= total + 1))
                $fatal(1, "SRAM_READER valid/bubble mismatch at C%0d", cycle);
            if (pixel_valid) begin
                check_pixel(count, width, height);
                sof_count += int'(sof); eol_count += int'(eol); done_count += int'(frame_done);
                count++;
                if (fd != 0) $fwrite(fd, "%04h\n", {4'b0, pixel_data});
            end else if ({sof, eol, frame_done} !== 3'b000) begin
                $fatal(1, "SRAM_READER flags asserted without valid");
            end
        end
        if (count != total || sof_count != 1 || eol_count != height || done_count != 1)
            $fatal(1, "SRAM_READER count mismatch pixels=%0d sof=%0d eol=%0d done=%0d",
                   count, sof_count, eol_count, done_count);
        if (fd != 0) begin
            $fflush(fd);
            if ($ferror(fd, io_error) != 0) $fatal(1, "SRAM_READER dump write error: %s", io_error);
            $fclose(fd);
        end
        // 额外空闲周期检查第 N+1 个像素和持续 start 意外重启，之后释放 start。
        repeat (3) begin @(negedge clk); tick(); check_quiet(0); end
        @(negedge clk); start = 0; tick(); check_quiet(0);
        $display("[CASE] reader %0dx%0d mode=%0d pixels=%0d PASS", width, height, mode, count);
    endtask

    // 零尺寸即使保持 start 数周期也不允许开始；释放后可接下一合法帧。
    task automatic invalid_dimensions(input int width, input int height);
        @(negedge clk); image_width = 16'(width); image_height = 16'(height); start = 1;
        repeat (4) begin tick(); check_quiet(0); @(negedge clk); end
        start = 0; tick(); check_quiet(0);
        $display("[CASE] reader zero dimension %0dx%0d PASS", width, height);
    endtask

    // 帧中复位：先验证已有像素，再复位清除 pending，避免旧返回数据泄漏。
    task automatic reset_midframe;
        @(negedge clk); image_width = 16; image_height = 16; start = 1;
        tick();
        for (int cycle = 1; cycle <= 6; cycle++) begin
            @(negedge clk); start = 0; tick();
            if (sampled_addr !== cycle - 1 || busy !== 1'b1 ||
                pixel_valid !== (cycle >= 2))
                $fatal(1, "SRAM_READER before-reset timing mismatch");
            if (cycle >= 2) check_pixel(cycle - 2, 16, 16);
        end
        @(negedge clk); rst_n = 0;
        repeat (2) begin tick(); check_quiet(1); @(negedge clk); end
        rst_n = 1; tick(); check_quiet(0);
        run_frame(2, 2, 0, "");
        $display("[CASE] reader midframe reset and restart PASS");
    endtask

    initial begin
        selected_case = "regression";
        void'($value$plusargs("CASE=%s", selected_case));
        void'($value$plusargs("DUMP_DIR=%s", dump_dir));
        repeat (3) begin tick(); check_quiet(1); end
        @(negedge clk); rst_n = 1; tick(); check_quiet(0);

        // 隔离负例：容量诊断必须来自 DUT，若未报告则用不同标记判失败。
        if (selected_case == "overflow" || selected_case == "overflow_large") begin
            @(negedge clk);
            image_width = (selected_case == "overflow") ? 17 : 65535;
            image_height = (selected_case == "overflow") ? 16 : 65535;
            start = 1; tick();
            $fatal(1, "SRAM_READER_OVERFLOW_DIAGNOSTIC_MISSING");
        end else if (selected_case == "capacity_reject") begin
            // 此例仅在 +define+SYNTHESIS 编译的程序中运行，证明拒绝逻辑属于硬件。
            invalid_dimensions(17, 16);
            invalid_dimensions(65535, 65535);
            $display("[PASS] SRAM_READER_CAPACITY_REJECT");
        end else if (selected_case == "forced_failure") begin
            $fatal(1, "SRAM_READER_FORCED_FAILURE");
        end else if (selected_case == "regression") begin
            if (dump_dir == "") $fatal(1, "SRAM_READER DUMP_DIR required");
            run_frame(16, 16, 0, "frame_0.mem");
            run_frame(16, 16, 1, "frame_1.mem");
            run_frame(1, 1, 0, "");
            run_frame(2, 2, 0, "");
            run_frame(7, 1, 0, "");
            run_frame(1, 7, 0, "");
            run_frame(3, 5, 0, "");
            run_frame(4, 4, 2, "");
            run_frame(4, 4, 4, "");
            run_frame(16, 16, 3, "");
            invalid_dimensions(0, 16);
            invalid_dimensions(16, 0);
            invalid_dimensions(0, 0);
            reset_midframe();
            $display("[PASS] SRAM_READER");
        end else begin
            $fatal(1, "SRAM_READER unknown CASE=%s", selected_case);
        end
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "SRAM_READER_TIMEOUT");
    end
endmodule
