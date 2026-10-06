// P3 正式流水线：同步 SRAM -> Reader -> BLC -> AWB Gain -> RAW12。
// 独立 blc_pipeline 保留 C3 边界；最终输出 C4，仍为每拍一个像素。
module isp_pipeline_top #(
    parameter int ADDR_W = 20, // 匹配外部 SRAM 地址宽度，容量由 Reader 检查。
    parameter int PIXEL_W = 12 // P3 数值契约为 RAW12。
) (
    // 时钟/复位模块：全部流水级及启动历史使用同步低有效复位。
    input  logic               clk,
    input  logic               rst_n,

    // 帧控制模块：仅整条链路空闲时接受 start 的新上升沿。
    // Reader 在该沿锁存尺寸；busy 包含 AWB 最后有效输出周期。
    input  logic               start,
    input  logic [15:0]        image_width,
    input  logic [15:0]        image_height,
    output logic               busy,

    // 算法配置模块：BLC 与 AWB 分别在各自的 valid+sof 沿锁存配置。
    // 黑电平为 RAW12 整数，三增益为 UQ4.12 编码（4096 为 1 倍）。
    // C0 启动不锁存算法配置：首像素处 BLC=C3、AWB=C4 分别采样。
    input  logic [PIXEL_W-1:0] black_level,
    input  logic [15:0]        gain_r,
    input  logic [15:0]        gain_g,
    input  logic [15:0]        gain_b,

    // SRAM 模块：请求地址来自 Reader，返回字为一周期同步 16 位数据。
    output logic [ADDR_W-1:0]  sram_addr,
    input  logic [15:0]        sram_rdata,

    // 最终载荷模块：AWB 后有效 RAW12 及对应 16 位光栅坐标，无反压。
    output logic               pixel_valid,
    output logic [PIXEL_W-1:0] pixel_data,
    output logic [15:0]        pixel_x,
    output logic [15:0]        pixel_y,

    // 最终帧标志模块：首像素/行末/帧末与数据同拍，无效拍标志全部为零。
    // 最后 frame_done 拍 busy 仍为 1，下一上升沿才解除。
    output logic               sof,
    output logic               eol,
    output logic               frame_done
);
    // BLC-only 级间流：该级完整保留 Source 和 BLC 的原有时序/控制行为。
    logic blc_busy, blc_valid, blc_sof, blc_eol, blc_frame_done;
    logic [PIXEL_W-1:0] blc_pixel;
    logic [15:0] blc_x, blc_y;
    logic start_q, blc_start;

    // BLC 最后有效输出由 blc_busy 覆盖；AWB 最后输出由最终 valid 接续。
    // 直接组合 OR 寄存状态，不增加输出级，也不反馈到乘法数值热路径。
    assign busy = blc_busy || pixel_valid;

    // 每拍保存原始 start，包括忙时边沿，避免 held-high 在解除 busy 后重启。
    // 本层过滤 AWB-only 排空周期；blc_pipeline 保留自己的历史边界过滤。
    always_ff @(posedge clk) begin
        if (!rst_n)
            start_q <= 1'b0;
        else
            start_q <= start;
    end
    assign blc_start = start && !start_q && !busy;

    blc_pipeline #(.ADDR_W(ADDR_W), .PIXEL_W(PIXEL_W)) black_level_stage (
        // 时钟、整链路资格过滤后的启动及原始帧尺寸。
        .clk(clk), .rst_n(rst_n), .start(blc_start),
        .image_width(image_width), .image_height(image_height), .busy(blc_busy),
        // SRAM 接口及 BLC 配置。
        .sram_addr(sram_addr), .sram_rdata(sram_rdata), .black_level(black_level),
        // 一级 BLC 流，全部侧带传给 AWB。
        .pixel_valid(blc_valid), .pixel_data(blc_pixel), .pixel_x(blc_x), .pixel_y(blc_y),
        .sof(blc_sof), .eol(blc_eol), .frame_done(blc_frame_done)
    );

    awb_gain #(.PIXEL_W(PIXEL_W), .GAIN_W(16), .FRAC_W(12)) white_balance_stage (
        // 时钟及与 BLC 一致的同步复位。
        .clk(clk), .rst_n(rst_n),
        // BLC 寄存输出及三路帧首采样配置。
        .in_valid(blc_valid), .in_pixel(blc_pixel), .in_x(blc_x), .in_y(blc_y),
        .in_sof(blc_sof), .in_eol(blc_eol), .in_frame_done(blc_frame_done),
        .gain_r(gain_r), .gain_g(gain_g), .gain_b(gain_b),
        // 公开输出只连接 AWB 寄存结果，保证固定 C4 首像素。
        .out_valid(pixel_valid), .out_pixel(pixel_data), .out_x(pixel_x), .out_y(pixel_y),
        .out_sof(sof), .out_eol(eol), .out_frame_done(frame_done)
    );
endmodule
