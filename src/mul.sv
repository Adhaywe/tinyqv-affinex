module mul #
    (
        parameter WIDTH = 16
    )
    (
        input  logic                      clk_i,
        input  logic                      rst_n,
        input  logic                      start_i,
        input  logic signed [WIDTH-1:0]   a_i, b_i,
        output logic signed [2*WIDTH-1:0] result_o,
        output logic                      busy_o
    );
    
        logic signed [2*WIDTH-1:0] acc_reg;
        logic signed [WIDTH-1:0] a_abs, b_abs;
        logic signed [WIDTH-1:0] multiplicand;
        logic signed [WIDTH-1:0] multiplier;
        logic [$clog2(WIDTH+1)-1:0] count;
        logic busy;
        logic sign;
    
        assign busy_o = busy;
        assign a_abs  = (a_i[WIDTH-1]) ? -a_i : a_i;
        assign b_abs  = (b_i[WIDTH-1]) ? -b_i : b_i;
    
        always_ff @(posedge clk_i or negedge rst_n) begin
            if (!rst_n) begin
                acc_reg <= 0;
                multiplicand <= 0;
                multiplier <= 0;
                result_o <= 0;
                count <= 0;
                busy <= 0;
                sign <= 0;
            end else begin
                if (start_i && !busy) begin
                    sign         <= a_i[WIDTH-1] ^ b_i[WIDTH-1];
                    acc_reg      <= 0;
                    multiplicand <= a_abs;
                    multiplier   <= b_abs;
                    count        <= 0;
                    busy         <= 1;
                end else if (busy) begin
                    if (multiplier[0])
                        acc_reg <= acc_reg + (multiplicand <<< count);
                    multiplier <= multiplier >> 1;
                    count <= count + 1;

                    if (count == WIDTH-1) begin
                        result_o <= sign ? -acc_reg : acc_reg;
                        busy <= 0;
                    end
                end
            end
        end
    endmodule
