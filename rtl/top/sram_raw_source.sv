// 独立 SRAM RAW Source：保留已验收的 P0/P1 Reader-only 边界。
// 本封装不增加寄存器或算法：C0 接受启动、C1 SRAM 采样、C2 首像素。
// 参数、容量资格判断和启动过滤均委托给原 sram_reader。
module sram_raw_source #(
    parameter int ADDR_W = 20,  // 与外部 SRAM 地址总线匹配。
    parameter int PIXEL_W = 12  // RAW 有效位宽，默认 RAW12。
) (
    // 时钟/复位模块：同步低有效复位直接传递到 reader。
    input  logic               clk,
    input  logic               rst_n,

    // 帧控制模块：空闲时的 start 上升沿启动；busy 时尺寸变化与启动被忽略。
    input  logic               start,
    input  logic [15:0]        image_width,
    input  logic [15:0]        image_height,
    output logic               busy,

    // SRAM 模块：外部提供 16 位、一个上升沿寄存延迟的同步存储器返回值。
    output logic [ADDR_W-1:0]  sram_addr,
    input  logic [15:0]        sram_rdata,

    // RAW 流模块：所有数据/坐标/标志与 pixel_valid 对齐，无反压接口。
    // frame_done 与最后像素同周期，busy 在随后的周期清零。
    output logic               pixel_valid,
    output logic [PIXEL_W-1:0] pixel_data,
    output logic [15:0]        pixel_x,
    output logic [15:0]        pixel_y,
    output logic               sof,
    output logic               eol,
    output logic               frame_done
);
    sram_reader #(.ADDR_W(ADDR_W), .PIXEL_W(PIXEL_W)) reader (
        // 时钟及帧控制。
        .clk(clk), .rst_n(rst_n), .start(start),
        .image_width(image_width), .image_height(image_height), .busy(busy),
        // SRAM 请求/返回。
        .sram_addr(sram_addr), .sram_rdata(sram_rdata),
        // 已对齐的原始像素流直接作为顶层输出。
        .pixel_valid(pixel_valid), .pixel_data(pixel_data),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .sof(sof), .eol(eol), .frame_done(frame_done)
    );
endmodule
