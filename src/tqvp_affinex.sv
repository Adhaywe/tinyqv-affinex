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
     logic        [ 2:0] status;

     logic signed [31:0] a;
     logic signed [31:0] b;
     logic signed [31:0] d;
     logic signed [31:0] e;
     logic signed [31:0] tx;
     logic signed [31:0] ty;



     logic signed [31:0] in_x;
     logic signed [31:0] in_y;

     logic signed [31:0] out_x;
     logic signed [31:0] out_y;

     logic signed [31:0] out_x_bat;
     logic signed [31:0] out_y_bat;

     // fifo signals
     logic signed [31:0] fifo_x_reg, fifo_y_reg;
     logic signed [31:0] fifo_out_x_reg, fifo_out_y_reg;
     logic        fifo_in_x_full, fifo_in_y_full;
     logic        fifo_in_x_empty, fifo_in_y_empty;
     logic        fifo_out_x_full, fifo_out_y_full;
     logic        fifo_out_x_empty, fifo_out_y_empty;
     logic        out_wr_en;
     logic signed [31:0] fifo_in_x_dout, fifo_in_y_dout;

     // temp signals
     logic signed [63:0] tmp_x, tmp_y;
     logic signed [63:0] tmp_xx, tmp_yy;

     logic rd_enable;
     logic out_valid;



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
     localparam ADDR_FIFO_XOUT = 6'h38; // FIFO output X
     localparam ADDR_FIFO_YOUT = 6'h3C; // FIFO output Y


     // FSM

     typedef enum logic [2:0] {
        IDLE    = 3'd0,
        READ    = 3'd1,
        COMPUTE = 3'd2,
        SHIFT   = 3'd3,
        WRITE   = 3'd4,
        WAIT_S  = 3'd5
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
            IDLE:  if (!control[0] && !fifo_in_x_empty && !fifo_in_y_empty
                       && !fifo_out_x_full && !fifo_out_y_full)
                       nextState = READ;

            READ:    nextState = COMPUTE;

            COMPUTE: nextState = SHIFT;

            SHIFT:   nextState = WRITE;

            WRITE:   nextState = WAIT_S;

            WAIT_S: nextState = IDLE;

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
                ADDR_A      :        a <= data_in;
                ADDR_B      :        b <= data_in;
                ADDR_D      :        d <= data_in;
                ADDR_E      :        e <= data_in;
                ADDR_TX     :       tx <= data_in;
                ADDR_TY     :       ty <= data_in;
                ADDR_XIN    :     in_x <= data_in;
                ADDR_YIN    :     in_y <= data_in;
                default     : ;
            endcase
             end
        end

     always_ff @(posedge clk or negedge rst_n) begin
         if (!rst_n) begin
             tmp_x      <= 0;
             tmp_y      <= 0;
             out_x      <= 0;
             out_y      <= 0;
             out_x_bat  <= 0;
             out_y_bat  <= 0;
             tmp_xx     <= 0;
             tmp_yy     <= 0;
             fifo_x_reg <= 0;
             fifo_y_reg <= 0;
             out_valid  <= 0;

         end

         else if (control[0]) begin

             tmp_x  <= (a) * (in_x) + (b) * (in_y);
             tmp_y  <= (d) * (in_x) + (e) * (in_y);

             tmp_xx <= (tmp_x >>> 16);
             tmp_yy <= (tmp_y >>> 16);

             out_x  <= tmp_xx[31:0] + tx;
             out_y  <= tmp_yy[31:0] + ty;
         end
         else begin

            case (currentState)
                IDLE:begin;
                end

                READ: begin
                    fifo_x_reg <= fifo_in_x_dout;
                    fifo_y_reg <= fifo_in_y_dout;
                end

                COMPUTE: begin
                     tmp_x  <= (a) * (fifo_x_reg) + (b) * (fifo_y_reg);
                     tmp_y  <= (d) * (fifo_x_reg) + (e) * (fifo_y_reg);
                end

                SHIFT: begin
                    tmp_xx <= (tmp_x >>> 16);
                    tmp_yy <= (tmp_y >>> 16);
                end

                WRITE: begin
                    out_x_bat  <= tmp_xx[31:0] + tx;
                    out_y_bat  <= tmp_yy[31:0] + ty;
                end

                WAIT_S: begin
                    out_valid <= 1;
                end

                default: ;
            endcase


         end
        end

        assign out_wr_en = (currentState == WAIT_S) && (!control[0]);
        assign rd_enable = (currentState == READ) && (!control[0]);

        // fifo instantiation

        fifo #
        (
            .DEPTH ( 10 ),
            .WIDTH ( 32 )
        )
        fifo_inx
        (
            .rst_n   ( rst_n           ),
            .clk_i   ( clk             ),
            .wr_en_i ( (address == ADDR_FIFO_XIN) && (data_write_n != 2'b11) && (!fifo_in_x_full) ),
            .rd_en_i ( rd_enable       ),
            .din_i   ( data_in         ),
            .dout_o  ( fifo_in_x_dout  ),
            .empty_o ( fifo_in_x_empty ),
            .full_o  ( fifo_in_x_full  )
        );

        fifo #
        (
            .DEPTH ( 10 ),
            .WIDTH ( 32 )
        )
        fifo_iny
        (
            .rst_n   ( rst_n           ),
            .clk_i   ( clk             ),
            .wr_en_i ( (address == ADDR_FIFO_YIN) && (data_write_n != 2'b11) && (!fifo_in_y_full) ),
            .rd_en_i ( rd_enable       ),
            .din_i   ( data_in         ),
            .dout_o  ( fifo_in_y_dout  ),
            .empty_o ( fifo_in_y_empty ),
            .full_o  ( fifo_in_y_full  )
        );

        fifo #
        (
            .DEPTH ( 10 ),
            .WIDTH ( 32 )
        )
        fifo_outx
        (
            .rst_n   ( rst_n            ),
            .clk_i   ( clk              ),
            .rd_en_i ( (address == ADDR_FIFO_XOUT) && (data_read_n != 2'b11) && (!fifo_out_x_empty) ),
            .wr_en_i ( out_wr_en        ),
            .din_i   ( out_x_bat        ),
            .dout_o  ( fifo_out_x_reg   ),
            .empty_o ( fifo_out_x_empty ),
            .full_o  ( fifo_out_x_full  )
        );

        fifo #
        (
            .DEPTH ( 10 ),
            .WIDTH ( 32 )
        )
        fifo_outy
        (
            .rst_n   ( rst_n            ),
            .clk_i   ( clk              ),
            .rd_en_i ( (address == ADDR_FIFO_YOUT) && (data_read_n != 2'b11) && (!fifo_out_y_empty) ),
            .wr_en_i ( out_wr_en        ),
            .din_i   ( out_y_bat        ),
            .dout_o  ( fifo_out_y_reg   ),
            .empty_o ( fifo_out_y_empty ),
            .full_o  ( fifo_out_y_full  )
        );


     assign data_out = (address == ADDR_CONTROL)   ? {29'b0, control}:
                       (address == ADDR_STATUS)    ? {29'b0, status} :
                       (address == ADDR_A)         ? a :
                       (address == ADDR_B)         ? b :
                       (address == ADDR_D)         ? d :
                       (address == ADDR_E)         ? e :
                       (address == ADDR_TX)        ? tx:
                       (address == ADDR_TY)        ? ty:
                       (address == ADDR_XIN)       ? in_x:
                       (address == ADDR_YIN)       ? in_y:
                       (address == ADDR_XOUT)      ? out_x:
                       (address == ADDR_YOUT)      ? out_y:
                       (address == ADDR_FIFO_XOUT) ? fifo_out_x_reg:
                       (address == ADDR_FIFO_YOUT) ? fifo_out_y_reg:
                       32'd0;



     assign data_ready     = 1'b1;
     assign status         = out_valid ? 1'b1 : 1'b0;
     assign user_interrupt = 1'b0;
     assign uo_out[7:0]    = 8'h00;

     wire _unused = &{ui_in[7:0], data_read_n, 1'b0};

 endmodule
