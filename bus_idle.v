// bus_idle.v — tracker CAN bus idle-periode.
// Efter en dominant bit skal vi se ≥11 sammenhængende recessive sample_pulse'er
// før bus_idle går høj (dvs. vi må starte SOF).
//
// Matcher can2040's krav: 7 bits EOF + 3 bits IFS + 1 buffer = 11 recessive bits.

module bus_idle #(
    parameter IDLE_BITS = 11
) (
    input  wire clk,
    input  wire rst,
    input  wire sample_pulse,     // fra bit_timing, fyrer hver bit-tid
    input  wire rx_sample,         // sampled rx-bit (1=recessive, 0=dominant)
    output reg  bus_idle
);
    localparam CW = $clog2(IDLE_BITS+1);
    reg [CW-1:0] cnt;

    always @(posedge clk) begin
        if (rst) begin
            cnt      <= 0;
            bus_idle <= 1'b0;
        end else if (sample_pulse) begin
            if (!rx_sample) begin
                cnt      <= 0;
                bus_idle <= 1'b0;
            end else if (cnt == IDLE_BITS) begin
                bus_idle <= 1'b1;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end
endmodule
