// P5 RGB CCM：九个signed乘积寄存，再宽位累加/舍入/钳位寄存。
// 固定两级、每拍一个像素；不增加旁路、offset、反压或状态机。
module ccm #(
    parameter int RGB_W = 12,  // P5 每通道RGB12有效精度。
    parameter int COEF_W = 16  // signed16补码，固定12个小数位。
) (
    // 时钟/复位模块：同步低有效；清空流水并恢复整数identity矩阵。
    input logic clk, rst_n,
    // 输入载荷模块：RGB为无符号，坐标16位；允许valid hole。
    input logic in_valid,
    input logic [RGB_W-1:0] in_r, in_g, in_b,
    input logic [15:0] in_x, in_y,
    // 输入帧控制模块：全部受valid限定，valid+sof原子采样矩阵。
    input logic in_sof, in_eol, in_frame_done,
    // 矩阵配置模块：行=输出R/G/B，列=输入R/G/B，4096=+1.0。
    // 首像素用当拍外部新系数，其余像素用保存矩阵；所有系数均signed。
    input logic signed [COEF_W-1:0] c00, c01, c02,
    input logic signed [COEF_W-1:0] c10, c11, c12,
    input logic signed [COEF_W-1:0] c20, c21, c22,
    // 输出载荷模块：三个通道及坐标只来自第二级寄存，identity也不旁路。
    output logic out_valid,
    output logic [RGB_W-1:0] out_r, out_g, out_b,
    output logic [15:0] out_x, out_y,
    // 输出控制模块：两级侧带与RGB对齐，无效标志归零。
    // busy表示流水非空，不门控输入；连续1x1帧也能逐拍进入。
    output logic out_sof, out_eol, out_frame_done,
    output logic busy
);
    localparam int FRAC_W = 12;
    localparam int PRODUCT_W = RGB_W+1+COEF_W; // 默认13x16 -> signed29。
    localparam int ACC_W = PRODUCT_W+2;        // 三项和保留两个保护位。
    localparam logic signed [ACC_W-1:0] ROUND_BIAS = 2048;
    localparam logic signed [ACC_W-1:0] MAX_PIXEL = (1<<RGB_W)-1;
    logic signed [COEF_W-1:0] matrix_q [0:2][0:2], effective [0:2][0:2];
    logic signed [RGB_W:0] pixel_signed [0:2];
    logic signed [PRODUCT_W-1:0] product_d [0:2][0:2], product_q [0:2][0:2];
    logic signed [ACC_W-1:0] extended [0:2][0:2];
    logic signed [ACC_W-1:0] pair_sum [0:2], accumulator [0:2];
    logic signed [ACC_W-1:0] rounded_sum [0:2], scaled [0:2];
    logic [RGB_W-1:0] clamped [0:2];
    logic stage1_valid, stage1_sof, stage1_eol, stage1_done;
    logic [15:0] stage1_x, stage1_y;
    assign busy=stage1_valid || out_valid;

    // 帧配置寄存块：九个元素在同沿更新，不能出现部分新/部分旧。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int row=0; row<3; row++) for (int col=0; col<3; col++)
                matrix_q[row][col] <= (row==col) ? COEF_W'(4096) : '0;
        end else if (in_valid && in_sof) begin
            matrix_q[0][0]<=c00; matrix_q[0][1]<=c01; matrix_q[0][2]<=c02;
            matrix_q[1][0]<=c10; matrix_q[1][1]<=c11; matrix_q[1][2]<=c12;
            matrix_q[2][0]<=c20; matrix_q[2][1]<=c21; matrix_q[2][2]<=c22;
        end
    end
    // 首像素前递块：NBA保存矩阵尚未生效时，乘法直接取外部新端口。
    // invalid sof既不采样也不前递；普通像素只取当前帧保存矩阵。
    always_comb begin
        for (int row=0; row<3; row++) for (int col=0; col<3; col++)
            effective[row][col]=matrix_q[row][col];
        if (in_valid && in_sof) begin
            effective[0][0]=c00; effective[0][1]=c01; effective[0][2]=c02;
            effective[1][0]=c10; effective[1][1]=c11; effective[1][2]=c12;
            effective[2][0]=c20; effective[2][1]=c21; effective[2][2]=c22;
        end
    end
    // 像素符号块：添加零符号位，再转signed；2048..4095必须仍为正数。
    assign pixel_signed[0]=$signed({1'b0,in_r});
    assign pixel_signed[1]=$signed({1'b0,in_g});
    assign pixel_signed[2]=$signed({1'b0,in_b});
    // 静态展开九个硬件乘法与符号扩展连线，两侧操作数均signed。
    // PRODUCT_W赋值上下文保留完整13+16位；任何加法前先扩宽所有乘积。
    for (genvar row=0; row<3; row++) begin : g_rows
        for (genvar col=0; col<3; col++) begin : g_columns
            assign product_d[row][col]=pixel_signed[col]*effective[row][col];
            assign extended[row][col]=$signed({{(ACC_W-PRODUCT_W){product_q[row][col][PRODUCT_W-1]}},product_q[row][col]});
        end
        assign pair_sum[row]=extended[row][0]+extended[row][1];
        assign accumulator[row]=pair_sum[row]+extended[row][2];
    end
    // Stage 1 R通道乘积寄存块：保存本行三个完整signed乘积。
    always_ff @(posedge clk) begin
        if (!rst_n) begin product_q[0][0]<='0; product_q[0][1]<='0; product_q[0][2]<='0; end
        else if (in_valid) begin
            product_q[0][0]<=product_d[0][0]; product_q[0][1]<=product_d[0][1]; product_q[0][2]<=product_d[0][2];
        end
    end
    // Stage 1 G通道乘积寄存块：保存本行三个完整signed乘积。
    always_ff @(posedge clk) begin
        if (!rst_n) begin product_q[1][0]<='0; product_q[1][1]<='0; product_q[1][2]<='0; end
        else if (in_valid) begin
            product_q[1][0]<=product_d[1][0]; product_q[1][1]<=product_d[1][1]; product_q[1][2]<=product_d[1][2];
        end
    end
    // Stage 1 B通道乘积寄存块：保存本行三个完整signed乘积。
    always_ff @(posedge clk) begin
        if (!rst_n) begin product_q[2][0]<='0; product_q[2][1]<='0; product_q[2][2]<='0; end
        else if (in_valid) begin
            product_q[2][0]<=product_d[2][0]; product_q[2][1]<=product_d[2][1]; product_q[2][2]<=product_d[2][2];
        end
    end
    // Stage 2组合数值块：负/零先钳位，正累加才加偏置并算术右移。
    // 上限比较保持ACC_W位，避免舍入到4096后截断回绕成0。
    always_comb begin
        for (int row=0; row<3; row++) begin
            clamped[row]='0; rounded_sum[row]='0; scaled[row]='0;
            if (accumulator[row]>0) begin
                rounded_sum[row]=accumulator[row]+ROUND_BIAS;
                scaled[row]=rounded_sum[row] >>> FRAC_W;
                if (scaled[row]>MAX_PIXEL) clamped[row]={RGB_W{1'b1}};
                else clamped[row]=scaled[row][RGB_W-1:0];
            end
        end
    end
    // Stage 2载荷寄存块：有效时登记最终RGB，无效时保持旧载荷。
    always_ff @(posedge clk) begin
        if (!rst_n) begin out_r<='0; out_g<='0; out_b<='0; end
        else if (stage1_valid) begin out_r<=clamped[0]; out_g<=clamped[1]; out_b<=clamped[2]; end
    end
    // 坐标寄存块：第一级与输入使能一致，第二级与乘积有效位一致。
    always_ff @(posedge clk) begin
        if (!rst_n) begin stage1_x<='0; stage1_y<='0; out_x<='0; out_y<='0; end
        else begin
            if (in_valid) begin stage1_x<=in_x; stage1_y<=in_y; end
            if (stage1_valid) begin out_x<=stage1_x; out_y<=stage1_y; end
        end
    end
    // 有效位寄存块：两位表示流水占用，busy覆盖最后输出有效拍。
    always_ff @(posedge clk) begin
        if (!rst_n) begin stage1_valid<=0; out_valid<=0; end
        else begin stage1_valid<=in_valid; out_valid<=stage1_valid; end
    end
    // 帧标志寄存块：每级使用对应valid限定，invalid输入干扰不外泄。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            stage1_sof<=0; stage1_eol<=0; stage1_done<=0;
            out_sof<=0; out_eol<=0; out_frame_done<=0;
        end else begin
            stage1_sof<=in_valid && in_sof; stage1_eol<=in_valid && in_eol;
            stage1_done<=in_valid && in_frame_done;
            out_sof<=stage1_valid && stage1_sof; out_eol<=stage1_valid && stage1_eol;
            out_frame_done<=stage1_valid && stage1_done;
        end
    end
endmodule
