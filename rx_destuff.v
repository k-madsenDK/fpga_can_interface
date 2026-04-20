// rx_destuff.v — CAN bit destuffer
//
// Input: rå bits fra bit_timing (én bit pr. sample_pulse)
// Output: un-stuffede bits til frame_fsm
//
// Regel: efter 5 ens bits i træk er næste bit et "stuff-bit" der skal droppes.
// Hvis 6 ens bits i træk ses → bit-stuff-fejl.
// Stuffing gælder kun når 'stuff_enable' er høj (fra SOF til CRC).
// Ved stuff_enable=0 (fra CRC-del og frem): pass-through, ingen destuffing.
//
// Svarer til unstuf_pull_bits() i can2040.c, men bit-for-bit i stedet for
// 32-bit ord.

module rx_destuff (
    input  wire clk,
    input  wire rst,

    input  wire bit_tick,        // 1-cycle puls: 'bit_in' er gyldig denne cycle
    input  wire bit_in,          // rå bit fra bit_timing.rx_sample
    input  wire stuff_enable,    // 1 = bit-stuff gælder, 0 = pass-through

    output reg  out_tick,        // 1-cycle puls: 'out_bit' er gyldig
    output reg  out_bit,         // unstuffed bit

    output reg  stuff_error      // pulser 1 cycle ved 6-ens-bits fejl
);

    reg [2:0] same_count;        // 1..5 (antal ens bits inkl. nuværende)
    reg       last_bit;          // forrige bit (for sammenligning)
    reg       expect_stuff;      // 1 = næste bit er et stuff-bit der skal droppes

    always @(posedge clk) begin
        out_tick     <= 1'b0;
        stuff_error  <= 1'b0;

        if (rst) begin
            same_count    <= 3'd1;
            last_bit      <= 1'b1;    // idle = recessive
            expect_stuff  <= 1'b0;
        end else if (bit_tick) begin

            if (!stuff_enable) begin
                // Pass-through mode (fra CRC-del og frem): ingen destuffing
                out_bit      <= bit_in;
                out_tick     <= 1'b1;
                // Reset state så næste gang stuff_enable går høj, starter vi rent
                same_count   <= 3'd1;
                last_bit     <= bit_in;
                expect_stuff <= 1'b0;

            end else if (expect_stuff) begin
                // Dette bit er et stuff-bit — drop det, men tjek polariteten
                if (bit_in == last_bit) begin
                    // 6 ens bits i træk — fejl!
                    stuff_error <= 1'b1;
                end
                // Nulstil: stuff-bittet er nu "forrige bit" for næste count
                same_count   <= 3'd1;
                last_bit     <= bit_in;
                expect_stuff <= 1'b0;
                // Ingen out_tick — vi svelger stuff-bittet

            end else begin
                // Normal bit — aflever det og opdater tæller
                out_bit  <= bit_in;
                out_tick <= 1'b1;

                if (bit_in == last_bit) begin
                    if (same_count == 3'd4) begin
                        // Vi har nu set 5 ens bits — næste skal være stuff
                        same_count   <= 3'd5;      // bare for synlighed i waveform
                        expect_stuff <= 1'b1;
                    end else begin
                        same_count <= same_count + 1'b1;
                    end
                end else begin
                    // Flanke — nulstil tæller
                    same_count <= 3'd1;
                    last_bit   <= bit_in;
                end
            end
        end
    end

endmodule
