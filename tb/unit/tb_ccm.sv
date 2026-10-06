`timescale 1ns/1ps
// CCM公开接口单测：独立longint oracle，不读取DUT矩阵、乘积或累加器。
module tb_ccm;
    // 时钟/复位模块：下降沿驱动，上升沿NBA后检查，避免竞争隐藏错拍。
    logic clk=0, rst_n=0;
    always #5 clk=~clk;
    // 输入载荷与帧控制：所有坐标和侧带也进入独立流水scoreboard。
    logic in_valid=0, in_sof=0, in_eol=0, in_done=0;
    logic [11:0] in_r=0, in_g=0, in_b=0;
    logic [15:0] in_x=0, in_y=0;
    // 外部矩阵为测试整数；端口转换显式保留signed16补码语义。
    int external_matrix [0:2][0:2], saved_matrix [0:2][0:2];
    wire signed [15:0] coefficient [0:2][0:2];
    for (genvar r=0;r<3;r++) for (genvar c=0;c<3;c++)
        assign coefficient[r][c]=16'(external_matrix[r][c]);
    // 输出模块：仅观察公开载荷、坐标、标志和busy。
    wire [11:0] actual [0:2];
    logic out_valid,out_sof,out_eol,out_done,busy;
    logic [15:0] out_x,out_y;
    // 第一级期望保存上一采样像素。第二个采样沿应输出它，对应两个寄存级。
    bit pending_valid=0,pending_sof=0,pending_eol=0,pending_done=0;
    int pending_rgb [0:2];
    logic [15:0] pending_x,pending_y;
    int cycles=0,pixels=0;
    int boundary [0:5]='{0,1,2047,2048,4094,4095};
    string selected_case;
    ccm dut (
        // 时钟、RGB载荷、坐标及输入帧标志。
        .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_r(in_r),.in_g(in_g),.in_b(in_b),
        .in_x(in_x),.in_y(in_y),.in_sof(in_sof),.in_eol(in_eol),.in_frame_done(in_done),
        // 九个独立signed系数，行列次序必须与数学定义一致。
        .c00(coefficient[0][0]),.c01(coefficient[0][1]),.c02(coefficient[0][2]),
        .c10(coefficient[1][0]),.c11(coefficient[1][1]),.c12(coefficient[1][2]),
        .c20(coefficient[2][0]),.c21(coefficient[2][1]),.c22(coefficient[2][2]),
        // 两级最终输出，没有内部信号或层次访问。
        .out_r(actual[0]),.out_g(actual[1]),.out_b(actual[2]),.out_x(out_x),.out_y(out_y),
        .out_valid(out_valid),.out_sof(out_sof),.out_eol(out_eol),.out_frame_done(out_done),.busy(busy)
    );
    task automatic tick;
        @(posedge clk); #1ps;
    endtask
    // 测试oracle允许function；其longint逐项计算与RTL乘积宽度/偏置实现独立。
    function automatic int corrected(input int r,input int g,input int b,input int row);
        longint total,quotient,remainder;
        total=longint'(r)*longint'(saved_matrix[row][0])+
              longint'(g)*longint'(saved_matrix[row][1])+
              longint'(b)*longint'(saved_matrix[row][2]);
        if (total<=0) return 0;
        quotient=total/4096; remainder=total%4096;
        if (remainder>=2048) quotient++;
        return (quotient>4095) ? 4095 : int'(quotient);
    endfunction
    // 模型矩阵仅按本次驱动valid+sof更新；先比较旧pending，再计算新pending。
    // 输出期望不会由DUT valid/busy自适应，因此延迟、丢点和旁路都会失败。
    task automatic sample(input int r,input int g,input int b,input bit valid,
                          input bit first,input bit line_end,input bit last);
        logic [71:0] previous_public;
        @(negedge clk);
        in_r=12'(r);in_g=12'(g);in_b=12'(b);in_valid=valid;
        in_sof=first;in_eol=line_end;in_done=last;
        in_x=16'(cycles*313);in_y=16'(cycles*947);
        previous_public={actual[0],actual[1],actual[2],out_x,out_y,out_valid,out_sof,out_eol,out_done};
        #1ps;
        if ({actual[0],actual[1],actual[2],out_x,out_y,out_valid,out_sof,out_eol,out_done} !== previous_public)
            $fatal(1,"CCM_UNIT combinational output bypass");
        tick();
        if (out_valid !== pending_valid || busy !== (valid || pending_valid))
            $fatal(1,"CCM_UNIT cycle=%0d valid/busy alignment",cycles);
        if (pending_valid) begin
            for (int row=0;row<3;row++) if (actual[row] !== 12'(pending_rgb[row]))
                $fatal(1,"CCM_UNIT cycle=%0d channel=%0d expected=%0d actual=%h",cycles,row,pending_rgb[row],actual[row]);
            if (out_x !== pending_x || out_y !== pending_y ||
                {out_sof,out_eol,out_done} !== {pending_sof,pending_eol,pending_done})
                $fatal(1,"CCM_UNIT coordinate/flag alignment");
            pixels++;
        end else if ({out_sof,out_eol,out_done} !== 3'b0)
            $fatal(1,"CCM_UNIT invalid flags");
        if (valid && first) for (int row=0;row<3;row++) for (int col=0;col<3;col++)
            saved_matrix[row][col]=external_matrix[row][col];
        pending_valid=valid;pending_sof=first;pending_eol=line_end;pending_done=last;
        pending_x=in_x;pending_y=in_y;
        if (valid) for (int row=0;row<3;row++) pending_rgb[row]=corrected(r,g,b,row);
        cycles++;
    endtask
    // 复位独立清空scoreboard。外部矩阵故意可保持坏配置，非SOF输入应仍identity。
    task automatic reset_pipeline;
        @(negedge clk);rst_n=0;in_valid=0;in_sof=0;in_eol=0;in_done=0;
        tick();
        if ({actual[0],actual[1],actual[2],out_x,out_y,out_valid,out_sof,out_eol,out_done,busy} !== '0)
            $fatal(1,"CCM_UNIT reset did not clear pipeline");
        pending_valid=0;
        for (int row=0;row<3;row++) for (int col=0;col<3;col++)
            saved_matrix[row][col]=(row==col)?4096:0;
        @(negedge clk);rst_n=1;
    endtask
    // 11组矩阵覆盖方向、fractional、signed抵消及全部编码极值。
    task automatic matrix_profile(input int profile);
        for (int row=0;row<3;row++) for (int col=0;col<3;col++) external_matrix[row][col]=0;
        case (profile)
            0: begin // identity：固定两级，精确恢复高位RGB正数。
                external_matrix[0][0]=4096; external_matrix[0][1]=0; external_matrix[0][2]=0;
                external_matrix[1][0]=0; external_matrix[1][1]=4096; external_matrix[1][2]=0;
                external_matrix[2][0]=0; external_matrix[2][1]=0; external_matrix[2][2]=4096;
            end
            1: begin // zero：验证全零也不旁路有效位。
                external_matrix[0][0]=0; external_matrix[0][1]=0; external_matrix[0][2]=0;
                external_matrix[1][0]=0; external_matrix[1][1]=0; external_matrix[1][2]=0;
                external_matrix[2][0]=0; external_matrix[2][1]=0; external_matrix[2][2]=0;
            end
            2: begin // R/B交换：检查通道连接，另用非对称矩阵排除转置。
                external_matrix[0][0]=0; external_matrix[0][1]=0; external_matrix[0][2]=4096;
                external_matrix[1][0]=0; external_matrix[1][1]=4096; external_matrix[1][2]=0;
                external_matrix[2][0]=4096; external_matrix[2][1]=0; external_matrix[2][2]=0;
            end
            3: begin // 矩阵C：大于一和负系数，三项累加覆盖fractional。
                external_matrix[0][0]=5120; external_matrix[0][1]=-512; external_matrix[0][2]=-512;
                external_matrix[1][0]=-256; external_matrix[1][1]=4608; external_matrix[1][2]=-256;
                external_matrix[2][0]=-512; external_matrix[2][1]=-512; external_matrix[2][2]=5120;
            end
            4: begin // 矩阵D：显式上饱和与负值下钳位。
                external_matrix[0][0]=8192; external_matrix[0][1]=0; external_matrix[0][2]=0;
                external_matrix[1][0]=0; external_matrix[1][1]=-4096; external_matrix[1][2]=8192;
                external_matrix[2][0]=-4096; external_matrix[2][1]=0; external_matrix[2][2]=8192;
            end
            5: begin // 非对称矩阵：三个输出手算不同，矩阵转置会失败。
                external_matrix[0][0]=4096; external_matrix[0][1]=2048; external_matrix[0][2]=0;
                external_matrix[1][0]=0; external_matrix[1][1]=4096; external_matrix[1][2]=-1024;
                external_matrix[2][0]=1024; external_matrix[2][1]=0; external_matrix[2][2]=4096;
            end
            6: begin // 三个0.5对角系数：half-up中点与两侧。
                external_matrix[0][0]=2048; external_matrix[0][1]=0; external_matrix[0][2]=0;
                external_matrix[1][0]=0; external_matrix[1][1]=2048; external_matrix[1][2]=0;
                external_matrix[2][0]=0; external_matrix[2][1]=0; external_matrix[2][2]=2048;
            end
            7: begin // +1.5/-0.5混合：宽位符号传播与抵消。
                external_matrix[0][0]=6144; external_matrix[0][1]=-2048; external_matrix[0][2]=0;
                external_matrix[1][0]=-2048; external_matrix[1][1]=6144; external_matrix[1][2]=0;
                external_matrix[2][0]=0; external_matrix[2][1]=-2048; external_matrix[2][2]=6144;
            end
            8: begin // 全部最大32767：完整正乘积及三项和保护位。
                external_matrix[0][0]=32767; external_matrix[0][1]=32767; external_matrix[0][2]=32767;
                external_matrix[1][0]=32767; external_matrix[1][1]=32767; external_matrix[1][2]=32767;
                external_matrix[2][0]=32767; external_matrix[2][1]=32767; external_matrix[2][2]=32767;
            end
            9: begin // 全部最小-32768：负乘积符号扩展和下钳位。
                external_matrix[0][0]=-32768; external_matrix[0][1]=-32768; external_matrix[0][2]=-32768;
                external_matrix[1][0]=-32768; external_matrix[1][1]=-32768; external_matrix[1][2]=-32768;
                external_matrix[2][0]=-32768; external_matrix[2][1]=-32768; external_matrix[2][2]=-32768;
            end
            10: begin // 32767/-32768/+1：高幅乘积抵消，和为零或接近零。
                external_matrix[0][0]=32767; external_matrix[0][1]=-32768; external_matrix[0][2]=1;
                external_matrix[1][0]=32767; external_matrix[1][1]=-32768; external_matrix[1][2]=1;
                external_matrix[2][0]=32767; external_matrix[2][1]=-32768; external_matrix[2][2]=1;
            end
            default: $fatal(1,"CCM_UNIT invalid profile");
        endcase
    endtask
    initial begin
        selected_case="regression";void'($value$plusargs("CASE=%s",selected_case));
        reset_pipeline();
        if (selected_case=="forced_failure") $fatal(1,"CCM_UNIT_FORCED_FAILURE");
        if (selected_case!="regression") $fatal(1,"CCM_UNIT unknown case");
        // 高位输入在reset identity下且没有SOF：外部zero不得污染默认矩阵。
        matrix_profile(1);sample(2048,4095,2047,1,0,1,1);sample(0,0,0,0,1,1,1);
        // 六个RGB边界值的216种组合，各矩阵一帧，逐通道完整检查。
        for (int profile=0;profile<11;profile++) begin
            matrix_profile(profile);
            for(int r=0;r<6;r++) for(int g=0;g<6;g++) for(int b=0;b<6;b++)
                sample(boundary[r],boundary[g],boundary[b],1,r==0 && g==0 && b==0,b==5,r==5 && g==5 && b==5);
        end
        sample(0,0,0,0,1,1,1);sample(0,0,0,0,1,1,1);
        // 非对称手算(1000,2000,3000)->(2000,1250,3250)，能排除矩阵转置。
        matrix_profile(5);sample(1000,2000,3000,1,1,1,1);
        if (pending_rgb[0]!=2000 || pending_rgb[1]!=1250 || pending_rgb[2]!=3250)
            $fatal(1,"CCM_UNIT hand oracle mismatch");
        // 中点上下、整数边界、正累加1及舍入到4096后饱和。
        for(int code=2047;code<=2049;code++) begin
            matrix_profile(1);for(int row=0;row<3;row++) external_matrix[row][0]=code;
            sample(1,0,0,1,1,1,1);
        end
        for(int code=4095;code<=4097;code++) begin
            matrix_profile(1);for(int row=0;row<3;row++) external_matrix[row][0]=code;
            sample(4095,0,0,1,1,1,1);
        end
        // 全4096个R值、反向G和置换B；首像素后每拍扰动全部九个外部系数。
        matrix_profile(3);
        for(int i=0;i<4096;i++) begin
            if(i>0) for(int row=0;row<3;row++) for(int col=0;col<3;col++)
                external_matrix[row][col]=int'($signed(16'(i*997+row*1237+col*619)));
            sample(i,4095-i,(i*313+127)%4096,1,i==0,i%64==63,i==4095);
        end
        // valid hole + invalid SOF不能采样；后续无SOF像素仍使用C。
        matrix_profile(4);sample(0,0,0,0,1,1,1);sample(72,18,54,1,0,1,1);
        // 连续单像素帧逐拍更新不同矩阵，不能用busy阻断SOF。
        for(int i=0;i<11;i++) begin matrix_profile(i);sample(1000,2000,3000,1,1,1,1);end
        sample(0,0,0,0,0,0,0);sample(0,0,0,0,0,0,0);
        // 分别在Stage1非空及Stage2有效时复位，随后无SOF输入验证identity恢复。
        matrix_profile(4);sample(4095,2048,1,1,1,0,0);reset_pipeline();
        sample(4095,2048,1,1,0,1,1);sample(0,0,0,0,1,1,1);reset_pipeline();
        sample(1,2048,4095,1,0,1,1);sample(0,0,0,0,0,0,0);sample(0,0,0,0,0,0,0);
        $display("[CASE] CCM cycles=%0d pixels=%0d channels=%0d",cycles,pixels,pixels*3);
        $display("[PASS] CCM_UNIT");$finish;
    end
    initial begin #2000000;$fatal(1,"CCM_UNIT_TIMEOUT");end
endmodule
