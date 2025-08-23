/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

 `default_nettype none

 // Change the name of this module to something that reflects its functionality and includes your name for uniqueness
 // For example tqvp_yourname_spi for an SPI peripheral.
 // Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
 module tqvp_affinex
(
     input          clk,            // Clock - the TinyQV project clock is normally set to 64MHz.
     input          rst_n,          // Reset_n - low to reset.

     input  [7:0]   ui_in,          // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                    // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

     output [7:0]   uo_out,         // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                    // Note that uo_out[0] is normally used for UART TX.

     input  [5:0]   address,        // Address within this peripheral's address space
     input  [31:0]  data_in,        // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

     // Data read and write requests from the TinyQV core.
     input  [1:0]   data_write_n,   // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
     input  [1:0]   data_read_n,    // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits

     output [31:0]  data_out,       // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
     output         data_ready,

     output         user_interrupt  // Dedicated interrupt request for this peripheral
 );


     // registers
     logic        [ 2:0] control;
     logic               status;

     logic signed [15:0] a;
     logic signed [15:0] b;
     logic signed [15:0] d;
     logic signed [15:0] e;
     logic signed [15:0] tx;
     logic signed [15:0] ty;



     logic signed [15:0] in_x;
     logic signed [15:0] in_y;

     logic signed [15:0] out_x;
     logic signed [15:0] out_y;

     logic rd_enable;
     logic out_valid;

     // multiplication
     logic signed [31:0] res_mul1;
     logic signed [31:0] res_mul2;
     logic signed [31:0] res_ax;
     logic signed [31:0] res_bx;
     logic signed [31:0] res_dx;
     logic signed [31:0] res_ex;
     logic signed [31:0] res_by;
     logic signed [31:0] res_ey;
     logic               busy_mul;
     logic               busy_mul1;
     logic               busy_mul2;


     assign busy_mul = busy_mul1 || busy_mul2;



     // memory mapped register addresses
     localparam ADDR_CONTROL   = 6'h00; // Control
     localparam ADDR_STATUS    = 6'h04; // Status
     localparam ADDR_A         = 6'h08;
     localparam ADDR_B         = 6'h0C;
     localparam ADDR_D         = 6'h10;
     localparam ADDR_E         = 6'h14;
     localparam ADDR_TX        = 6'h18;
     localparam ADDR_TY        = 6'h1C;
     localparam ADDR_XIN       = 6'h20; // Single input X
     localparam ADDR_YIN       = 6'h24; // Single input Y
     localparam ADDR_XOUT      = 6'h28; // Output X
     localparam ADDR_YOUT      = 6'h2C; // Output Y
     localparam ADDR_FIFO_XIN  = 6'h30; // FIFO input X
     localparam ADDR_FIFO_YIN  = 6'h34; // FIFO input Y
     //localparam ADDR_FIFO_XOUT = 6'h38; // FIFO output X
     //localparam ADDR_FIFO_YOUT = 6'h3C; // FIFO output Y


     // FSM

     typedef enum logic [3:0] {
        IDLE          = 4'd0,
        READ          = 4'd1,
        COMPUTE1      = 4'd2,
        COMPUTE1_WAIT = 4'd3,
        COMPUTE2      = 4'd4,
        COMPUTE2_WAIT = 4'd5,
        ADD           = 4'd6,
        WRITE         = 4'd7
     } state_t;

     state_t currentState, nextState;

     always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
           currentState <= IDLE;
        else
           currentState <= nextState;
     end


     always_comb begin
        nextState = currentState;

        case(currentState)
            IDLE:   if (control[0]) begin
                        nextState = COMPUTE1;
                    end

            READ:          nextState = COMPUTE1;

            COMPUTE1:      nextState = COMPUTE1_WAIT;

            COMPUTE1_WAIT: if (!busy_mul) begin
                              nextState = COMPUTE2;
            end

            COMPUTE2:      nextState = COMPUTE2_WAIT;

            COMPUTE2_WAIT: if (!busy_mul) begin
                              nextState = ADD;
            end

            ADD:           nextState = WRITE;

            WRITE:         nextState = IDLE;

            default: ;
        endcase
     end


     //write logic
     always_ff @(posedge clk or negedge rst_n) begin
         if (!rst_n) begin
             control    <= 0;
             a          <= 0;
             b          <= 0;
             d          <= 0;
             e          <= 0;
             tx         <= 0;
             ty         <= 0;
             in_x       <= 0;
             in_y       <= 0;

         end
         else if (data_write_n != 2'b11) begin
            case(address)
                ADDR_CONTROL:  control <= data_in[2:0];
                ADDR_A      :        a <= data_in[15:0];
                ADDR_B      :        b <= data_in[15:0];
                ADDR_D      :        d <= data_in[15:0];
                ADDR_E      :        e <= data_in[15:0];
                ADDR_TX     :       tx <= data_in[15:0];
                ADDR_TY     :       ty <= data_in[15:0];
                ADDR_XIN    :     in_x <= data_in[15:0];
                ADDR_YIN    :     in_y <= data_in[15:0];
                default     : ;
            endcase
             end
        end


    // computation
     always_ff @(posedge clk or negedge rst_n) begin
         if (!rst_n) begin
             out_x      <= 0;
             out_y      <= 0;
             out_valid  <= 0;

         end
         else begin
            case (currentState)
                IDLE:begin;
                end

                READ: begin;
                    //fifo_x_reg <= fifo_in_x_dout;
                    //fifo_y_reg <= fifo_in_y_dout;
                end

                COMPUTE1: begin
                    res_ax <= res_mul1;
                    res_dx <= res_mul2;
                end


                COMPUTE2: begin
                    res_by  <= res_mul1;
                    res_ey  <= res_mul2;
                end

                ADD: begin
                    // final addition and shift for single-point mode
                    if (control[0] == 1'b1) begin
                        out_x <= (res_ax >>> 8) + (res_by >>> 8) + tx;
                        out_y <= (res_dx >>> 8) + (res_ey >>> 8) + ty;
                    end
                end

                WRITE: begin
                    out_valid <= 1;
                end

                default: ;
            endcase


         end
        end

        //assign out_wr_en = (currentState == WRITE) && (!control[0]);
        //assign rd_enable = (currentState == READ) && (!control[0]);



        // Control signals for the multi-cycle multipliers
        logic mul_sel;
        logic start_mul;
        assign start_mul = (currentState == COMPUTE1) || (currentState == COMPUTE2);
        assign mul_sel   = (currentState == COMPUTE1) ? 1'b0 : 1'b1;

        logic signed [15:0] op_a1;
        assign op_a1 = mul_sel ? b : a;

        logic signed [15:0] op_b1;
        assign op_b1 = mul_sel ? (control[0] == 1'b1 ? in_y : 0) : (control[0] == 1'b1 ? in_x : 0);

        logic signed [15:0] op_a2;
        assign op_a2 = mul_sel ? e : d;

        logic signed [15:0] op_b2;
        assign op_b2 = mul_sel ? (control[0] == 1'b1 ? in_y : 0) : (control[0] == 1'b1 ? in_x : 0);


        // MUL instantiation

        mul #
        (
            .WIDTH(16)
        )
        mul1
        (
            .clk_i    ( clk       ),
            .rst_n    ( rst_n     ),
            .start_i  ( start_mul ),
            .a_i      ( op_a1     ),
            .b_i      ( op_b1     ),
            .result_o ( res_mul1  ),
            .busy_o   ( busy_mul1 )
        );

        mul #
        (
            .WIDTH(16)
        )
        mul2
        (
            .clk_i    ( clk       ),
            .rst_n    ( rst_n     ),
            .start_i  ( start_mul ),
            .a_i      ( op_a2     ),
            .b_i      ( op_b2     ),
            .result_o ( res_mul2  ),
            .busy_o   ( busy_mul2 )
        );




     assign data_out = (address == ADDR_CONTROL)   ? {29'b0, control}:
                       (address == ADDR_STATUS)    ? {31'b0, status} :
                       //(address == ADDR_A)         ? a :
                       //(address == ADDR_B)         ? b :
                       //(address == ADDR_D)         ? d :
                       //(address == ADDR_E)         ? e :
                       //(address == ADDR_TX)        ? tx:
                       //(address == ADDR_TY)        ? ty:
                       //(address == ADDR_XIN)       ? in_x:
                       //(address == ADDR_YIN)       ? in_y:
                       (address == ADDR_XOUT)      ? out_x:
                       (address == ADDR_YOUT)      ? out_y:
                       //(address == ADDR_FIFO_XOUT) ? fifo_out_x_reg:
                       //(address == ADDR_FIFO_YOUT) ? fifo_out_y_reg:
                       32'd0;



     assign data_ready     = 1'b1;
     assign status         = out_valid ? 1'b1 : 1'b0;
     assign user_interrupt = 1'b0;
     assign uo_out[7:0]    = 8'h00;

     wire _unused = &{ui_in[7:0], data_read_n, 1'b0};

 endmodule
/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

 `default_nettype none

 // Change the name of this module to something that reflects its functionality and includes your name for uniqueness
 // For example tqvp_yourname_spi for an SPI peripheral.
 // Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
 module tqvp_affinex
