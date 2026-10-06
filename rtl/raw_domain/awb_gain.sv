// AWB Gain：外部配置的 RGGB 增益施加，不包含统计或增益估计。
// 固定一级输出寄存；组合路径为相位译码、乘法、舍入和上限饱和。
module awb_gain #(
    parameter int PIXEL_W = 12, // P3 使用 RAW12，范围 0..4095。
    parameter int GAIN_W  = 16, // P3 增益为无符号 16 位 UQ4.12。
    parameter int FRAC_W  = 12  // 4096 为 unity；参数须满足 0 < FRAC_W < GAIN_W。
) (
    // 时钟/复位模块：所有寄存器采用上升沿、同步低有效复位。
    input  logic               clk,
    input  logic               rst_n,

    // 输入载荷模块：in_valid 限定像素及 16 位光栅坐标，无反压。
    // 相位仅从该像素的坐标最低位推导，避免独立 phase 与坐标错位。
    input  logic               in_valid,
    input  logic [PIXEL_W-1:0] in_pixel,
    input  logic [15:0]        in_x,
    input  logic [15:0]        in_y,

    // 输入帧标志模块：sof/eol/frame_done 分别标记首像素、行末和帧末。
    // 无效拍的标志即使为 1，也不能采样配置或形成输出帧事件。
    input  logic               in_sof,
    input  logic               in_eol,
    input  logic               in_frame_done,

    // 帧配置模块：三个 UQ4.12 编码在 valid+sof 同一沿原子锁存。
    // 首像素直接使用当拍外部增益，后续像素使用保存值，两个 G 共用 gain_g。
    input  logic [GAIN_W-1:0]  gain_r,
    input  logic [GAIN_W-1:0]  gain_g,
    input  logic [GAIN_W-1:0]  gain_b,

    // 输出载荷模块：固定一级寄存，包含 zero/unity 增益；无效拍载荷保持。
    output logic               out_valid,
    output logic [PIXEL_W-1:0] out_pixel,
    output logic [15:0]        out_x,
    output logic [15:0]        out_y,

    // 输出帧标志模块：与像素和坐标同拍，无效周期全部为零。
    output logic               out_sof,
    output logic               out_eol,
    output logic               out_frame_done
);
    localparam int PRODUCT_W = PIXEL_W + GAIN_W;
    localparam logic [GAIN_W-1:0] UNITY = GAIN_W'(1) << FRAC_W;
    localparam logic [PRODUCT_W:0] ROUND_BIAS = (PRODUCT_W+1)'(1) << (FRAC_W-1);
    localparam logic [PRODUCT_W:0] PIXEL_MAX =
        {{(PRODUCT_W+1-PIXEL_W){1'b0}}, {PIXEL_W{1'b1}}};

    // 配置存储与首像素旁路：旁路只作用于配置，不旁路输出寄存器。
    logic [GAIN_W-1:0] frame_r_q, frame_g_q, frame_b_q;
    logic [GAIN_W-1:0] effective_r, effective_g, effective_b, selected_gain;
    logic [PRODUCT_W-1:0] product;
    logic [PRODUCT_W:0] biased_product, scaled_pixel;
    logic [PIXEL_W-1:0] saturated_pixel;

    assign effective_r = (in_valid && in_sof) ? gain_r : frame_r_q;
    assign effective_g = (in_valid && in_sof) ? gain_g : frame_g_q;
    assign effective_b = (in_valid && in_sof) ? gain_b : frame_b_q;

    // RGGB 奇偶译码：00=R，01=Gr，10=Gb，11=B，顺序是 {y[0],x[0]}。
    // 只有一个三选一组合路径，两个绿色位置均选择 effective_g。
    always_comb begin
        case ({in_y[0], in_x[0]})
            2'b00: selected_gain = effective_r;
            2'b11: selected_gain = effective_b;
            default: selected_gain = effective_g;
        endcase
    end

    // 乘积目标位宽为完整 PIXEL_W+GAIN_W（默认 28 位），不能先存入 16 位。
    // 加偏置先显式扩展为 29 位；随后保持宽结果做饱和比较，最后才取低 12 位。
    // 若先截断再判断，4095*4097 舍入到 4096 将错误回绕成零。
    assign product = in_pixel * selected_gain;
    assign biased_product = {1'b0, product} + ROUND_BIAS;
    assign scaled_pixel = biased_product >> FRAC_W;
    assign saturated_pixel = (scaled_pixel > PIXEL_MAX) ?
                             {PIXEL_W{1'b1}} : scaled_pixel[PIXEL_W-1:0];

    // 配置寄存器：非阻塞赋值同时更新三路，复位 unity 保证非 sof 输入也确定。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            frame_r_q <= UNITY;
            frame_g_q <= UNITY;
            frame_b_q <= UNITY;
        end else if (in_valid && in_sof) begin
            frame_r_q <= gain_r;
            frame_g_q <= gain_g;
            frame_b_q <= gain_b;
        end
    end

    // 数值寄存器：每个有效输入沿计算一次；无效拍保持载荷，不增加流水级。
    always_ff @(posedge clk) begin
        if (!rst_n)
            out_pixel <= '0;
        else if (in_valid)
            out_pixel <= saturated_pixel;
    end

    // 坐标寄存器：与像素采用相同使能，供后续模块继续推导 Bayer 位置。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            out_x <= '0;
            out_y <= '0;
        end else if (in_valid) begin
            out_x <= in_x;
            out_y <= in_y;
        end
    end

    // 有效位寄存器：每拍采样，连续流与有效空洞均保持固定一级延迟。
    always_ff @(posedge clk) begin
        if (!rst_n)
            out_valid <= 1'b0;
        else
            out_valid <= in_valid;
    end

    // 帧标志寄存器：valid 门控防止无效 sof/eol/frame_done 污染输出。
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
