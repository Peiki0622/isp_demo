// 流式 reflect 窗口：三行轮转存储，输出全尺寸 3x3 邻域，不提供反压。
module window_3x3 #(
    parameter int PIXEL_W = 12,  // P4 行存储和窗口样本为 RAW12。
    parameter int MAX_WIDTH = 4096 // 静态行容量；帧首在硬件中检查。
) (
    // 时钟/复位模块：同步低有效复位中止处理及 tail，不复位行数组。
    input logic clk,
    input logic rst_n,
    // 输入载荷模块：从 (0,0) 连续逐拍光栅输入，没有 ready。
    input logic in_valid,
    input logic [PIXEL_W-1:0] in_pixel,
    input logic [15:0] in_x, in_y,
    // 输入帧标志模块：有效 sof 开帧，eol 轮转，frame_done 开始排空。
    // 标志受 in_valid 限定；下一帧只能在 busy=0 时进入。
    input logic in_sof, in_eol, in_frame_done,
    // 稳定尺寸模块：来自 top 在合法 start 时保存的尺寸；在有效 sof
    // 再保存终点供尾部使用，不能直接使用会在帧中变化的外部 image_*。
    input logic [15:0] frame_width, frame_height,
    // 窗口载荷模块：pRC 是邻域第 R 行、第 C 列，p11 对应中心。
    // 九个样本和中心坐标在同沿寄存，out_valid 限定其有效性。
    output logic out_valid,
    output logic [PIXEL_W-1:0] p00, p01, p02,
    output logic [PIXEL_W-1:0] p10, p11, p12,
    output logic [PIXEL_W-1:0] p20, p21, p22,
    output logic [15:0] center_x, center_y,
    // 输出帧控制模块：由中心重建标志，无效拍清零；busy 覆盖预热、
    // 正常处理、W+1 个 tail 窗口及最后一个有效输出周期。
    output logic out_sof, out_eol, out_frame_done,
    output logic busy
);
    typedef enum logic [1:0] {IDLE, STREAM, TAIL_RIGHT, TAIL_LAST} state_t;
    state_t state_q, state_d;
    logic dimensions_legal, accept_frame, write_pixel, emit;
    logic [15:0] last_x_q, last_y_q, tail_x_q, emit_x, emit_y;
    // 三个角色保存当前行、前一行和前两行。仅交换 bank 索引，不复制行，
    // 不在像素路径上计算 y%3，也不保存整帧。
    logic [1:0] write_bank_q, previous_bank_q, older_bank_q;
    logic [PIXEL_W-1:0] rows [0:2][0:MAX_WIDTH-1];
    logic [1:0] read_bank [0:2];
    logic [15:0] read_col [0:2];
    logic [2:0] incoming_row;
    logic [PIXEL_W-1:0] samples [0:2][0:2];
    assign dimensions_legal = frame_width >= 2 && frame_height >= 2 &&
                              {16'd0, frame_width} <= 32'(MAX_WIDTH);
    assign busy = (state_q != IDLE) || out_valid;
    assign accept_frame = (state_q == IDLE) && !out_valid && in_valid &&
                          in_sof && dimensions_legal;
    assign write_pixel = accept_frame || ((state_q == STREAM) && in_valid && !in_sof);

    // 三段式 FSM 第一段：状态寄存器单独更新。
    always_ff @(posedge clk) begin
        if (!rst_n) state_q <= IDLE;
        else        state_q <= state_d;
    end
    // 第二段：完整默认赋值。尾部没有等待态，确保窗口逐拍连续输出。
    always_comb begin
        state_d = state_q;
        case (state_q)
            IDLE:       if (accept_frame) state_d = STREAM;
            STREAM:     if (write_pixel && in_frame_done) state_d = TAIL_RIGHT;
            TAIL_RIGHT: state_d = TAIL_LAST;
            TAIL_LAST:  if (tail_x_q == last_x_q) state_d = IDLE;
            default:    state_d = IDLE;
        endcase
    end
    // 第三段之一：配置终点只在有效 sof 保存，窗口预热后使用保存值。
    always_ff @(posedge clk) begin
        if (!rst_n) begin last_x_q <= '0; last_y_q <= '0; end
        else if (accept_frame) begin
            last_x_q <= frame_width - 16'd1;
            last_y_q <= frame_height - 16'd1;
        end
    end
    // 第三段之二：只在非末行有效 eol 轮转。最终三个角色保持到 tail 结束。
    always_ff @(posedge clk) begin
        if (!rst_n || accept_frame) begin
            write_bank_q <= 0; previous_bank_q <= 2; older_bank_q <= 1;
        end else if (write_pixel && in_eol && !in_frame_done) begin
            write_bank_q <= older_bank_q;
            previous_bank_q <= write_bank_q;
            older_bank_q <= previous_bank_q;
        end
    end
    // 第三段之三：尾行列计数器独立于已经结束的输入流。
    always_ff @(posedge clk) begin
        if (!rst_n || accept_frame) tail_x_q <= '0;
        else if (state_q == TAIL_LAST && tail_x_q != last_x_q)
            tail_x_q <= tail_x_q + 16'd1;
    end
    // 行数组同步写块：不使用数组复位循环。首像素强制写 bank0，防止
    // 上一帧角色残留。非阻塞写允许同沿读取覆盖前旧行，最新点显式前递。
    always_ff @(posedge clk) begin
        if (rst_n && write_pixel)
            rows[accept_frame ? 2'd0 : write_bank_q][in_x] <= in_pixel;
    end
    // 调度和行地址块：常规中心是输入的左上一点；新行 x=0 补右边界，
    // 此时 write_bank 中的旧上邻行必须先读后覆盖，尤其是宽度为 2 时。
    // 顶边反射到第二行，底边反射到倒数第二行，保持 Bayer 奇偶相位。
    always_comb begin
        emit = 1'b0; emit_x = '0; emit_y = '0;
        read_bank[0] = older_bank_q;
        read_bank[1] = previous_bank_q;
        read_bank[2] = write_bank_q;
        incoming_row = 3'b000;
        case (state_q)
            STREAM: begin
                // 已收到右下邻点：中心是输入的左上一点，底行含当前像素。
                if (write_pixel && in_x >= 1 && in_y >= 1) begin
                    emit = 1'b1; emit_x = in_x - 16'd1; emit_y = in_y - 16'd1;
                    incoming_row = 3'b100;
                    if (in_y == 1) begin
                        // 第一输出行的上邻也镜像到当前输入行，需要相同前递。
                        read_bank[0] = write_bank_q;
                        incoming_row[0] = 1'b1;
                    end
                end else if (write_pixel && in_x == 0 && in_y >= 2) begin
                    // 新行第一列只服务前一输出行的最右中心；写 bank 中的
                    // 旧行 y-3 在本沿读出后才覆盖。y=2 的顶边改读镜像行1。
                    emit = 1'b1; emit_x = last_x_q; emit_y = in_y - 16'd2;
                    read_bank[0] = (in_y == 2) ? previous_bank_q : write_bank_q;
                    read_bank[1] = older_bank_q;
                    read_bank[2] = previous_bank_q;
                end
            end
            TAIL_RIGHT: begin
                // 最后输入像素已输出 (W-2,H-2)，先补 (W-1,H-2)。
                emit = 1'b1; emit_x = last_x_q; emit_y = last_y_q - 16'd1;
                if (last_y_q == 1) read_bank[0] = write_bank_q;
            end
            TAIL_LAST: begin
                // 底边上下邻都取倒数第二行，中心取最后输入行，逐列排空。
                emit = 1'b1; emit_x = tail_x_q; emit_y = last_y_q;
                read_bank[0] = previous_bank_q;
                read_bank[1] = write_bank_q;
                read_bank[2] = previous_bank_q;
            end
            default: begin end
        endcase
    end
    // 列地址/样本选择块：-1->1，W->W-2。当前输入行的当前列前递，
    // 包括顶/左 reflect 的重复引用。emit=0 时不读取尚未建立内容的行。
    always_comb begin
        read_col[0] = (emit_x == 0) ? 16'd1 : emit_x - 16'd1;
        read_col[1] = emit_x;
        read_col[2] = (emit_x == last_x_q) ? last_x_q - 16'd1 : emit_x + 16'd1;
        for (int r = 0; r < 3; r++) begin
            for (int c = 0; c < 3; c++) begin
                samples[r][c] = '0;
                if (emit) begin
                    samples[r][c] = rows[read_bank[r]][read_col[c]];
                    if (write_pixel && incoming_row[r] && read_col[c] == in_x)
                        samples[r][c] = in_pixel;
                end
            end
        end
    end
    // 九个窗口样本寄存块：同沿采样，无效时保持上次有效载荷。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            p00 <= '0; p01 <= '0; p02 <= '0;
            p10 <= '0; p11 <= '0; p12 <= '0;
            p20 <= '0; p21 <= '0; p22 <= '0;
        end else if (emit) begin
            p00 <= samples[0][0]; p01 <= samples[0][1]; p02 <= samples[0][2];
            p10 <= samples[1][0]; p11 <= samples[1][1]; p12 <= samples[1][2];
            p20 <= samples[2][0]; p21 <= samples[2][1]; p22 <= samples[2][2];
        end
    end
    // 中心坐标寄存块：不能直接输出已经前进的输入坐标。
    always_ff @(posedge clk) begin
        if (!rst_n) begin center_x <= '0; center_y <= '0; end
        else if (emit) begin center_x <= emit_x; center_y <= emit_y; end
    end
    // 有效位寄存块：末窗口有效拍仍 busy，随后一个沿解除。
    always_ff @(posedge clk) begin
        if (!rst_n) out_valid <= 1'b0;
        else        out_valid <= emit;
    end
    // 帧标志寄存块：从输出中心重建，不能简单延迟输入 frame_done。
    always_ff @(posedge clk) begin
        if (!rst_n) begin out_sof <= 0; out_eol <= 0; out_frame_done <= 0; end
        else begin
            out_sof <= emit && emit_x == 0 && emit_y == 0;
            out_eol <= emit && emit_x == last_x_q;
            out_frame_done <= emit && emit_x == last_x_q && emit_y == last_y_q;
        end
    end
    // 协议诊断仅用于仿真；综合路径仍保留尺寸资格及写入门控。
    // synopsys translate_off
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && in_valid && in_sof && !busy && !dimensions_legal)
            $fatal(1, "WINDOW_DIMENSIONS_INVALID: %0dx%0d max=%0d", frame_width, frame_height, MAX_WIDTH);
        if (rst_n && in_valid && in_sof && busy) $fatal(1, "WINDOW_FRAME_OVERLAP");
        if (rst_n && state_q == STREAM && !in_valid) $fatal(1, "WINDOW_INPUT_GAP");
    end
`endif
    // synopsys translate_on
endmodule
