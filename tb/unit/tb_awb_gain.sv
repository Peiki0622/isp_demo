`timescale 1ns/1ps
// AWB 一级流水自检查：仅使用外部激励及独立整数商/余数参考，不访问 DUT 内部。
module tb_awb_gain;
    // 时钟/同步复位接口：下降沿改变输入，上升沿 NBA 后检查输出。
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // 输入载荷、帧标志与配置接口：坐标与三增益分别变化以暴露错拍和错误选色。
    logic in_valid = 0, in_sof = 0, in_eol = 0, in_frame_done = 0;
    logic [11:0] in_pixel = 0;
    logic [15:0] in_x = 0, in_y = 0;
    logic [15:0] gain_r = 4096, gain_g = 4096, gain_b = 4096;

    // 输出接口：逐拍核对所有端口，无效拍仍检查 payload 保持及标志为零。
    logic out_valid, out_sof, out_eol, out_frame_done;
    logic [11:0] out_pixel;
    logic [15:0] out_x, out_y;

    // 外部参考状态：仅有效 sof 更新三路保存值，复位恢复 unity。
    int reference_r = 4096, reference_g = 4096, reference_b = 4096;
    int reference_pixel = 0, reference_x = 0, reference_y = 0;
    bit reference_valid = 0, reference_sof = 0, reference_eol = 0, reference_done = 0;
    int checked_cycles = 0;
    int gains [0:10] = '{0, 1, 2047, 2048, 2049, 4095, 4096, 4097, 6144, 8192, 65535};
    string selected_case;

    awb_gain dut (
        // 时钟和同步低有效复位。
        .clk(clk), .rst_n(rst_n),
        // 完整输入流及帧配置。
        .in_valid(in_valid), .in_pixel(in_pixel), .in_x(in_x), .in_y(in_y),
        .in_sof(in_sof), .in_eol(in_eol), .in_frame_done(in_frame_done),
        .gain_r(gain_r), .gain_g(gain_g), .gain_b(gain_b),
        // 完整一级寄存输出。
        .out_valid(out_valid), .out_pixel(out_pixel), .out_x(out_x), .out_y(out_y),
        .out_sof(out_sof), .out_eol(out_eol), .out_frame_done(out_frame_done)
    );

    // case inequality 同时拒绝 X/Z；不能依据 DUT valid 来移动参考输出时刻。
    task automatic check_output;
        if (out_valid !== reference_valid || out_pixel !== 12'(reference_pixel) ||
            out_x !== 16'(reference_x) || out_y !== 16'(reference_y) ||
            out_sof !== reference_sof || out_eol !== reference_eol || out_frame_done !== reference_done)
            $fatal(1, "AWB_UNIT cycle=%0d wanted v=%b p=%0d xy=(%0d,%0d) flags=%b%b%b actual v=%b p=%h xy=(%0d,%0d) flags=%b%b%b",
                   checked_cycles, reference_valid, reference_pixel, reference_x, reference_y,
                   reference_sof, reference_eol, reference_done, out_valid, out_pixel, out_x, out_y,
                   out_sof, out_eol, out_frame_done);
    endtask

    // 每次刺激先验证沿前旧结果保持，再计算采样沿对应的新期望，检查 NBA 后值。
    // 参数是未截断的整数；全部测试只提供合法 RAW12 和 UQ4.12 编码。
    task automatic drive(input bit valid_i, input int pixel_i,
                         input int r_i, input int g_i, input int b_i,
                         input bit sof_i, input bit eol_i, input bit done_i,
                         input int x_i = 0, input int y_i = 0, input bit reset_n = 1);
        longint product_ref, scaled_ref;
        int code;
        @(negedge clk);
        rst_n = reset_n; in_valid = valid_i; in_pixel = 12'(pixel_i);
        gain_r = 16'(r_i); gain_g = 16'(g_i); gain_b = 16'(b_i);
        in_sof = sof_i; in_eol = eol_i; in_frame_done = done_i;
        in_x = 16'(x_i); in_y = 16'(y_i);
        #1ps; check_output();
        @(posedge clk);
        if (!reset_n) begin
            reference_r = 4096; reference_g = 4096; reference_b = 4096;
            reference_pixel = 0; reference_x = 0; reference_y = 0;
            reference_valid = 0; reference_sof = 0; reference_eol = 0; reference_done = 0;
        end else begin
            if (valid_i && sof_i) begin
                reference_r = r_i; reference_g = g_i; reference_b = b_i;
            end
            reference_valid = valid_i; reference_sof = valid_i && sof_i;
            reference_eol = valid_i && eol_i; reference_done = valid_i && done_i;
            if (valid_i) begin
                // 独立余数阈值实现 round-half-up，不照搬 DUT 加 2048/移位路径。
                code = reference_g;
                if (x_i % 2 == 0 && y_i % 2 == 0) code = reference_r;
                if (x_i % 2 == 1 && y_i % 2 == 1) code = reference_b;
                product_ref = longint'(pixel_i) * code;
                scaled_ref = product_ref / 4096 + ((product_ref % 4096) >= 2048);
                reference_pixel = (scaled_ref > 4095) ? 4095 : int'(scaled_ref);
                reference_x = x_i; reference_y = y_i;
            end
        end
        #1ps; check_output(); checked_cycles++;
    endtask

    initial begin
        selected_case = "regression";
        void'($value$plusargs("CASE=%s", selected_case));
        drive(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        drive(0, 0, 0, 0, 0, 0, 0, 0);
        if (selected_case == "forced_failure") $fatal(1, "AWB_UNIT_FORCED_FAILURE");
        if (selected_case != "regression") $fatal(1, "AWB_UNIT_UNKNOWN_CASE");

        // 无效 sof 的零配置不能覆盖复位 unity，且三个通道均需验证。
        drive(0, 123, 0, 0, 0, 1, 1, 1, 99, 88);
        for (int phase = 0; phase < 4; phase++)
            drive(1, 4095, 0, 0, 0, 0, 0, 0, phase%2, phase/2);

        // 手算 2x2：100*(R=2,G=0.5,B=1.5) 为 200/50/50/150。
        // 后三拍故意改外部三增益，结果仍必须使用第一拍原子保存的三路值。
        drive(1, 100, 8192, 2048, 6144, 1, 0, 0, 0, 0);
        if (out_pixel !== 12'd200) $fatal(1, "AWB_UNIT_HAND_R");
        drive(1, 100, 0, 65535, 0, 0, 1, 0, 1, 0);
        if (out_pixel !== 12'd50) $fatal(1, "AWB_UNIT_HAND_GR");
        drive(1, 100, 65535, 0, 65535, 0, 0, 0, 0, 1);
        if (out_pixel !== 12'd50) $fatal(1, "AWB_UNIT_HAND_GB");
        drive(1, 100, 0, 0, 0, 0, 1, 1, 1, 1);
        if (out_pixel !== 12'd150) $fatal(1, "AWB_UNIT_HAND_B");

        // 连续 1x1 帧同时携带全部标志，每拍切换三路配置且首像素使用新值。
        drive(1, 1, 2047, 8192, 0, 1, 1, 1);
        drive(1, 1, 2048, 0, 8192, 1, 1, 1);
        if (out_pixel !== 12'd1) $fatal(1, "AWB_UNIT_HAND_HALF");
        drive(1, 4095, 4097, 2048, 0, 1, 1, 1);
        if (out_pixel !== 12'd4095) $fatal(1, "AWB_UNIT_HAND_SATURATION");

        // 对 11 个增益分别穷举全部 RAW12 输入，共 45056 次寄存结果检查。
        // 坐标低位循环覆盖四相位；零/unity 也必须经过一级寄存而非组合旁路。
        for (int k = 0; k < 11; k++) begin
            for (int pixel = 0; pixel < 4096; pixel++)
                drive(1, pixel, gains[k], gains[k], gains[k], 1, 1, 1, pixel%2, (pixel/2)%2);
            $display("[CASE] AWB exhaustive gain=%0d pixels=4096 PASS", gains[k]);
        end

        // 八个真实 8x8 坐标序列：帧中配置不断扰动，穿插 invalid sof 和 valid 空洞。
        // 帧间没有额外空拍要求；数值遍历 RAW12 广范围，旗标按外部尺寸计算。
        for (int frame = 0; frame < 8; frame++) begin
            for (int index = 0; index < 64; index++) begin
                if (index % 7 == 3)
                    drive(0, index, 0, 65535, 0, 1, 1, 1, 65535, 65535);
                drive(1, (frame*313+index*197)%4096,
                      (index == 0) ? gains[frame] : (index*619)%65536,
                      (index == 0) ? gains[frame+1] : (index*997)%65536,
                      (index == 0) ? gains[frame+3] : (index*337)%65536,
                      index == 0, index%8 == 7, index == 63, index%8, index/8);
            end
        end

        // 有效输入期间同步复位：采样沿清输出及配置，随后非 sof 输入仍按 unity。
        drive(1, 4095, 65535, 0, 8192, 1, 0, 0, 3, 4);
        drive(1, 2048, 0, 0, 0, 0, 1, 1, 9, 8, 0);
        for (int phase = 0; phase < 4; phase++)
            drive(1, 1024, 0, 0, 0, 0, 0, 0, phase%2, phase/2);
        drive(1, 100, 8192, 2048, 6144, 1, 1, 1);
        repeat (3) drive(0, 4095, 65535, 65535, 65535, 1, 1, 1);
        $display("[CASE] AWB checked cycles=%0d PASS", checked_cycles);
        $display("[PASS] AWB_UNIT");
        $finish;
    end

    // watchdog 覆盖穷举长回归，超过确定周期上限必须明确失败。
    initial begin
        #1000000;
        $fatal(1, "AWB_UNIT_TIMEOUT");
    end
endmodule
