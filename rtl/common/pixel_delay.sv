module pixel_delay #(
    parameter int W = 12,
    parameter int N = 1
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         in_valid,
    input  logic [W-1:0] in_data,
    output logic         out_valid,
    output logic [W-1:0] out_data
);
    logic [W-1:0] data_pipe [0:N-1];
    logic valid_pipe [0:N-1];
    integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) begin data_pipe[i] <= '0; valid_pipe[i] <= 1'b0; end
        end else begin
            data_pipe[0] <= in_data; valid_pipe[0] <= in_valid;
            for (i = 1; i < N; i = i + 1) begin data_pipe[i] <= data_pipe[i-1]; valid_pipe[i] <= valid_pipe[i-1]; end
        end
    end
    assign out_data = data_pipe[N-1];
    assign out_valid = valid_pipe[N-1];
endmodule
