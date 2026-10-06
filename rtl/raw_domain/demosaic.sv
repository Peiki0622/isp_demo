// RGGB 双线性去马赛克：已登记的 3x3 窗口 -> 整数平均 -> 一级 RGB 寄存。
module demosaic #(
    parameter int RAW_W = 12, // P4 使用 RAW12；加法中间位宽由 RAW_W 扩展。
    parameter int RGB_W = 12, // P4 RGB 三通道与输入有效精度一致。
    parameter int MAX_WIDTH = 4096 // 传给窗口的静态行容量。
) (
    // 时钟/复位模块：同步低有效复位同时中止窗口及 RGB 最后一级。
    input logic clk,
    input logic rst_n,
    // RAW 载荷模块：坐标为该输入像素坐标，无反压，帧内连续 valid。
    input logic in_valid,
    input logic [RAW_W-1:0] in_pixel,
    input logic [15:0] in_x, in_y,
    // 输入帧控制模块：完整侧带交给窗口重建；有效 sof 必须在 busy=0。
    input logic in_sof, in_eol, in_frame_done,
    // 稳定尺寸模块：使用 top 在合法启动时锁存的整帧宽高。
    input logic [15:0] frame_width, frame_height,
    // RGB 载荷模块：三个通道和中心坐标严格同沿寄存，没有组合旁路。
    output logic out_valid,
    output logic [RGB_W-1:0] out_r, out_g, out_b,
    output logic [15:0] out_x, out_y,
    // 输出帧控制模块：最终 frame_done 与最后 RGB 同拍，busy 包含该拍。
    output logic out_sof, out_eol, out_frame_done,
    output logic busy
);
    // 窗口级间流，全部来自窗口寄存器；相位必须取中心，不能取当前输入。
    logic window_valid, window_busy, window_sof, window_eol, window_done, window_in_valid;
    logic [15:0] center_x, center_y;
    logic [RAW_W-1:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    assign busy = window_busy || out_valid;
    // 尾部 RGB 尚有效时窗口可能已空闲；额外门控禁止首像素误启动下一帧。
    assign window_in_valid = in_valid && (!in_sof || !busy);
    window_3x3 #(.PIXEL_W(RAW_W), .MAX_WIDTH(MAX_WIDTH)) neighborhood (
        // 完整 RAW 输入流和帧尺寸。
        .clk(clk), .rst_n(rst_n), .in_valid(window_in_valid), .in_pixel(in_pixel), .in_x(in_x), .in_y(in_y),
        .in_sof(in_sof), .in_eol(in_eol), .in_frame_done(in_frame_done),
        .frame_width(frame_width), .frame_height(frame_height),
        // 九个邻居及对应中心坐标。
        .p00(p00), .p01(p01), .p02(p02), .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22), .center_x(center_x), .center_y(center_y),
        // 已重建的窗口有效位/标志和窗口忙状态。
        .out_valid(window_valid), .out_sof(window_sof), .out_eol(window_eol),
        .out_frame_done(window_done), .busy(window_busy)
    );
    // 平衡加法树：两项和保留 RAW_W+1 位，四项偏置和保留 RAW_W+2 位。
    // 每个操作数先零扩展；不能先发生 RAW12 溢出再赋给宽变量。
    logic [RAW_W:0] cross0, cross1, diagonal0, diagonal1, horizontal, vertical;
    logic [RAW_W+1:0] cross_sum, diagonal_sum;
    logic [RGB_W-1:0] cross_average, diagonal_average, horizontal_average, vertical_average;
    logic [RGB_W-1:0] next_r, next_g, next_b;
    assign cross0 = {1'b0,p01} + {1'b0,p10};
    assign cross1 = {1'b0,p12} + {1'b0,p21};
    assign diagonal0 = {1'b0,p00} + {1'b0,p02};
    assign diagonal1 = {1'b0,p20} + {1'b0,p22};
    assign cross_sum = {1'b0,cross0} + {1'b0,cross1} + (RAW_W+2)'(2);
    assign diagonal_sum = {1'b0,diagonal0} + {1'b0,diagonal1} + (RAW_W+2)'(2);
    assign horizontal = {1'b0,p10} + {1'b0,p12} + (RAW_W+1)'(1);
    assign vertical = {1'b0,p01} + {1'b0,p21} + (RAW_W+1)'(1);
    // 移位只去掉平均分母位，结果数学上不会超过 4095，无需上限饱和。
    assign cross_average = RGB_W'(cross_sum >> 2);
    assign diagonal_average = RGB_W'(diagonal_sum >> 2);
    assign horizontal_average = RGB_W'(horizontal >> 1);
    assign vertical_average = RGB_W'(vertical >> 1);
    // 四类 Bayer 中心译码：00=R，01=Gr，10=Gb，11=B。
    always_comb begin
        next_r = '0; next_g = '0; next_b = '0;
        case ({center_y[0],center_x[0]})
            2'b00: begin next_r=RGB_W'(p11); next_g=cross_average; next_b=diagonal_average; end
            2'b01: begin next_r=horizontal_average; next_g=RGB_W'(p11); next_b=vertical_average; end
            2'b10: begin next_r=vertical_average; next_g=RGB_W'(p11); next_b=horizontal_average; end
            2'b11: begin next_r=diagonal_average; next_g=cross_average; next_b=RGB_W'(p11); end
            default: begin end
        endcase
    end
    // 算术载荷寄存块：即便全零或满量程也保留这一级，不产生旁路。
    always_ff @(posedge clk) begin
        if (!rst_n) begin out_r<='0; out_g<='0; out_b<='0; end
        else if (window_valid) begin out_r<=next_r; out_g<=next_g; out_b<=next_b; end
    end
    // 中心坐标寄存块：与三个 RGB 通道使用相同使能。
    always_ff @(posedge clk) begin
        if (!rst_n) begin out_x<='0; out_y<='0; end
        else if (window_valid) begin out_x<=center_x; out_y<=center_y; end
    end
    // 有效位寄存块：覆盖窗口后额外一拍；参与 busy 以保护最终排空。
    always_ff @(posedge clk) begin
        if (!rst_n) out_valid<=0;
        else out_valid<=window_valid;
    end
    // 帧标志寄存块：与 RGB 一级对齐，无效拍强制归零。
    always_ff @(posedge clk) begin
        if (!rst_n) begin out_sof<=0; out_eol<=0; out_frame_done<=0; end
        else begin
            out_sof<=window_valid && window_sof;
            out_eol<=window_valid && window_eol;
            out_frame_done<=window_valid && window_done;
        end
    end
    // 仿真重叠帧诊断独立于综合拒绝门控，不进入实际 RGB 数值路径。
    // synopsys translate_off
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && in_valid && in_sof && busy) $fatal(1,"DEMOSAIC_FRAME_OVERLAP");
    end
`endif
    // synopsys translate_on
endmodule
