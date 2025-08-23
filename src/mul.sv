module mul #
    (
        parameter WIDTH = 16
    )
    (
        input  logic signed [WIDTH-1:0]   a_i, b_i,
        output logic signed [2*WIDTH-1:0] result_o
    );


    assign result_o = $signed(a_i) * $signed(b_i);

    endmodule
