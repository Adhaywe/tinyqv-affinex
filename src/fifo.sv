/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */


module fifo #
(
    parameter DEPTH=8, WIDTH=16
)
(
    input                     rst_n,
    input                     clk_i,
    input                     wr_en_i,
    input                     rd_en_i,
    input        [WIDTH-1:0]  din_i,
    output logic [WIDTH-1:0]  dout_o,
    output                    empty_o,
    output                    full_o
);

    logic [$clog2(DEPTH)-1:0]   wptr, rptr;

    logic [WIDTH-1 : 0]  fifo [DEPTH];

    // fifo write logic
    always @ (posedge clk_i) begin
        if (!rst_n) begin
            wptr <= 0;
        end else begin
        if (wr_en_i & !full_o) begin
            fifo[wptr] <= din_i;
            wptr <= wptr + 1;
        end
        end
    end


    // fifo read logic
    always @ (posedge clk_i) begin
        if (!rst_n) begin
            rptr <= 0;
        end else begin
        if (rd_en_i & !empty_o) begin
            rptr <= rptr + 1;
        end
        end
    end

    assign dout_o = rd_en_i ? fifo[rptr] : 0;
    assign full_o  = (wptr + 1) == rptr;
    assign empty_o = wptr == rptr;

endmodule
