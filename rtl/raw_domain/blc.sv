// BLC 全局黑电平校正：无反压、每拍一个像素、固定一级寄存流水。
// 数值路径只有比较、减法和下限钳位；配置多路选择位于寄存器之前。
// 帧首使用当前配置，后续像素使用锁存配置；不需要额外状态机。
module blc #(
    parameter int PIXEL_W = 12  // 默认 RAW12；偏置和像素始终采用相同位宽。
) (
    // 时钟/复位模块：全部状态在上升沿更新，rst_n 为同步低有效复位。
    input  logic               clk,
    input  logic               rst_n,

    // 输入载荷模块：in_valid 限定像素和 16 位坐标，无 ready/反压。
    input  logic               in_valid,
    input  logic [PIXEL_W-1:0] in_pixel,
    input  logic [15:0]        in_x,
    input  logic [15:0]        in_y,

    // 输入帧标志模块：sof 为首像素，eol 为行末，frame_done 为帧末。
    // 无效拍标志即使为 1 也不能更新帧配置或传播到输出。
    input  logic               in_sof,
    input  logic               in_eol,
    input  logic               in_frame_done,

    // 帧配置模块：仅 valid+sof 所在采样沿锁存全局无符号偏置。
    // 外部配置可在其他周期变化；当帧首到达时才影响该帧。
    input  logic [PIXEL_W-1:0] black_level,

    // 输出载荷模块：输入载荷经过一级寄存；无效时数据/坐标保持。
    output logic               out_valid,
    output logic [PIXEL_W-1:0] out_pixel,
    output logic [15:0]        out_x,
    output logic [15:0]        out_y,

    // 输出帧标志模块：与输出像素同拍；out_valid=0 时全部归零。
    output logic               out_sof,
    output logic               out_eol,
    output logic               out_frame_done
);
    logic [PIXEL_W-1:0] frame_black_level_q;
    logic [PIXEL_W-1:0] effective_black_level;

    // 帧首不能读取刚被非阻塞赋值的寄存器：该沿仍只能看到旧值。
    // 直接选择当前输入配置，保证第一个像素也使用本帧的新偏置。
    assign effective_black_level = (in_valid && in_sof) ?
                                   black_level : frame_black_level_q;

    // 配置寄存器：只有有效帧首写入，无效 sof 和帧中修改均被忽略。
    always_ff @(posedge clk) begin
        if (!rst_n)
            frame_black_level_q <= '0;
        else if (in_valid && in_sof)
            frame_black_level_q <= black_level;
    end

    // 数值寄存器：比较先行避免无符号下溢；相等时输出也钳位为零。
    // 减非负偏置不会超过输入，因此无上限饱和器或额外流水级。
    always_ff @(posedge clk) begin
        if (!rst_n)
            out_pixel <= '0;
        else if (in_valid)
            out_pixel <= (in_pixel > effective_black_level) ?
                         (in_pixel - effective_black_level) : '0;
    end

    // 坐标寄存器：与数值寄存器采用相同有效使能和采样沿。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            out_x <= '0;
            out_y <= '0;
        end else if (in_valid) begin
            out_x <= in_x;
            out_y <= in_y;
        end
    end

    // 有效位寄存器：每拍更新，输入空洞必须按一拍延迟传播。
    always_ff @(posedge clk) begin
        if (!rst_n)
            out_valid <= 1'b0;
        else
            out_valid <= in_valid;
    end

    // 标志寄存器：只传播有效输入的标志，防止空洞造成虚假帧事件。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            out_sof <= 1'b0;
            out_eol <= 1'b0;
            out_frame_done <= 1'b0;
        end else begin
            out_sof <= in_valid && in_sof;
            out_eol <= in_valid && in_eol;
            out_frame_done <= in_valid && in_frame_done;
        end
    end
endmodule
