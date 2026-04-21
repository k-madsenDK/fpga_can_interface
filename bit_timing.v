// bit_timing.v — CAN bit-timing generator med hard-sync
//
// Eksakte timing-parametre @ 100 MHz sys_clk:
//   Bitrate  TQ_PER_BIT  SAMPLE_TQ  CLKS_PER_TQ
//   125 k    16          12         50
//   250 k    16          12         25
//   500 k    20          15         10
//   1 M      10           8         10
//
// sample_pulse fyrer ved SAMPLE_TQ; tx_pulse ved start af bit.
// Hard-sync på recessive→dominant flanker (men ikke når vi selv sender).

module bit_timing #(
    parameter SYS_CLK_HZ = 100_000_000,
    parameter BITRATE    = 125_000,
    parameter TQ_PER_BIT = 16,
    parameter SAMPLE_TQ  = 12
) (
    input  wire clk,
    input  wire rst,
    input  wire rx_bit,
    input  wire tx_active,
    output reg  sample_pulse,
    output reg  tx_pulse,
    output reg  rx_sample
);

    localparam integer CLKS_PER_TQ = SYS_CLK_HZ / (BITRATE * TQ_PER_BIT);
    localparam integer TQ_CTR_W    = $clog2(CLKS_PER_TQ + 1);
    localparam integer BIT_CTR_W   = $clog2(TQ_PER_BIT + 1);

    // Compile-time check: timing skal gå op eksakt
    initial begin
        if (SYS_CLK_HZ != CLKS_PER_TQ * BITRATE * TQ_PER_BIT) begin
            $display("ERROR bit_timing: inexact. SYS_CLK=%0d BITRATE=%0d TQ_PER_BIT=%0d CLKS_PER_TQ=%0d actual_rate=%0d",
                     SYS_CLK_HZ, BITRATE, TQ_PER_BIT, CLKS_PER_TQ,
                     SYS_CLK_HZ / (CLKS_PER_TQ * TQ_PER_BIT));
            $finish;
        end
        if (SAMPLE_TQ >= TQ_PER_BIT) begin
            $display("ERROR bit_timing: SAMPLE_TQ (%0d) must be < TQ_PER_BIT (%0d)",
                     SAMPLE_TQ, TQ_PER_BIT);
            $finish;
        end
    end

    reg [TQ_CTR_W-1:0]  tq_counter;
    reg [BIT_CTR_W-1:0] bit_counter;
    reg rx_prev;

    wire falling_edge = rx_prev & ~rx_bit;
    wire near_start   = (bit_counter == 0) && (tq_counter < CLKS_PER_TQ/4);

    always @(posedge clk) begin
        sample_pulse <= 1'b0;
        tx_pulse     <= 1'b0;

        if (rst) begin
            tq_counter  <= 0;
            bit_counter <= 0;
            rx_prev     <= 1'b1;
            rx_sample   <= 1'b1;
        end else begin
            rx_prev <= rx_bit;

            if (falling_edge && !near_start && !tx_active) begin
                // Hard-sync til flanke (kun når vi IKKE selv sender)
                tq_counter  <= 0;
                bit_counter <= 0;
            end else begin
                if (tq_counter == CLKS_PER_TQ - 1) begin
                    tq_counter <= 0;
                    if (bit_counter == TQ_PER_BIT - 1) begin
                        bit_counter <= 0;
                        tx_pulse    <= 1'b1;
                    end else begin
                        bit_counter <= bit_counter + 1'b1;
                    end
                    if (bit_counter == SAMPLE_TQ - 1) begin
                        sample_pulse <= 1'b1;
                        rx_sample    <= rx_bit;
                    end
                end else begin
                    tq_counter <= tq_counter + 1'b1;
                end
            end
        end
    end
endmodule