(
     input          clk,            // Clock - the TinyQV project clock is normally set to 64MHz.
     input          rst_n,          // Reset_n - low to reset.

     input  [7:0]   ui_in,          // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                    // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

     output [7:0]   uo_out,         // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                    // Note that uo_out[0] is normally used for UART TX.

     input  [5:0]   address,        // Address within this peripheral's address space
     input  [31:0]  data_in,        // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

     // Data read and write requests from the TinyQV core.
     input  [1:0]   data_write_n,   // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
     input  [1:0]   data_read_n,    // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits

     output [31:0]  data_out,       // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
     output         data_ready,

     output         user_interrupt  // Dedicated interrupt request for this peripheral
 );


     // registers
     logic        [ 2:0] control;
     logic               status;

     logic signed [15:0] a;
     logic signed [15:0] b;
     logic signed [15:0] d;
     logic signed [15:0] e;
     logic signed [15:0] tx;
     logic signed [15:0] ty;
     logic signed [15:0] op_a;
     logic signed [15:0] op_b;



     logic signed [15:0] in_x;
     logic signed [15:0] in_y;

     logic signed [15:0] out_x;
     logic signed [15:0] out_y;


     logic out_valid;

     // multiplication
     logic signed [31:0] res_mul;
     logic signed [31:0] res_ax;
     logic signed [31:0] res_dx;
     logic signed [31:0] res_by;
     logic signed [31:0] res_ey;

     logic         [1:0] mult_stage;


     // memory mapped register addresses
     localparam ADDR_CONTROL   = 6'h00; // Control
     localparam ADDR_STATUS    = 6'h04; // Status
     localparam ADDR_A         = 6'h08;
     localparam ADDR_B         = 6'h0C;
     localparam ADDR_D         = 6'h10;
     localparam ADDR_E         = 6'h14;
     localparam ADDR_TX        = 6'h18;
     localparam ADDR_TY        = 6'h1C;
     localparam ADDR_XIN       = 6'h20; // Single input X
     localparam ADDR_YIN       = 6'h24; // Single input Y
     localparam ADDR_XOUT      = 6'h28; // Output X
     localparam ADDR_YOUT      = 6'h2C; // Output Y

     // FSM
     typedef enum logic [1:0] {
        IDLE          = 2'd0,
        MULT          = 2'd1,
        ADD_SHIFT     = 2'd2,
        DONE          = 2'd3
     } state_t;

     state_t currentState, nextState;

     always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
           currentState <= IDLE;
        else
           currentState <= nextState;
     end

     always_comb begin
        nextState = currentState;

        case(currentState)
            IDLE:   if (control[0])
                        nextState = MULT;

            MULT:   if (mult_stage == 3)
                       nextState = ADD_SHIFT;

            ADD_SHIFT: nextState = DONE;

            DONE:      nextState = IDLE;

            default: ;
        endcase
     end


     //write logic
     always_ff @(posedge clk or negedge rst_n) begin
         if (!rst_n) begin
             control    <= 0;
             a          <= 0;
             b          <= 0;
             d          <= 0;
             e          <= 0;
             tx         <= 0;
             ty         <= 0;
             in_x       <= 0;
             in_y       <= 0;

         end
         else if (data_write_n != 2'b11) begin
            case(address)
                ADDR_CONTROL:  control <= data_in[2:0];
                ADDR_A      :        a <= data_in[15:0];
                ADDR_B      :        b <= data_in[15:0];
                ADDR_D      :        d <= data_in[15:0];
                ADDR_E      :        e <= data_in[15:0];
                ADDR_TX     :       tx <= data_in[15:0];
                ADDR_TY     :       ty <= data_in[15:0];
                ADDR_XIN    :     in_x <= data_in[15:0];
                ADDR_YIN    :     in_y <= data_in[15:0];
                default     : ;
            endcase
             end
        end


    // computation
     always_ff @(posedge clk or negedge rst_n) begin
         if (!rst_n) begin
             res_ax     <= 0;
             res_by     <= 0;
             res_dx     <= 0;
             res_ey     <= 0;
             mult_stage <= 0;
             out_x      <= 0;
             out_y      <= 0;
             out_valid  <= 0;
         end
         else begin
            case (currentState)
                IDLE:begin;
                end

                MULT: begin
                    case(mult_stage)
                        0: begin
                            res_ax     <= res_mul;
                            mult_stage <= mult_stage + 1;
                        end

                        1: begin
                            res_by     <= res_mul;
                            mult_stage <= mult_stage + 1;
                        end

                        2: begin
                            res_dx     <= res_mul;
                            mult_stage <= mult_stage + 1;
                        end

                        3: begin
                            res_ey     <= res_mul;
                            mult_stage <= mult_stage + 1;
                        end

                        default: ;
                    endcase
                end

                ADD_SHIFT: begin
                        out_x <= (res_ax >>> 8) + (res_by >>> 8) + tx;
                        out_y <= (res_dx >>> 8) + (res_ey >>> 8) + ty;
                    end

                DONE: begin
                    if (mult_stage == 3)
                       out_valid <= 1;
                    else
                       out_valid <= 0;
                end

                default: ;
            endcase


         end
        end

        // multiplier operands
        assign op_a = (mult_stage == 0) ? a :
                      (mult_stage == 1) ? b :
                      (mult_stage == 2) ? d :
                                          e ;

        assign op_b = (mult_stage == 0) ? in_x :
                      (mult_stage == 1) ? in_y :
                      (mult_stage == 2) ? in_x :
                                          in_y ;


        // MUL instantiation
        mul #
        (
            .WIDTH(16)
        )
        mul1
        (
            .a_i      ( op_a                 ),
            .b_i      ( op_b                 ),
            .result_o ( res_mul              )
        );



     assign data_out = (address == ADDR_CONTROL)   ? {29'b0, control}:
                       (address == ADDR_STATUS)    ? {31'b0, status} :
                       (address == ADDR_XOUT)      ? out_x:
                       (address == ADDR_YOUT)      ? out_y:
                       32'd0;



     assign data_ready     = 1'b1;
     assign status         = out_valid ? 1'b1 : 1'b0;
     assign user_interrupt = 1'b0;
     assign uo_out[7:0]    = 8'h00;

     wire _unused = &{ui_in[7:0], data_read_n, 1'b0};

 endmodule
