// crc15.v — CAN CRC-15 shift register (LUT-Optimeret)
//
// Polynom:  x^15 + x^14 + x^10 + x^8 + x^7 + x^4 + x^3 + 1  = 0x4599
// Startværdi: 0
// Opdateres pr. "rent" (unstuffed) bit.

module crc15 (
    input  wire        clk,
    input  wire        rst,         // synkron reset, active high
    input  wire        init,        // puls: nulstil crc til 0
    input  wire        bit_valid,   // puls: bit_in er gyldig denne cycle
    input  wire        bit_in,      // det unstuffede bit

    output wire [14:0] crc          // nuværende CRC-15 værdi
);

    reg [14:0] crc_reg;

    // Ved hvert bit: feedback = crc_reg[14] XOR indgangsbit
    wire feedback = crc_reg[14] ^ bit_in;

    // --- HARDWARE UNROLLING AF 0x4599 POLYNOMET ---
    // Vi hardkoder ledningerne for at undgå at syntesen bygger en 15-bit Multiplexer.
    // Bits sat i 0x4599: 0, 3, 4, 7, 8, 10, 14
    wire [14:0] next_crc;
    
    assign next_crc[0]  = feedback;
    assign next_crc[1]  = crc_reg[0];
    assign next_crc[2]  = crc_reg[1];
    assign next_crc[3]  = crc_reg[2] ^ feedback;
    assign next_crc[4]  = crc_reg[3] ^ feedback;
    assign next_crc[5]  = crc_reg[4];
    assign next_crc[6]  = crc_reg[5];
    assign next_crc[7]  = crc_reg[6] ^ feedback;
    assign next_crc[8]  = crc_reg[7] ^ feedback;
    assign next_crc[9]  = crc_reg[8];
    assign next_crc[10] = crc_reg[9] ^ feedback;
    assign next_crc[11] = crc_reg[10];
    assign next_crc[12] = crc_reg[11];
    assign next_crc[13] = crc_reg[12];
    assign next_crc[14] = crc_reg[13] ^ feedback;

    always @(posedge clk) begin
        if (rst || init)
            crc_reg <= 15'h0000;
        else if (bit_valid)
            crc_reg <= next_crc;
    end

    assign crc = crc_reg;

endmodule
