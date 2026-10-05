module saturation #(
    parameter int IN_W  = 20,
    parameter int OUT_W = 12
) (
    input  logic signed [IN_W-1:0] in_value,
    output logic        [OUT_W-1:0] out_value
);
    localparam logic signed [IN_W-1:0] MAX_VALUE = (1 <<< OUT_W) - 1;
    always_comb begin
        if (in_value < 0) out_value = '0;
        else if (in_value > MAX_VALUE) out_value = {OUT_W{1'b1}};
        else out_value = in_value[OUT_W-1:0];
    end
endmodule
