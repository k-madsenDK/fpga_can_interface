// bit_timing.v ��� CAN bit-timing generator med hard-sync
//
// 100 MHz sys_clk → CAN bit-takt.
// sample_pulse fyrer ved 75% af bittet; tx_pulse ved start af bittet.
// Hard-sync på ENHVER recessive→dominant flanke (CAN-standard: kun 1→0).

module bit_timing #(
    parameter SYS_CLK_HZ = 100_000_000,
    parameter BITRATE    = 125_000,
    parameter TQ_PER_BIT = 16,
    parameter SAMPLE_TQ  = 12      // sample point: 12/16 = 75%
) (
    input  wire clk,
    input  wire rst,
    input  wire rx_bit,            // synkroniseret can_rx
    input  wire tx_active,         // <-- NY: høj mens FPGA selv sender

    output reg  sample_pulse,
    output reg  tx_pulse,
    output reg  rx_sample
);

    localparam integer CLKS_PER_TQ = SYS_CLK_HZ / (BITRATE * TQ_PER_BIT);
    localparam integer TQ_CTR_W    = $clog2(CLKS_PER_TQ);
    localparam integer BIT_CTR_W   = $clog2(TQ_PER_BIT);

    reg [TQ_CTR_W-1:0]  tq_counter;
    reg [BIT_CTR_W-1:0] bit_counter;

    // Flanke-detektion
    reg rx_prev;
    wire falling_edge = rx_prev & ~rx_bit;   // recessive(1) → dominant(0)

    // For at undgå at re-syncere når vi LIGE har re-synchroniseret
    // (dvs. hvis vi allerede står på bit_counter=0, tq_counter lille):
    wire near_start = (bit_counter == 0) && (tq_counter < CLKS_PER_TQ/4);

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

            if (falling_edge && !near_start) begin
                // --- Hard-sync: denne flanke ER starten af et nyt bit ---
                tq_counter  <= 0;
                bit_counter <= 0;
                // Ingen tx/sample puls denne cycle
            end else begin
                // --- Normal fri tælling ---
                if (tq_counter == CLKS_PER_TQ - 1) begin
                    tq_counter <= 0;

                    if (bit_counter == TQ_PER_BIT - 1) begin
                        bit_counter <= 0;
                        tx_pulse    <= 1'b1;     // start af nyt bit
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
