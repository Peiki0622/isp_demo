// P5 正式 RGB 流水线：保留独立P4 Demosaic边界，再接两级signed CCM。
module isp_pipeline_top #(
    parameter int ADDR_W = 20, // SRAM 地址空间；启动资格检查保留完整尺寸乘积。
    parameter int PIXEL_W = 12, // 输入RAW12，最终每通道RGB12。
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
    // CCM帧配置模块：signed16补码、12小数位，行=输出通道，列=输入通道。
    // 在CCM的有效sof采样，accepted start后C(W+8)；不是在C0提前锁存。
    input logic signed [15:0] c00, c01, c02,
    input logic signed [15:0] c10, c11, c12,
    input logic signed [15:0] c20, c21, c22,
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
    logic start_q, forward_start;
    logic demosaic_busy, ccm_busy, rgb_valid, rgb_sof, rgb_eol, rgb_done;
    logic [PIXEL_W-1:0] rgb_r, rgb_g, rgb_b;
    logic [15:0] rgb_x, rgb_y;
    // 整链占用块：P4预热/tail与CCM Stage1/最后输出有效位共同覆盖busy。
    // 无反馈到像素乘加热路径；最后RGB拍busy=1，下一沿才清零。
    assign busy=demosaic_busy || ccm_busy;
    assign forward_start=start && !start_q && !busy;
    // 外部start历史块：包括忙时、尺寸拒绝及busy清零沿，防止保持高电平重启。
    always_ff @(posedge clk) begin
        if (!rst_n) start_q<=0;
        else start_q<=start;
    end
    demosaic_pipeline #(.ADDR_W(ADDR_W),.PIXEL_W(PIXEL_W),.MAX_WIDTH(MAX_WIDTH)) raw_to_rgb (
        // P4独立边界在内部保留完整尺寸资格检查、C0尺寸锁存与C3/C4配置采样。
        .clk(clk),.rst_n(rst_n),.start(forward_start),.busy(demosaic_busy),
        .image_width(image_width),.image_height(image_height),
        .black_level(black_level),.gain_r(gain_r),.gain_g(gain_g),.gain_b(gain_b),
        // 同步SRAM请求不增加任何寄存延迟。
        .sram_addr(sram_addr),.sram_rdata(sram_rdata),
        // P4的RGB和全部坐标/侧带仍为C(W+7)..C(N+W+6)，下一沿被CCM采样。
        .pixel_valid(rgb_valid),.pixel_r(rgb_r),.pixel_g(rgb_g),.pixel_b(rgb_b),
        .pixel_x(rgb_x),.pixel_y(rgb_y),.sof(rgb_sof),.eol(rgb_eol),.frame_done(rgb_done)
    );
    ccm #(.RGB_W(PIXEL_W),.COEF_W(16)) color_matrix (
        // 完整P4寄存流进入CCM，不修改上游坐标或帧标志。
        .clk(clk),.rst_n(rst_n),.in_valid(rgb_valid),.in_r(rgb_r),.in_g(rgb_g),.in_b(rgb_b),
        .in_x(rgb_x),.in_y(rgb_y),.in_sof(rgb_sof),.in_eol(rgb_eol),.in_frame_done(rgb_done),
        // 九系数传到CCM，由其有效SOF原子采样并给首像素前递。
        .c00(c00),.c01(c01),.c02(c02),.c10(c10),.c11(c11),.c12(c12),.c20(c20),.c21(c21),.c22(c22),
        // 最终公开输出只来自CCM第二级，first/last/idle为W+9/N+W+8/N+W+9。
        .out_valid(pixel_valid),.out_r(pixel_r),.out_g(pixel_g),.out_b(pixel_b),
        .out_x(pixel_x),.out_y(pixel_y),.out_sof(sof),.out_eol(eol),.out_frame_done(frame_done),.busy(ccm_busy)
    );
endmodule
