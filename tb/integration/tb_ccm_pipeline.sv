`timescale 1ns/1ps
// P5 公开 RGB 接口验收：精确尺寸相关周期，黄金来自原始 SRAM 经 Python BLC->AWB->Demosaic->CCM。
// 控制/复位回归和四图案两帧回归共享本平台，但不访问 DUT 内部状态。
module tb_ccm_pipeline;
    // 时钟、同步复位、帧尺寸和配置接口：下降沿驱动避免 NBA 竞态。
    logic clk = 0, rst_n = 0, start = 0;
    logic [15:0] image_width = 0, image_height = 0;
    logic [11:0] black_level = 0;
    logic [15:0] gain_r = 4096, gain_g = 4096, gain_b = 4096;
    // 两帧完整矩阵配置：整数plusargs与Python CLI共享同一组row-major编码。
    int matrices [0:1][0:2][0:2];
    logic signed [15:0] external_matrix [0:2][0:2];
    task automatic set_matrix(input int frame_index);
        for(int row=0;row<3;row++) for(int col=0;col<3;col++)
            external_matrix[row][col]=16'(matrices[frame_index][row][col]);
    endtask
    logic busy;
    always #5 clk = ~clk;

    // 同步 SRAM 接口：8 位地址让 16x16 恰好占满容量，便于验证边界。
    logic [7:0] sram_addr;
    logic [15:0] sram_rdata;
    int sampled_addr;

    // RGB 公开流接口：逐拍检查数据、坐标、全部标志和忙状态。
    logic pixel_valid, sof, eol, frame_done;
    logic [11:0] pixel_r, pixel_g, pixel_b;
    logic [15:0] pixel_x, pixel_y;

    // 独立黄金和文件接口：两帧配置不同，不共享同一个 expected 数组。
    logic [35:0] expected0 [0:255], expected1 [0:255];
    string golden0, golden1, dump_dir, selected_case;
    int black0 = 64, black1 = 128;
    int r0 = 6144, g0 = 4096, b0 = 8192, r1 = 4096, g1 = 5120, b1 = 2048;
    // 每次仿真使用该实际尺寸对应的 SRAM 输入和两份黄金，不使用大图前缀。
    int frame_width = 16, frame_height = 16;

    sram_model #(.ADDR_W(8), .DEPTH(256)) memory (
        .clk(clk), .addr(sram_addr), .rdata(sram_rdata)
    );
    isp_pipeline_top #(.ADDR_W(8), .MAX_WIDTH(16)) dut (
        // 时钟、帧控制和算法配置。
        .clk(clk), .rst_n(rst_n), .start(start), .image_width(image_width),
        .image_height(image_height), .black_level(black_level), .busy(busy),
        .gain_r(gain_r), .gain_g(gain_g), .gain_b(gain_b),
        // 新增九个signed CCM系数，行列固定对应RGB数学矩阵。
        .c00(external_matrix[0][0]),.c01(external_matrix[0][1]),.c02(external_matrix[0][2]),
        .c10(external_matrix[1][0]),.c11(external_matrix[1][1]),.c12(external_matrix[1][2]),
        .c20(external_matrix[2][0]),.c21(external_matrix[2][1]),.c22(external_matrix[2][2]),
        // 外部同步 SRAM 返回。
        .sram_addr(sram_addr), .sram_rdata(sram_rdata),
        // 完整 RAW->RGB 最终输出。
        .pixel_valid(pixel_valid), .pixel_r(pixel_r), .pixel_g(pixel_g), .pixel_b(pixel_b), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .sof(sof), .eol(eol), .frame_done(frame_done)
    );

    // 先记录 SRAM 在沿上采样的旧地址，再在 NBA 后检查本周期输出。
    task automatic tick;
        @(posedge clk); sampled_addr = sram_addr; #1ps;
    endtask

    task automatic check_idle;
        if ({busy, pixel_valid, sof, eol, frame_done} !== 5'b00000)
            $fatal(1, "CCM_PIPELINE unexpected idle activity");
    endtask

    // 明确验证文件可打开，防止 readmemh 警告被当作通过。
    task automatic require_file(input string filename);
        int fd;
        fd = $fopen(filename, "r");
        if (fd == 0) $fatal(1, "CCM_GOLDEN_FILE_ERROR: %s", filename);
        $fclose(fd);
    endtask

    // 数值期望由黄金文件提供，坐标/标志由外部尺寸和输出序号提供。
    // X/Z 使用 case inequality 显式拒绝，不能通过 DUT valid 调整期望时序。
    task automatic check_pixel(input int index, input int width, input int height,
                               input int frame_index);
        logic [35:0] wanted;
        wanted = (frame_index == 0) ? expected0[index] : expected1[index];
        if ((^wanted === 1'bx) || {pixel_r,pixel_g,pixel_b} !== wanted || pixel_x !== 16'(index % width) ||
            pixel_y !== 16'(index / width))
            $fatal(1, "CCM_PIPELINE frame=%0d index=%0d expected=%h actual=%h xy=(%0d,%0d)",
                   frame_index, index, wanted, {pixel_r,pixel_g,pixel_b}, pixel_x, pixel_y);
        if (sof !== (index == 0) || eol !== (index%width == width-1) ||
            frame_done !== (index == width*height-1))
            $fatal(1, "CCM_PIPELINE flag mismatch index=%0d", index);
    endtask

    // mode 8/9 CCM最后Stage1脉冲/保持，10/11最后P4输出脉冲/保持。
    // mode 0 普通脉冲，1 忙时脉冲，2 持续高电平，3 帧中改变尺寸，
    // 4 窗口 tail 脉冲，5 tail 拉高跨完成，6 末 RGB 沿脉冲，7 busy 解除沿脉冲。
    // 独立周期表：C1..CN 请求，RGB C(W+9)..C(N+W+8)，随后沿清 busy。
    task automatic run_frame(input int width, input int height, input int frame_index,
                             input int mode, input string dump_name = "");
        int total, first_cycle, last_cycle, count, sof_count, eol_count, done_count, fd, wanted_black, wanted_r, wanted_g, wanted_b;
        string io_error;
        total = width*height; first_cycle=width+9; last_cycle=total+width+8; count = 0; sof_count = 0; eol_count = 0; done_count = 0; fd = 0;
        wanted_black = (frame_index == 0) ? black0 : black1;
        wanted_r = (frame_index == 0) ? r0 : r1;
        wanted_g = (frame_index == 0) ? g0 : g1;
        wanted_b = (frame_index == 0) ? b0 : b1;
        if (dump_name != "") begin
            fd = $fopen({dump_dir, "/", dump_name}, "w");
            if (fd == 0) $fatal(1, "CCM_PIPELINE cannot create dump");
        end
        @(negedge clk);
        image_width = 16'(width); image_height = 16'(height); start = 1;
        // C0矩阵故意错误，CCM应该直到C(W+8)才采样，而不是随start锁存。
        for(int row=0;row<3;row++) for(int col=0;col<3;col++) external_matrix[row][col]=-32768;
        // 故意在 start 沿提供错误配置；C3 前才改成目标，证明不在 C0 锁存。
        black_level = 12'(4095-wanted_black);
        gain_r = 16'(65535-wanted_r); gain_g = 16'(65535-wanted_g);
        gain_b = 16'(65535-wanted_b); tick();
        if (busy !== 1'b1 || {pixel_valid, sof, eol, frame_done} !== 4'b0000)
            $fatal(1, "CCM_PIPELINE accepted-start mismatch");
        for (int cycle = 1; cycle <= last_cycle+1; cycle++) begin
            @(negedge clk);
            start = (mode == 2) || (mode == 1 && cycle == 2) ||
                    (mode == 4 && cycle == total+5) ||
                    (mode == 5 && cycle >= total+5) ||
                    (mode == 6 && cycle == last_cycle) ||
                    (mode == 8 && cycle == last_cycle-1) ||
                    (mode == 9 && cycle >= last_cycle-1) ||
                    (mode == 10 && cycle == last_cycle-2) ||
                    (mode == 11 && cycle >= last_cycle-2);
            if (mode == 7 && cycle == last_cycle+1) start=1;
            if (cycle == 3) black_level = 12'(wanted_black);
            if (cycle == 4) black_level = 12'(4095-wanted_black);
            // AWB 比 BLC 晚一拍采样：C4 前提供新增益，C5 起扰动三路配置。
            // 这既验证首像素，又证明 C0/C3 不会提前锁存 AWB 配置。
            if (cycle == 4) begin
                gain_r = 16'(wanted_r); gain_g = 16'(wanted_g); gain_b = 16'(wanted_b);
            end
            if (cycle >= 5) begin
                gain_r = 16'((cycle*997+65535-wanted_r)%65536);
                gain_g = 16'((cycle*619+65535-wanted_g)%65536);
                gain_b = 16'((cycle*337+65535-wanted_b)%65536);
            end
            // 前级首RGB出现在C(W+7)，CCM在下一沿C(W+8)消费并原子采样。
            // 随后每拍扰动全部九个外部端口，但当前帧黄金必须保持原矩阵。
            if (cycle==width+8) set_matrix(frame_index);
            if (cycle>=width+9) for(int row=0;row<3;row++) for(int col=0;col<3;col++)
                external_matrix[row][col]=16'(cycle*997+row*1237+col*619);
            if (mode == 3 && cycle == 2) begin
                image_width = 0; image_height = 65535;
            end
            tick();
            if (cycle <= total && sampled_addr !== cycle-1)
                $fatal(1, "CCM_PIPELINE SRAM address mismatch C%0d", cycle);
            if (busy !== (cycle <= last_cycle) ||
                pixel_valid !== (cycle >= first_cycle && cycle <= last_cycle))
                $fatal(1, "CCM_PIPELINE busy/valid mismatch C%0d", cycle);
            if (pixel_valid) begin
                check_pixel(count, width, height, frame_index);
                sof_count += int'(sof); eol_count += int'(eol); done_count += int'(frame_done);
                count++;
                if (fd != 0) $fwrite(fd, "%09h\n", {pixel_r,pixel_g,pixel_b});
            end else if ({sof, eol, frame_done} !== 3'b000)
                $fatal(1, "CCM_PIPELINE invalid-cycle flags");
        end
        if (count != total || sof_count != 1 || eol_count != height || done_count != 1)
            $fatal(1, "CCM_PIPELINE frame counts incorrect");
        if (fd != 0) begin
            $fflush(fd);
            if ($ferror(fd, io_error) != 0) $fatal(1, "CCM_PIPELINE dump write error: %s", io_error);
            $fclose(fd);
        end
        // 忙时保持的 start 不可在 busy 下降后变成新启动；多检查三拍排除尾像素。
        repeat (3) begin
            @(negedge clk); start = (mode == 2 || mode == 5 || mode == 9 || mode == 11); tick(); check_idle();
        end
        @(negedge clk); start = 0; tick(); check_idle();
        $display("[CASE] RGB top %0dx%0d frame=%0d mode=%0d pixels=%0d PASS",
                 width, height, frame_index, mode, count);
    endtask

    // 零尺寸和 SYNTHESIS 容量拒绝复用此任务；保持高电平时改为合法尺寸
    // 也不能启动，必须先释放，再产生新的上升沿。
    task automatic rejected_start(input int width, input int height);
        @(negedge clk); image_width = 16'(width); image_height = 16'(height); start = 1;
        repeat (3) begin tick(); check_idle(); @(negedge clk); end
        image_width = 16; image_height = 16;
        repeat (3) begin tick(); check_idle(); @(negedge clk); end
        start = 0; tick(); check_idle();
        $display("[CASE] RGB top rejected %0dx%0d PASS", width, height);
    endtask

    // 在指定周期同步复位，清除 Reader pending、RAW 配置、窗口和 RGB 寄存器。
    // 分别覆盖预热、有效 RGB、tail 及最后 RGB，重启不得泄漏旧帧。
    task automatic reset_midframe(input int stop_cycle);
        @(negedge clk); image_width = 16'(frame_width); image_height = 16'(frame_height); start = 1; set_matrix(0);
        black_level = 12'(black0); gain_r = 16'(r0); gain_g = 16'(g0); gain_b = 16'(b0); tick();
        for (int cycle = 1; cycle <= stop_cycle; cycle++) begin
            @(negedge clk); start = 0; tick();
            if (busy !== 1'b1 || pixel_valid !== (cycle >= frame_width+9))
                $fatal(1, "CCM_PIPELINE before-reset timing mismatch");
            if (cycle >= frame_width+9) check_pixel(cycle-frame_width-9, frame_width, frame_height, 0);
        end
        @(negedge clk); rst_n = 0;
        repeat (2) begin
            tick(); check_idle();
            if ({sram_addr, pixel_r, pixel_g, pixel_b, pixel_x, pixel_y} !== '0)
                $fatal(1, "CCM_PIPELINE reset payload/address mismatch");
            @(negedge clk);
        end
        rst_n = 1;
        repeat (5) begin tick(); check_idle(); @(negedge clk); end
        run_frame(frame_width, frame_height, 1, 0);
        $display("[CASE] RGB top reset and restart PASS");
    endtask

    initial begin
        // 未提供矩阵参数时identity；脚本给每帧全部九个有符号整数参数。
        for(int frame=0;frame<2;frame++) for(int row=0;row<3;row++) for(int col=0;col<3;col++)
            matrices[frame][row][col]=(row==col)?4096:0;
        for(int frame=0;frame<2;frame++) for(int row=0;row<3;row++) for(int col=0;col<3;col++)
            void'($value$plusargs($sformatf("M%0d_%0d=%%d",frame,row*3+col),matrices[frame][row][col]));
        set_matrix(0);
        selected_case = "regression";
        void'($value$plusargs("CASE=%s", selected_case));
        void'($value$plusargs("BLACK0=%d", black0));
        void'($value$plusargs("BLACK1=%d", black1));
        void'($value$plusargs("R0=%d", r0)); void'($value$plusargs("G0=%d", g0));
        void'($value$plusargs("B0=%d", b0)); void'($value$plusargs("R1=%d", r1));
        void'($value$plusargs("G1=%d", g1)); void'($value$plusargs("B1=%d", b1));
        void'($value$plusargs("WIDTH=%d", frame_width));
        void'($value$plusargs("HEIGHT=%d", frame_height));
        if (frame_width < 2 || frame_height < 2 || frame_width > 16 || frame_width*frame_height > 256)
            $fatal(1, "CCM_PIPELINE invalid test dimensions");
        repeat (3) begin tick(); check_idle(); end
        @(negedge clk); rst_n = 1; tick(); check_idle();
        if (selected_case == "forced_failure") $fatal(1, "CCM_PIPELINE_FORCED_FAILURE");
        if (selected_case == "overflow" || selected_case == "overflow_large") begin
            @(negedge clk); start = 1;
            image_width = (selected_case == "overflow") ? 16 : 2;
            image_height = (selected_case == "overflow") ? 17 : 65535;
            tick(); $fatal(1, "CCM_PIPELINE_OVERFLOW_DIAGNOSTIC_MISSING");
        end
        if (!$value$plusargs("GOLDEN0=%s", golden0) ||
            !$value$plusargs("GOLDEN1=%s", golden1))
            $fatal(1, "CCM_PIPELINE golden paths required");
        require_file(golden0); require_file(golden1);
        $readmemh(golden0, expected0, 0, frame_width*frame_height-1);
        $readmemh(golden1, expected1, 0, frame_width*frame_height-1);

        if (selected_case == "regression" || selected_case == "controls") begin
            if (!$value$plusargs("DUMP_DIR=%s", dump_dir)) $fatal(1,"CCM_PIPELINE dump directory required");
        end
        if (selected_case == "regression") begin
            run_frame(frame_width, frame_height, 0, 5, "frame_0.mem");
            run_frame(frame_width, frame_height, 1, 3, "frame_1.mem");
        end else if (selected_case == "controls") begin
            for (int mode = 0; mode <= 11; mode++)
                run_frame(frame_width, frame_height, mode%2, mode);
            // 两帧不同配置紧接执行，确保完成后新的空闲上升沿仍可接受。
            run_frame(frame_width, frame_height, 0, 0, "frame_0.mem");
            run_frame(frame_width, frame_height, 1, 0, "frame_1.mem");
            rejected_start(0, 16); rejected_start(16, 0); rejected_start(0, 0);
            rejected_start(1, 16); rejected_start(16, 1); rejected_start(17, 2);
            reset_midframe(2); // 首 RGB 前同步中止。
            reset_midframe(frame_width+10); // 已输出多个 RGB 后中止。
            reset_midframe(frame_width*frame_height+5); // 窗口 tail 中止。
            reset_midframe(frame_width*frame_height+frame_width+7); // CCM最后Stage1乘积占用。
            reset_midframe(frame_width*frame_height+frame_width+8); // 最后 RGB 周期中止。
        end else if (selected_case == "capacity_reject") begin
            rejected_start(16, 17); rejected_start(2, 65535);
            run_frame(frame_width, frame_height, 1, 0);
        end else $fatal(1, "CCM_PIPELINE unknown case %s", selected_case);
        $display("[PASS] CCM_PIPELINE");
        $finish;
    end

    // 所有模式共享固定 watchdog；协议卡住或额外启动必须失败。
    initial begin
        #250000;
        $fatal(1, "CCM_PIPELINE_TIMEOUT");
    end
endmodule
