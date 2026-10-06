// P4 独立 Demosaic-only 流水线：保留独立 AWB-only 边界，再接窗口及双线性去马赛克。
module demosaic_pipeline #(
    parameter int ADDR_W = 20, // SRAM 地址空间；启动资格检查保留完整尺寸乘积。
    parameter int PIXEL_W = 12, // P4 输入 RAW12、输出每通道 RGB12。
    parameter int MAX_WIDTH = 4096 // 三行存储的静态行容量。
) (
    // 时钟/复位模块：同步低有效复位同时中止上游、窗口和最终 RGB 排空。
    input logic clk,
    input logic rst_n,
    // 帧控制模块：只有整链空闲时的新 start 上升沿及合法尺寸才接受。
    // 尺寸在接受沿锁存；busy 保持到最后 RGB 有效拍之后的一个上升沿。
    input logic start,
    input logic [15:0] image_width, image_height,
    output logic busy,
    // 算法配置模块：BLC/AWB 各自在有效 sof 采样；C0 不锁存这些参数。
    // BLC 为 RAW12 整数，三增益为 UQ4.12 编码，两个绿色位置共用 gain_g。
    input logic [PIXEL_W-1:0] black_level,
    input logic [15:0] gain_r, gain_g, gain_b,
    // SRAM 模块：外部一周期同步 16 位 SRAM，地址完全由既有 Reader 产生。
    output logic [ADDR_W-1:0] sram_addr,
    input logic [15:0] sram_rdata,
    // RGB 载荷模块：三个通道及 16 位中心坐标，无反压；有效区逐拍连续。
    output logic pixel_valid,
    output logic [PIXEL_W-1:0] pixel_r, pixel_g, pixel_b,
    output logic [15:0] pixel_x, pixel_y,
    // 最终帧标志模块：与 RGB 同拍，首/行末/帧末按输出中心重建。
    // 无效拍全部为零，frame_done 当拍 busy 仍为一。
    output logic sof, eol, frame_done
);
    logic start_q, start_rise, accepted_start, dimensions_legal, frame_fits;
    logic [31:0] requested_pixels;
    localparam logic [63:0] ADDRESS_CAPACITY = 64'd1 << ADDR_W;
    logic [15:0] frame_width_q, frame_height_q;
    // AWB-only 级间流，独立边界继续保持 C4，窗口在下一沿消费。
    logic awb_busy, awb_valid, awb_sof, awb_eol, awb_done, demosaic_busy;
    logic [PIXEL_W-1:0] awb_pixel;
    logic [15:0] awb_x, awb_y;
    assign busy = awb_busy || demosaic_busy;
    // 尺寸检查仅在启动控制路径上；先拓宽乘法，避免 16 位乘积回绕。
    assign requested_pixels = {16'd0,image_width} * {16'd0,image_height};
    assign dimensions_legal = image_width >= 2 && image_height >= 2 &&
                              {16'd0,image_width} <= 32'(MAX_WIDTH);
    assign frame_fits = {32'd0,requested_pixels} <= ADDRESS_CAPACITY;
    assign start_rise = start && !start_q;
    assign accepted_start = start_rise && !busy && dimensions_legal && frame_fits;
    // 外部启动历史块：忙时和非法尺寸时也更新，held-high 不能自动重启。
    always_ff @(posedge clk) begin
        if (!rst_n) start_q <= 0;
        else start_q <= start;
    end
    // 稳定帧尺寸块：只与实际转发到上游的合法启动事件同时锁存。
    always_ff @(posedge clk) begin
        if (!rst_n) begin frame_width_q <= '0; frame_height_q <= '0; end
        else if (accepted_start) begin
            frame_width_q <= image_width; frame_height_q <= image_height;
        end
    end
    awb_pipeline #(.ADDR_W(ADDR_W), .PIXEL_W(PIXEL_W)) raw_stages (
        // 上游接受资格已由整链 busy 过滤；内部 C2/C3/C4 时序保持。
        .clk(clk), .rst_n(rst_n), .start(accepted_start),
        .image_width(image_width), .image_height(image_height), .busy(awb_busy),
        // 原有外部 SRAM 与两级帧首采样配置。
        .black_level(black_level), .gain_r(gain_r), .gain_g(gain_g), .gain_b(gain_b),
        .sram_addr(sram_addr), .sram_rdata(sram_rdata),
        // 完整 RAW12 中间流，数据/坐标/侧带一一对应。
        .pixel_valid(awb_valid), .pixel_data(awb_pixel), .pixel_x(awb_x), .pixel_y(awb_y),
        .sof(awb_sof), .eol(awb_eol), .frame_done(awb_done)
    );
    demosaic #(.RAW_W(PIXEL_W), .RGB_W(PIXEL_W), .MAX_WIDTH(MAX_WIDTH)) rgb_stage (
        // AWB RAW 流与启动时锁存的帧尺寸，绝不传外部可变 image_*。
        .clk(clk), .rst_n(rst_n), .in_valid(awb_valid), .in_pixel(awb_pixel), .in_x(awb_x), .in_y(awb_y),
        .in_sof(awb_sof), .in_eol(awb_eol), .in_frame_done(awb_done),
        .frame_width(frame_width_q), .frame_height(frame_height_q),
        // 正式公开 RGB 输出仅来自最终寄存级，包含最后输出的 busy。
        .out_valid(pixel_valid), .out_r(pixel_r), .out_g(pixel_g), .out_b(pixel_b),
        .out_x(pixel_x), .out_y(pixel_y), .out_sof(sof), .out_eol(eol), .out_frame_done(frame_done), .busy(demosaic_busy)
    );
    // 仿真容量诊断：硬件资格门控始终存在，关闭诊断仍不能发起超容量帧。
    // synopsys translate_off
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && start_rise && !busy && dimensions_legal && !frame_fits)
            $fatal(1,"SRAM_FRAME_TOO_LARGE: pixels=%0d capacity=%0d",requested_pixels,ADDRESS_CAPACITY);
    end
`endif
    // synopsys translate_on
endmodule
