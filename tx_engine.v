// tx_engine.v — CAN transmit engine (frame builder + bit stuffer + CRC)
//
// På 'tx_start'-puls: bygger og sender én CAN-frame.
// Leverer ét bit pr. tx_pulse.
// Bit-stuffing og CRC-15 håndteres automatisk.
//
// Data-konvention:
//   tx_data er LSB-aligneret (samme som rx_data fra rx_frame_fsm).
//   F.eks. for DLC=2, data=[0xCA, 0xFE]: tx_data = 64'h000000000000CAFE
//   Ved DLC=8 bruges alle 64 bits.
//   Intern: tx_engine shifter op til MSB ved frame-start, så S_DATA
//   kan emittere fra bit 63 MSB-først (CAN sender byte 0 først, MSB først).
//
// BEMÆRK: Ingen arbitration-tab-detektion. Vi antager at bussen er ledig
// når tx_start gives.

module tx_engine (
    input  wire         clk,
    input  wire         rst,
    input  wire         tx_pulse,       // fra bit_timing — ét bit-tik
    input  wire         tx_start,       // 1-cycle puls: start ny frame
    input  wire [10:0]  tx_id,
    input  wire [3:0]   tx_dlc,
    input  wire [63:0]  tx_data,        // LSB-aligned

    output reg          tx_bit,         // bit til can_tx (1=recessive, 0=dominant)
    output reg          tx_active,      // høj under hele frame
    output reg          tx_done         // 1-cycle puls når frame er færdig
);

    // ---- States ----
    localparam S_IDLE     = 4'd0;
    localparam S_SOF      = 4'd1;
    localparam S_ID       = 4'd2;
    localparam S_RTR      = 4'd3;
    localparam S_IDE      = 4'd4;
    localparam S_R0       = 4'd5;
    localparam S_DLC      = 4'd6;
    localparam S_DATA     = 4'd7;
    localparam S_CRC      = 4'd8;
    localparam S_CRC_DEL  = 4'd9;
    localparam S_ACK_SLOT = 4'd10;
    localparam S_ACK_DEL  = 4'd11;
    localparam S_EOF      = 4'd12;
    localparam S_IFS      = 4'd13;

    reg [3:0]  state;
    reg [6:0]  bit_counter;

    reg [10:0] id_sr;
    reg [3:0]  dlc_sr;
    reg [63:0] data_sr;
    reg [14:0] crc_acc;
    reg [14:0] crc_sr;
    reg [6:0]  data_bits_total;

    // Bit-stuffing state
    reg [2:0]  same_count;
    reg        last_emitted;
    reg        stuff_pending;

    // ---- Kombinatorisk: hvilken bit vil vi emitte? ----
    reg bit_to_emit;
    reg stuff_active;
    always @(*) begin
        bit_to_emit  = 1'b1;
        stuff_active = 1'b1;
        case (state)
            S_SOF:      bit_to_emit = 1'b0;
            S_ID:       bit_to_emit = id_sr[10];
            S_RTR:      bit_to_emit = 1'b0;
            S_IDE:      bit_to_emit = 1'b0;
            S_R0:       bit_to_emit = 1'b0;
            S_DLC:      bit_to_emit = dlc_sr[3];
            S_DATA:     bit_to_emit = data_sr[63];
            S_CRC:      bit_to_emit = crc_sr[14];
            S_CRC_DEL:  begin bit_to_emit = 1'b1; stuff_active = 1'b0; end
            S_ACK_SLOT: begin bit_to_emit = 1'b1; stuff_active = 1'b0; end
            S_ACK_DEL:  begin bit_to_emit = 1'b1; stuff_active = 1'b0; end
            S_EOF:      begin bit_to_emit = 1'b1; stuff_active = 1'b0; end
            S_IFS:      begin bit_to_emit = 1'b1; stuff_active = 1'b0; end
            default:    begin bit_to_emit = 1'b1; stuff_active = 1'b0; end
        endcase
    end

    // CRC opdateres kun på SOF..DATA (ikke CRC-feltet selv)
    wire crc_update = (state == S_SOF || state == S_ID  || state == S_RTR
                    || state == S_IDE || state == S_R0  || state == S_DLC
                    || state == S_DATA);

    wire        crc_fb   = crc_acc[14] ^ bit_to_emit;
    wire [14:0] crc_next = crc_fb ? ({crc_acc[13:0], 1'b0} ^ 15'h4599)
                                  :  {crc_acc[13:0], 1'b0};

    // ---- Hjælpewire: databits-total baseret på DLC (kombinatorisk) ----
    wire [6:0] dbits_total = (tx_dlc >= 4'd8) ? 7'd64 : {tx_dlc, 3'b000};

    // ---- Hoved-FSM ----
    always @(posedge clk) begin
        tx_done <= 1'b0;

        if (rst) begin
            state           <= S_IDLE;
            tx_active       <= 1'b0;
            tx_bit          <= 1'b1;
            bit_counter     <= 7'd0;
            same_count      <= 3'd1;
            last_emitted    <= 1'b1;
            stuff_pending   <= 1'b0;
            crc_acc         <= 15'd0;
            crc_sr          <= 15'd0;
            id_sr           <= 11'd0;
            dlc_sr          <= 4'd0;
            data_sr         <= 64'd0;
            data_bits_total <= 7'd0;

        end else if (state == S_IDLE) begin
            tx_bit    <= 1'b1;
            tx_active <= 1'b0;

            if (tx_start) begin
                state           <= S_SOF;
                tx_active       <= 1'b1;
                id_sr           <= tx_id;
                dlc_sr          <= tx_dlc;
                data_bits_total <= dbits_total;
                // LSB-aligned → shift op til MSB så data_sr[63] er første bit
                // (kombinatorisk fall-through ved DLC=0 giver 64-shift = 0)
                data_sr         <= (tx_dlc >= 4'd8) ? tx_data
                                 : (tx_dlc == 4'd0) ? 64'd0
                                 : (tx_data << (64 - {tx_dlc, 3'b000}));
                same_count      <= 3'd1;
                last_emitted    <= 1'b1;
                stuff_pending   <= 1'b0;
                crc_acc         <= 15'd0;
                bit_counter     <= 7'd0;
            end

        end else if (tx_pulse) begin
            if (stuff_pending) begin
                // Emit stuff-bit (modsat af seneste)
                tx_bit        <= ~last_emitted;
                last_emitted  <= ~last_emitted;
                same_count    <= 3'd1;
                stuff_pending <= 1'b0;
                // Ingen state-advance, ingen CRC-update

            end else begin
                // Emit almindelig bit
                tx_bit <= bit_to_emit;

                if (crc_update)
                    crc_acc <= crc_next;

                // Bit-stuff tracking
                if (stuff_active) begin
                    if (bit_to_emit == last_emitted) begin
                        if (same_count == 3'd4) begin
                            same_count    <= 3'd5;
                            stuff_pending <= 1'b1;   // næste pulse = stuff
                        end else begin
                            same_count <= same_count + 1'b1;
                        end
                    end else begin
                        same_count   <= 3'd1;
                        last_emitted <= bit_to_emit;
                    end
                end

                // ---- State-advance ----
                case (state)
                S_SOF: begin
                    state       <= S_ID;
                    bit_counter <= 7'd0;
                end

                S_ID: begin
                    id_sr <= {id_sr[9:0], 1'b0};
                    if (bit_counter == 7'd10) begin
                        state       <= S_RTR;
                        bit_counter <= 7'd0;
                    end else
                        bit_counter <= bit_counter + 1'b1;
                end

                S_RTR: state <= S_IDE;
                S_IDE: state <= S_R0;
                S_R0:  begin state <= S_DLC; bit_counter <= 7'd0; end

                S_DLC: begin
                    dlc_sr <= {dlc_sr[2:0], 1'b0};
                    if (bit_counter == 7'd3) begin
                        bit_counter <= 7'd0;
                        if (data_bits_total == 7'd0) begin
                            crc_sr <= crc_next;
                            state  <= S_CRC;
                        end else begin
                            state <= S_DATA;
                        end
                    end else
                        bit_counter <= bit_counter + 1'b1;
                end

                S_DATA: begin
                    data_sr <= {data_sr[62:0], 1'b0};
                    if (bit_counter == data_bits_total - 1) begin
                        crc_sr      <= crc_next;
                        state       <= S_CRC;
                        bit_counter <= 7'd0;
                    end else
                        bit_counter <= bit_counter + 1'b1;
                end

                S_CRC: begin
                    crc_sr <= {crc_sr[13:0], 1'b0};
                    if (bit_counter == 7'd14) begin
                        state       <= S_CRC_DEL;
                        bit_counter <= 7'd0;
                    end else
                        bit_counter <= bit_counter + 1'b1;
                end

                S_CRC_DEL:  state <= S_ACK_SLOT;
                S_ACK_SLOT: state <= S_ACK_DEL;
                S_ACK_DEL:  begin state <= S_EOF; bit_counter <= 7'd0; end

                S_EOF: begin
                    if (bit_counter == 7'd6) begin
                        state       <= S_IFS;
                        bit_counter <= 7'd0;
                    end else
                        bit_counter <= bit_counter + 1'b1;
                end

                S_IFS: begin
                    if (bit_counter == 7'd2) begin
                        state     <= S_IDLE;
                        tx_active <= 1'b0;
                        tx_done   <= 1'b1;
                    end else
                        bit_counter <= bit_counter + 1'b1;
                end

                default: ;
                endcase
            end
        end
    end

endmodule
