
module mul
    #
    (
        parameter WIDTH = 16
    )
    (
        input  logic               clk,
        input  logic               rst_n,
        input  logic               start,
        input  logic signed [WIDTH-1:0] a_i, b_i,
        output logic signed [2*WIDTH-1:0] result_o,
        output logic               done, busy
    );
    
    // Internal registers
    logic signed [WIDTH-1:0] a_reg, b_reg;
    logic signed [2*WIDTH-1:0] acc;
    logic [5:0]              bit_cnt;
    
    // Control signals
    logic busy_reg, done_reg, start_pipe;
    
    // A pipeline register for the 'start' signal to handle a single-cycle 'start' pulse
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            start_pipe <= 1'b0;
        else
            start_pipe <= start;
    end
    
    // Main logic for the sequential multiplier
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg     <= 0;
            b_reg     <= 0;
            acc       <= 0;
            bit_cnt   <= 0;
            busy_reg  <= 0;
            done_reg  <= 0;
        end
        else begin
            // Pulse done for one cycle when the multiplication is finished
            done_reg <= 1'b0; 
            
            // Start of a new multiplication
            if (start_pipe && !busy_reg) begin
                a_reg     <= a_i;
                b_reg     <= b_i;
                acc       <= 0;
                bit_cnt   <= 0;
                busy_reg  <= 1'b1;
            end
            // Multiplication in progress
            else if (busy_reg) begin
                // Check if the LSB of b_reg is 1
                if (b_reg[0])
                    acc <= acc + (a_reg <<< bit_cnt); // Add shifted a_reg
                
                // Increment bit counter and right shift b_reg
                bit_cnt <= bit_cnt + 1;
                b_reg   <= b_reg >>> 1;
                
                // End condition: When all bits of b_reg have been processed
                if (bit_cnt == WIDTH - 1) begin
                    // Final add for the sign bit
                    busy_reg <= 1'b0;
                    done_reg <= 1'b1;
                end
            end
        end
    end
    
    // Assign outputs
    assign result_o = acc;
    assign done = done_reg;
    assign busy = busy_reg;
    
endmodule
