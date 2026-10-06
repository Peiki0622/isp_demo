`timescale 1ns/1ps
// 窗口公开接口验收：独立整帧 oracle 只存在于测试平台，不读取 DUT 内部。
module tb_window_3x3;
    // 时钟/同步复位与完整输入流；下降沿驱动，上升沿 NBA 后检查。
    logic clk = 0, rst_n = 0, in_valid = 0, in_sof = 0, in_eol = 0, in_frame_done = 0;
    logic [11:0] in_pixel = 0;
    logic [15:0] in_x = 0, in_y = 0, frame_width = 2, frame_height = 2;
    always #5 clk = ~clk;
    // 公开窗口/控制接口：数组仅用于 scoreboard 统一检查九个端口。
    logic out_valid, out_sof, out_eol, out_frame_done, busy;
    logic [15:0] center_x, center_y;
    wire [11:0] actual [0:8];
    logic [11:0] raw [0:16383];
    int frames = 0, checked = 0;
    string selected_case;
    window_3x3 dut (
        // 时钟、有效输入载荷及坐标。
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_pixel(in_pixel), .in_x(in_x), .in_y(in_y),
        // 输入标志和稳定尺寸。
        .in_sof(in_sof), .in_eol(in_eol), .in_frame_done(in_frame_done),
        .frame_width(frame_width), .frame_height(frame_height),
        // 九个样本、输出中心和有效位。
        .p00(actual[0]), .p01(actual[1]), .p02(actual[2]),
        .p10(actual[3]), .p11(actual[4]), .p12(actual[5]),
        .p20(actual[6]), .p21(actual[7]), .p22(actual[8]),
        .center_x(center_x), .center_y(center_y), .out_valid(out_valid),
        // 重建输出标志和完整忙状态。
        .out_sof(out_sof), .out_eol(out_eol), .out_frame_done(out_frame_done), .busy(busy)
    );
    task automatic tick;
        @(posedge clk); #1ps;
    endtask
    task automatic idle;
        if ({busy,out_valid,out_sof,out_eol,out_frame_done} !== 5'b0)
            $fatal(1, "WINDOW_UNIT idle activity");
    endtask
    // oracle 的边界映射直接由外部尺寸计算，与 DUT 行角色和调度无关。
    function automatic int reflected(input int c, input int length);
        if (c < 0) return -c;
        if (c >= length) return 2*length-2-c;
        return c;
    endfunction
    task automatic prepare(input int w, input int h, input int pattern);
        for (int i=0; i<w*h; i++) begin
            case (pattern)
                0: raw[i] = 0;
                1: raw[i] = 4095;
                2: raw[i] = ((i/w)%2) ? ((i%w)%2 ? 4095 : 2001) : ((i%w)%2 ? 2001 : 17);
                3: raw[i] = 12'((i*313 + (i/w)*1237 + frames*97) ^ (i*37));
                default: raw[i] = 12'(i%7);
            endcase
        end
    endtask
    // 精确检查九个样本及坐标、标志；任何 X/Z 都由 case inequality 拒绝。
    task automatic check_sample(input int index, input int w, input int h);
        int x, y, rx, ry;
        x=index%w; y=index/w;
        if (center_x !== 16'(x) || center_y !== 16'(y))
            $fatal(1, "WINDOW_UNIT coordinates index=%0d xy=%0d,%0d",index,center_x,center_y);
        for (int k=0; k<9; k++) begin
            rx=reflected(x+k%3-1,w); ry=reflected(y+k/3-1,h);
            if (actual[k] !== raw[ry*w+rx])
                $fatal(1,"WINDOW_UNIT index=%0d sample=%0d expected=%h actual=%h",index,k,raw[ry*w+rx],actual[k]);
        end
        if (out_sof !== (index==0) || out_eol !== (x==w-1) || out_frame_done !== (index==w*h-1))
            $fatal(1,"WINDOW_UNIT flags index=%0d",index);
        checked++;
    endtask
    // 输入首像素采样沿记作 cycle0。首窗口必须是 W+1，末窗口 N+W，
    // 其间没有气泡；从输入 EOF 后仍有 W+1 个窗口，末有效拍保持 busy。
    task automatic run_frame(input int w, input int h, input int pattern);
        int n, count, sofs, eols, dones;
        logic [107:0] previous_payload;
        n=w*h; count=0; sofs=0; eols=0; dones=0;
        prepare(w,h,pattern);
        for (int cycle=0; cycle<=n+w+2; cycle++) begin
            @(negedge clk);
            frame_width=16'(w); frame_height=16'(h);
            in_valid=(cycle<n); in_sof=(cycle==0);
            in_eol=(cycle<n && cycle%w==w-1); in_frame_done=(cycle==n-1);
            if (in_valid) begin in_x=16'(cycle%w); in_y=16'(cycle/w); in_pixel=raw[cycle]; end
            // 无效标志干扰不可形成新帧事件；输入尺寸在 sof 后也作扰动，
            // 验证本模块保存的终点供窗口及尾部使用。
            if (cycle>=n) begin in_sof=1; in_eol=1; in_frame_done=1; end
            if (cycle>0) begin frame_width=65535; frame_height=0; end
            previous_payload={actual[0],actual[1],actual[2],actual[3],actual[4],actual[5],actual[6],actual[7],actual[8]};
            #1ps;
            if ({actual[0],actual[1],actual[2],actual[3],actual[4],actual[5],actual[6],actual[7],actual[8]} !== previous_payload)
                $fatal(1,"WINDOW_UNIT combinational output bypass");
            tick();
            if (busy !== (cycle<=n+w) || out_valid !== (cycle>=w+1 && cycle<=n+w))
                $fatal(1,"WINDOW_UNIT timing %0dx%0d C%0d busy=%b valid=%b",w,h,cycle,busy,out_valid);
            if (out_valid) begin
                check_sample(count,w,h); count++;
                sofs+=int'(out_sof); eols+=int'(out_eol); dones+=int'(out_frame_done);
            end else if ({out_sof,out_eol,out_frame_done} !== 3'b0)
                $fatal(1,"WINDOW_UNIT invalid flags");
        end
        if (count!=n || sofs!=1 || eols!=h || dones!=1) $fatal(1,"WINDOW_UNIT counts");
        frames++;
    endtask
    // 在预热、正常输出、尾部各中止一次。行数组不清零，重启使用不同
    // 尺寸/内容，检查元数据与窗口有效门控足以防止上一帧泄漏。
    task automatic abort_frame(input int stop_cycle);
        prepare(8,6,3);
        for (int cycle=0; cycle<=stop_cycle; cycle++) begin
            @(negedge clk);
            frame_width=8; frame_height=6; in_valid=(cycle<48); in_sof=(cycle==0);
            in_eol=(cycle<48 && cycle%8==7); in_frame_done=(cycle==47);
            if (in_valid) begin in_x=16'(cycle%8); in_y=16'(cycle/8); in_pixel=raw[cycle]; end
            tick();
        end
        @(negedge clk); rst_n=0; in_valid=0; in_sof=0; in_eol=0; in_frame_done=0;
        tick(); idle();
        if ({actual[0],actual[1],actual[2],actual[3],actual[4],actual[5],actual[6],actual[7],actual[8],center_x,center_y} !== '0)
            $fatal(1,"WINDOW_UNIT reset payload");
        @(negedge clk); rst_n=1; repeat(3) begin tick(); idle(); end
        run_frame(3,5,4);
    endtask
    task automatic rejected(input int w,input int h);
        @(negedge clk); frame_width=16'(w); frame_height=16'(h);
        in_valid=1; in_sof=1; in_x=0; in_y=0; in_eol=0; in_frame_done=0;
        tick(); idle();
        @(negedge clk); in_valid=0; in_sof=0; tick(); idle();
    endtask
    initial begin
        selected_case="regression"; void'($value$plusargs("CASE=%s",selected_case));
        repeat(3) begin tick(); idle(); end
        @(negedge clk); rst_n=1; tick(); idle();
        case (selected_case)
            "forced_failure": $fatal(1,"WINDOW_UNIT_FORCED_FAILURE");
            "invalid_width": begin rejected(4097,2); $fatal(1,"WINDOW_DIMENSION_DIAGNOSTIC_MISSING"); end
            "invalid_small": begin rejected(1,2); $fatal(1,"WINDOW_DIMENSION_DIAGNOSTIC_MISSING"); end
            "invalid_height": begin rejected(2,1); $fatal(1,"WINDOW_DIMENSION_DIAGNOSTIC_MISSING"); end
            "dimension_reject": begin
                rejected(0,2); rejected(1,2); rejected(2,0); rejected(2,1); rejected(4097,2);
                run_frame(2,2,3);
            end
            "overlap": begin
                @(negedge clk); in_valid=1; in_sof=1; tick();
                @(negedge clk); tick(); $fatal(1,"WINDOW_OVERLAP_DIAGNOSTIC_MISSING");
            end
            "regression": begin
                run_frame(2,2,3); run_frame(3,2,4); run_frame(2,3,3); run_frame(3,5,3); run_frame(4,4,3);
                for(int w=2;w<=8;w++) for(int h=2;h<=8;h++) run_frame(w,h,3);
                for(int pattern=0;pattern<5;pattern++) run_frame(6,7,pattern);
                run_frame(4095,3,3); run_frame(4096,2,3);
                abort_frame(0); abort_frame(11); abort_frame(50);
            end
            default: $fatal(1,"WINDOW_UNIT unknown case");
        endcase
        $display("[CASE] window frames=%0d checked=%0d samples=%0d",frames,checked,checked*9);
        $display("[PASS] WINDOW_UNIT"); $finish;
    end
    initial begin #2000000; $fatal(1,"WINDOW_UNIT_TIMEOUT"); end
endmodule
