// P2 稳定 BLC-only 流水线：同步 SRAM -> Reader-only Source -> 一级 BLC -> RAW12。
// Source 保留 C2 首像素；BLC 后公开首像素为 C3，吞吐仍为一拍一像素。
module blc_pipeline #(
    parameter int ADDR_W = 20, // 与外部 SRAM 地址总线匹配。
    parameter int PIXEL_W = 12 // 默认 RAW12，源与 BLC 的像素位宽一致。
) (
    // 时钟/复位模块：Source、BLC 和启动历史均使用同步低有效复位。
    input  logic               clk,
    input  logic               rst_n,

    // 帧控制模块：仅整个流水线空闲时接受新的 start 上升沿。
    // 宽高由 Source 在合法启动时锁存，busy 包含 BLC 最后有效输出周期。
    input  logic               start,
    input  logic [15:0]        image_width,
    input  logic [15:0]        image_height,
    output logic               busy,

    // 算法配置模块：BLC 在消费有效首像素的沿采样，而不是 start 沿。
    // 当前帧后续修改不会改变像素结果；零偏置仍保留固定一级寄存。
    input  logic [PIXEL_W-1:0] black_level,

    // SRAM 模块：地址由 Source 提供，返回字是一个上升沿寄存的 16 位数据。
    output logic [ADDR_W-1:0]  sram_addr,
    input  logic [15:0]        sram_rdata,

    // BLC 输出载荷模块：valid 限定数据和 16 位光栅坐标，无反压。
    output logic               pixel_valid,
    output logic [PIXEL_W-1:0] pixel_data,
    output logic [15:0]        pixel_x,
    output logic [15:0]        pixel_y,

    // BLC 输出帧标志模块：与对应像素同步；无效周期全部为零。
    // frame_done 与末像素同拍，busy 在其后的上升沿才解除。
    output logic               sof,
    output logic               eol,
    output logic               frame_done
);
    // Source 内部 RAW 流：公开像素端口只连接 BLC，避免混淆两级时序。
    logic raw_busy, raw_valid, raw_sof, raw_eol, raw_frame_done;
    logic [PIXEL_W-1:0] raw_pixel;
    logic [15:0] raw_x, raw_y;
    logic start_q, source_start;

    // Source 最后有效拍仍 busy；下一拍 BLC 输出末像素时 valid 接续 busy。
    // 这里只对寄存输出做 OR，不增加流水级、不在像素减法热路径上反馈。
    assign busy = raw_busy || pixel_valid;

    // 外部边沿历史必须在忙时也更新：简单 start & !busy 门控会将一个
    // 忙时保持高电平误变成空闲后的新上升沿。只转发原始输入的新边沿。
    always_ff @(posedge clk) begin
        if (!rst_n)
            start_q <= 1'b0;
        else
            start_q <= start;
    end
    assign source_start = start && !start_q && !busy;

    sram_raw_source #(.ADDR_W(ADDR_W), .PIXEL_W(PIXEL_W)) source (
        // 时钟、资格已过滤的启动及尺寸；零尺寸/容量检查仍由 Reader 执行。
        .clk(clk), .rst_n(rst_n), .start(source_start),
        .image_width(image_width), .image_height(image_height), .busy(raw_busy),
        // 外部同步 SRAM。
        .sram_addr(sram_addr), .sram_rdata(sram_rdata),
        // 内部 RAW 流及全部侧带。
        .pixel_valid(raw_valid), .pixel_data(raw_pixel), .pixel_x(raw_x), .pixel_y(raw_y),
        .sof(raw_sof), .eol(raw_eol), .frame_done(raw_frame_done)
    );

    blc #(.PIXEL_W(PIXEL_W)) correction (
        // 与 Source 相同的同步时钟和复位。
        .clk(clk), .rst_n(rst_n),
        // 完整输入流与帧首采样配置。
        .in_valid(raw_valid), .in_pixel(raw_pixel), .in_x(raw_x), .in_y(raw_y),
        .in_sof(raw_sof), .in_eol(raw_eol), .in_frame_done(raw_frame_done),
        .black_level(black_level),
        // 正式顶层只输出 BLC 的寄存结果。
        .out_valid(pixel_valid), .out_pixel(pixel_data), .out_x(pixel_x), .out_y(pixel_y),
        .out_sof(sof), .out_eol(eol), .out_frame_done(frame_done)
    );
endmodule
