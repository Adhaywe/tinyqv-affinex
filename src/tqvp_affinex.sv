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
     logic               control, status;
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
     logic signed [31:0] acc_x;
     logic signed [31:0] acc_y;

     logic         [1:0] mult_stage;
     logic               done, start, busy;

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
        start = 1'b0;

        case(currentState)
            IDLE:   if (control)
                        nextState = MULT;

            MULT:   if (mult_stage == 3 && done)
                       nextState = ADD_SHIFT;
                    else if (!busy)
                       start = 1'b1;

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
                ADDR_CONTROL:  control <= data_in[0];
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
             acc_x      <= 0;
             acc_y      <= 0;
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
                    if (done) begin
                        case(mult_stage)
                            0: begin
                                acc_x      <= res_mul;
                                //mult_stage <= mult_stage + 1;
                            end

                            1: begin
                                acc_x      <= acc_x + res_mul;
                                //mult_stage <= mult_stage + 1;
                            end

                            2: begin
                                acc_y      <= res_mul;
                                //mult_stage <= mult_stage + 1;
                            end

                            3: begin
                                acc_y      <= acc_y + res_mul;
                                //mult_stage <= mult_stage + 1;
                            end

                            default: ;
                        endcase
                        mult_stage <= mult_stage + 1;
                    end
                end

                ADD_SHIFT: begin
                        out_x <= (acc_x >>> 8) + tx;
                        out_y <= (acc_y >>> 8) + ty;
                    end

                DONE: begin
                     out_valid <= 1;
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
            .clk      ( clk                  ),
            .rst_n    ( rst_n                ),
            .start    ( start    ),
            .a_i      ( op_a                 ),
            .b_i      ( op_b                 ),
            .result_o ( res_mul              ),
            .done     ( done                 ),
            .busy     ( busy                 )
        );



     assign data_out = (address == ADDR_CONTROL)   ? {31'b0, control}:
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