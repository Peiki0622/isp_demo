`timescale 1ns/1ps
// 独立 BLC 验收：期望只由外部激励和有符号整数公式推导。
// 下降沿驱动、上升沿前检查寄存保持、NBA 后检查一次寄存后的精确结果。
module tb_blc;
    // 时钟/同步复位接口：测试中也检查复位在采样沿前不能改变输出。
    logic clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    // 输入载荷及帧标志接口：坐标有意变化，避免恒定零掩盖对齐问题。
    logic in_valid = 0, in_sof = 0, in_eol = 0, in_frame_done = 0;
    logic [11:0] in_pixel = 0, black_level = 0;
    logic [15:0] in_x = 0, in_y = 0;

    // 输出载荷及帧标志接口：所有端口逐拍核对，包含无效拍和复位。
    logic out_valid, out_sof, out_eol, out_frame_done;
    logic [11:0] out_pixel;
    logic [15:0] out_x, out_y;

    // 独立参考状态：保存帧首配置和上一拍期望，不读取 DUT 内部寄存器。
    int reference_black = 0, reference_pixel = 0, reference_x = 0, reference_y = 0;
    bit reference_valid = 0, reference_sof = 0, reference_eol = 0, reference_done = 0;
    int checked_cycles = 0;
    string selected_case;
    int offsets [0:3] = '{0, 64, 1024, 4095};

    blc dut (
        // 时钟及同步低有效复位。
        .clk(clk), .rst_n(rst_n),
        // 外部输入流及按帧配置。
        .in_valid(in_valid), .in_pixel(in_pixel), .in_x(in_x), .in_y(in_y),
        .in_sof(in_sof), .in_eol(in_eol), .in_frame_done(in_frame_done),
        .black_level(black_level),
        // 完整一级寄存输出。
        .out_valid(out_valid), .out_pixel(out_pixel), .out_x(out_x), .out_y(out_y),
        .out_sof(out_sof), .out_eol(out_eol), .out_frame_done(out_frame_done)
    );

    // case inequality 同时拒绝 X/Z。无效拍也核对载荷保持，防止组合旁路。
    task automatic check_output;
        if (out_valid !== reference_valid || out_pixel !== 12'(reference_pixel) ||
            out_x !== 16'(reference_x) || out_y !== 16'(reference_y) ||
            out_sof !== reference_sof || out_eol !== reference_eol ||
            out_frame_done !== reference_done)
            $fatal(1, "BLC_UNIT cycle=%0d expected v=%0b pixel=%0d xy=(%0d,%0d) flags=%0b%0b%0b; actual v=%b pixel=%h xy=(%0d,%0d) flags=%b%b%b",
                   checked_cycles, reference_valid, reference_pixel, reference_x, reference_y,
                   reference_sof, reference_eol, reference_done,
                   out_valid, out_pixel, out_x, out_y, out_sof, out_eol, out_frame_done);
    endtask

    // 一次刺激对应一个采样周期。先验证未到寄存沿时输出不跟随输入，
    // 再按外部 stimulus 更新参考并核对 NBA 后输出，不能用 DUT valid 移动期望。
    task automatic drive(input bit valid_i, input int pixel_i, input int offset_i,
                         input bit sof_i, input bit eol_i, input bit done_i,
                         input int x_i = 0, input int y_i = 0, input bit reset_n = 1);
        int difference;
        @(negedge clk);
        rst_n = reset_n;
        in_valid = valid_i; in_pixel = 12'(pixel_i); black_level = 12'(offset_i);
        in_sof = sof_i; in_eol = eol_i; in_frame_done = done_i;
        in_x = 16'(x_i); in_y = 16'(y_i);
        #1ps; check_output();
        @(posedge clk);
        if (!reset_n) begin
            reference_black = 0; reference_pixel = 0;
            reference_x = 0; reference_y = 0;
            reference_valid = 0; reference_sof = 0;
            reference_eol = 0; reference_done = 0;
        end else begin
            if (valid_i && sof_i) reference_black = offset_i;
            reference_valid = valid_i;
            reference_sof = valid_i && sof_i;
            reference_eol = valid_i && eol_i;
            reference_done = valid_i && done_i;
            if (valid_i) begin
                // 有符号减法后测试负值，与 RTL 的无符号先比较路径独立。
                difference = pixel_i - reference_black;
                reference_pixel = (difference < 0) ? 0 : difference;
                reference_x = x_i; reference_y = y_i;
            end
        end
        #1ps; check_output(); checked_cycles++;
    endtask

    initial begin
        selected_case = "regression";
        void'($value$plusargs("CASE=%s", selected_case));
        drive(0, 0, 0, 0, 0, 0, 0, 0, 0);
        drive(0, 0, 0, 0, 0, 0);
        if (selected_case == "forced_failure")
            $fatal(1, "BLC_UNIT_FORCED_FAILURE");
        if (selected_case != "regression")
            $fatal(1, "BLC_UNIT_UNKNOWN_CASE");

        // 无效 sof 不能锁存 4095；复位配置为零，下一有效非 sof 像素应恒等。
        drive(0, 123, 4095, 1, 1, 1, 99, 88);
        drive(1, 4095, 4095, 0, 0, 0, 7, 9);
        for (int k = 0; k < 4; k++) begin
            // 非零帧首能暴露上一帧配置错误；后续每拍改变外部偏置。
            drive(1, 4095, offsets[k], 1, 0, 0, 0, k);
            drive(1, 0, 4095-offsets[k], 0, 0, 0, 1, k);
            if (offsets[k] > 0)
                drive(1, offsets[k]-1, 0, 0, 0, 0, 2, k);
            drive(0, 4095, 4095, 1, 1, 1, 65535, 65535);
            drive(1, offsets[k], 1, 0, 1, 0, 3, k);
            if (offsets[k] < 4095)
                drive(1, offsets[k]+1, 4095, 0, 0, 0, 4, k);
            drive(1, 4095, 0, 0, 1, 1, 5, k);
            $display("[CASE] BLC threshold/holes offset=%0d PASS", offsets[k]);
        end

        // 连续帧首且不插空洞：1x1 同时具有全部标志，配置每帧改变。
        drive(1, 1024, 1024, 1, 1, 1, 0, 0);
        drive(1, 1024, 64, 1, 1, 1, 0, 0);
        drive(1, 4095, 0, 1, 1, 1, 0, 0);

        // 确定性长序列混合有效空洞、帧内配置变化和行/帧标志。
        // 坐标和像素通过独立整数生成，覆盖 RAW12 全区间，保持可复现。
        for (int frame = 0; frame < 8; frame++) begin
            for (int index = 0; index < 64; index++) begin
                if (index % 7 == 3)
                    drive(0, index, 4095, 1, 1, 1, index, frame);
                drive(1, (frame*313 + index*197) % 4096,
                      (index == 0) ? offsets[frame%4] : (index*61)%4096,
                      index == 0, index%8 == 7, index == 63, index%8, index/8);
            end
        end

        // 输出有效时施加同步复位，必须在采样沿丢弃当前输入和旧帧配置。
        drive(1, 4095, 1024, 1, 0, 0, 3, 4);
        drive(1, 2048, 4095, 0, 1, 1, 9, 8, 0);
        drive(0, 0, 0, 0, 0, 0);
        drive(1, 1024, 0, 0, 0, 0, 0, 0);
        drive(1, 1024, 64, 1, 1, 1, 0, 0);
        repeat (3) drive(0, 4095, 4095, 1, 1, 1);
        $display("[CASE] BLC checked cycles=%0d PASS", checked_cycles);
        $display("[PASS] BLC_UNIT");
        $finish;
    end

    // watchdog 防止时钟/等待协议错误导致仿真挂住或无声结束。
    initial begin
        #20000;
        $fatal(1, "BLC_UNIT_TIMEOUT");
    end
endmodule
