// SRAM 帧读取器：请求地址和同步返回数据分别推进，无反压、连续一拍一个像素。
// 三段式 FSM 的第三段按配置、请求、返回和流输出分别建寄存器块。
module sram_reader #(
    parameter int ADDR_W  = 20, // SRAM 地址位宽；测试用 8 位覆盖容量边界。
    parameter int PIXEL_W = 12  // 16 位 SRAM 字中的有效低位数，取值 1..16。
) (
    // 时钟/复位模块：所有寄存器均在上升沿更新；rst_n 为同步低有效复位。
    input  logic               clk,
    input  logic               rst_n,

    // 帧控制模块：仅空闲时接受 start 上升沿，尺寸随接受事件锁存。
    // busy 包含请求、返回排空以及最后像素所在周期，随后一周期清零。
    input  logic               start,
    input  logic [15:0]        image_width,
    input  logic [15:0]        image_height,
    output logic               busy,

    // SRAM 模块：无读使能。地址在当前沿之后更新，SRAM 于下一沿采样；
    // sram_rdata 是 SRAM 的寄存返回值，reader 再在随后一个沿消费。
    output logic [ADDR_W-1:0]  sram_addr,
    input  logic [15:0]        sram_rdata,

    // RAW 像素流模块：仅 pixel_valid=1 时数据与 16 位坐标有效，无 ready。
    // sof 标记首像素，eol 标记行末，frame_done 与最后像素同时置位。
    output logic               pixel_valid,
    output logic [PIXEL_W-1:0] pixel_data,
    output logic [15:0]        pixel_x,
    output logic [15:0]        pixel_y,
    output logic               sof,
    output logic               eol,
    output logic               frame_done
);
    // ISSUE 发出请求，DRAIN 消费最后返回，FINISH 保留最后输出周期的 busy。
    typedef enum logic [1:0] {IDLE, ISSUE, DRAIN, FINISH} state_t;
    state_t state_q, state_d;

    logic start_q, start_rise, accept_start, dimensions_nonzero, frame_fits;
    logic [31:0] requested_pixels;
    localparam logic [63:0] ADDRESS_CAPACITY = 64'd1 << ADDR_W;

    // 预先锁存行/帧终点，像素热路径仅有计数器加一和相等比较，无除法或乘法。
    logic [15:0] last_x_q, last_y_q;
    logic [15:0] request_x_q, request_y_q;
    logic request_last;

    // 与 SRAM 同沿寄存的请求元数据；下一沿与 SRAM 返回值一起转为像素流。
    logic pending_valid_q, pending_sof_q, pending_eol_q, pending_last_q;
    logic [15:0] pending_x_q, pending_y_q;

    // 容量资格检查仅用于启动，不位于逐像素数据路径。显式拓宽乘法操作数，
    // 避免 16 位尺寸乘积在比较地址容量之前被截断；硬件拒绝非法大帧。
    assign requested_pixels = {16'd0, image_width} * {16'd0, image_height};
    assign dimensions_nonzero = (image_width != 0) && (image_height != 0);
    assign frame_fits = ({32'd0, requested_pixels} <= ADDRESS_CAPACITY);
    assign start_rise = start && !start_q;
    assign accept_start = (state_q == IDLE) && start_rise &&
                          dimensions_nonzero && frame_fits;
    assign request_last = (request_x_q == last_x_q) &&
                          (request_y_q == last_y_q);

    // FSM 第一段：仅管理当前状态寄存器。
    always_ff @(posedge clk) begin
        if (!rst_n)
            state_q <= IDLE;
        else
            state_q <= state_d;
    end

    // FSM 第二段：完整默认赋值避免锁存器；最后请求和最后输出分属不同状态。
    always_comb begin
        state_d = state_q;
        case (state_q)
            IDLE:   if (accept_start) state_d = ISSUE;
            ISSUE:  if (request_last) state_d = DRAIN;
            DRAIN:  state_d = FINISH;
            FINISH: state_d = IDLE;
            default: state_d = IDLE;
        endcase
    end

    // 启动边沿历史始终更新，包括 busy 期间，防止忙时保持高电平在结束后重启。
    always_ff @(posedge clk) begin
        if (!rst_n)
            start_q <= 1'b0;
        else
            start_q <= start;
    end

    // FSM 第三段之一：配置寄存器只在合法启动时改变，帧中尺寸输入可任意变化。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            last_x_q <= '0;
            last_y_q <= '0;
        end else if (accept_start) begin
            last_x_q <= image_width - 16'd1;
            last_y_q <= image_height - 16'd1;
        end
    end

    // FSM 第三段之二：请求侧地址/坐标同步推进。最后请求后保持地址，
    // 不增加到容量之外；下一帧启动清零，因此地址容量恰好满帧也不会回绕。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sram_addr <= '0;
            request_x_q <= '0;
            request_y_q <= '0;
        end else if (accept_start) begin
            sram_addr <= '0;
            request_x_q <= '0;
            request_y_q <= '0;
        end else if ((state_q == ISSUE) && !request_last) begin
            sram_addr <= sram_addr + 1'b1;
            if (request_x_q == last_x_q) begin
                request_x_q <= '0;
                request_y_q <= request_y_q + 16'd1;
            end else begin
                request_x_q <= request_x_q + 16'd1;
            end
        end
    end

    // FSM 第三段之三：每个 ISSUE 沿保存一次请求有效位和元数据。
    // 非 ISSUE 周期清除有效位，SRAM 虽仍返回旧地址数据也不会形成多余像素。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pending_valid_q <= 1'b0;
            pending_x_q <= '0;
            pending_y_q <= '0;
            pending_sof_q <= 1'b0;
            pending_eol_q <= 1'b0;
            pending_last_q <= 1'b0;
        end else begin
            pending_valid_q <= (state_q == ISSUE);
            if (state_q == ISSUE) begin
                pending_x_q <= request_x_q;
                pending_y_q <= request_y_q;
                pending_sof_q <= (request_x_q == 0) && (request_y_q == 0);
                pending_eol_q <= (request_x_q == last_x_q);
                pending_last_q <= request_last;
            end
        end
    end

    // FSM 第三段之四：返回数据及坐标寄存器。这里消费前一沿的 pending 和
    // sram_rdata，绝不把当前刚发出的地址对应到旧数据；无效周期保持载荷。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pixel_data <= '0;
            pixel_x <= '0;
            pixel_y <= '0;
        end else if (pending_valid_q) begin
            pixel_data <= sram_rdata[PIXEL_W-1:0];
            pixel_x <= pending_x_q;
            pixel_y <= pending_y_q;
        end
    end

    // FSM 第三段之五：有效标志统一由返回有效位限定，无效周期全部归零。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pixel_valid <= 1'b0;
            sof <= 1'b0;
            eol <= 1'b0;
            frame_done <= 1'b0;
        end else begin
            pixel_valid <= pending_valid_q;
            sof <= pending_valid_q && pending_sof_q;
            eol <= pending_valid_q && pending_eol_q;
            frame_done <= pending_valid_q && pending_last_q;
        end
    end

    // busy 独立寄存，避免由多位状态组合译码产生毛刺；最后输出后的沿才清零。
    always_ff @(posedge clk) begin
        if (!rst_n)
            busy <= 1'b0;
        else if (accept_start)
            busy <= 1'b1;
        else if (state_q == FINISH)
            busy <= 1'b0;
    end

    // 仅仿真诊断，综合时整个块被排除；上面的 frame_fits 拒绝逻辑始终是硬件。
    // 不使用 function、initial 初始化或不可综合结构实现任何功能路径。
    // synopsys translate_off
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && (state_q == IDLE) && start_rise &&
            dimensions_nonzero && !frame_fits)
            $fatal(1, "SRAM_FRAME_TOO_LARGE: pixels=%0d capacity=%0d",
                   requested_pixels, ADDRESS_CAPACITY);
    end
`endif
    // synopsys translate_on
endmodule
