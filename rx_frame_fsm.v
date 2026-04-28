// rx_frame_fsm.v — CAN frame parser state machine (ULTRA OPTIMERET)
// ack_request er nu 1-cycle puls ved start af ACK-slot (handshake til ack_driver)

module rx_frame_fsm (
    input  wire         clk,
    input  wire         rst,
    input  wire         bit_tick,
    input  wire         bit_in,
    input  wire         stuff_error,

    output reg          crc_init,
    output reg          crc_bit_valid,
    output wire         crc_bit_in,
    input  wire [14:0]  crc_computed,

    output reg          stuff_enable,
    output reg          ack_request,    // 1-cycle puls

    output reg          rx_valid,
    output reg  [10:0]  rx_id,
    output reg  [3:0]   rx_dlc,
    output reg  [63:0]  rx_data
);

    localparam S_IDLE       = 4'd0;
    localparam S_ID         = 4'd1;
    localparam S_RTR_IDE_R0 = 4'd2;
    localparam S_DLC        = 4'd3;
    localparam S_DATA       = 4'd4;
    localparam S_CRC        = 4'd5;
    localparam S_CRC_DEL    = 4'd6;
    localparam S_ACK        = 4'd7;
    localparam S_ACK_DEL    = 4'd8;
    localparam S_EOF        = 4'd9;
    localparam S_ERROR      = 4'd10;

    reg [3:0] state;
    reg [6:0] bit_counter;

    reg [10:0] id_sr;
    reg [3:0]  dlc_sr;
    reg [63:0] data_sr;
    reg [14:0] crc_sr;
    reg [14:0] crc_at_crc_start;
    
    reg [6:0]  target_data_bits;

    assign crc_bit_in = bit_in;

    always @(posedge clk) begin
        // Pulser nulstilles hver cycle
        rx_valid      <= 1'b0;
        crc_init      <= 1'b0;
        crc_bit_valid <= 1'b0;
        ack_request   <= 1'b0;      

        if (rst) begin
            state            <= S_IDLE;
            bit_counter      <= 7'd0;
            stuff_enable     <= 1'b0;
            id_sr            <= 11'd0;
            dlc_sr           <= 4'd0;
            data_sr          <= 64'd0;
            crc_sr           <= 15'd0;
            crc_at_crc_start <= 15'd0;
            rx_id            <= 11'd0;
            rx_dlc           <= 4'd0;
            rx_data          <= 64'd0;
            target_data_bits <= 7'd0;

        end else if (stuff_error && state != S_IDLE) begin
            state        <= S_ERROR;
            stuff_enable <= 1'b0;

        end else if (bit_tick) begin
            case (state)
            S_IDLE: begin
                if (bit_in == 1'b0) begin
                    crc_init      <= 1'b1;
                    stuff_enable  <= 1'b1;
                    state         <= S_ID;
                    bit_counter   <= 7'd0;
                    id_sr         <= 11'd0;
                end
            end

            S_ID: begin
                id_sr         <= {id_sr[9:0], bit_in};
                crc_bit_valid <= 1'b1;
                if (bit_counter == 7'd10) begin
                    state       <= S_RTR_IDE_R0;
                    bit_counter <= 7'd0;
                end else begin
                    bit_counter <= bit_counter + 1'b1;
                end
            end

            S_RTR_IDE_R0: begin
                crc_bit_valid <= 1'b1;
                if (bit_counter == 7'd1 && bit_in == 1'b1) begin
                    state <= S_ERROR;
                end else if (bit_counter == 7'd2) begin
                    state       <= S_DLC;
                    bit_counter <= 7'd0;
                    dlc_sr      <= 4'd0;
                end else begin
                    bit_counter <= bit_counter + 1'b1;
                end
            end

            S_DLC: begin
                dlc_sr        <= {dlc_sr[2:0], bit_in};
                crc_bit_valid <= 1'b1;
                
                if (bit_counter == 7'd3) begin
                    bit_counter <= 7'd0;
                    data_sr     <= 64'd0;
                    
                    // --- EXTREME HARDWARE OPTIMIZATION START ---
                    // Den 4-bit DLC værdi er bygget af {dlc_sr[2], dlc_sr[1], dlc_sr[0], bit_in}.
                    // Vi bruger en NOR-operation til at tjekke for NUL (meget hurtig i en LUT4).
                    if (~(dlc_sr[2] | dlc_sr[1] | dlc_sr[0] | bit_in)) begin
                        state <= S_CRC;
                        target_data_bits <= 7'd0;
                    end else begin
                        state <= S_DATA;
                        
                        // Bit 3 i vores DLC-værdi svarer til 'dlc_sr[2]'. 
                        // Hvis den er høj, er tallet >= 8. (Ingen comparator nødvendig!)
                        if (dlc_sr[2]) begin
                            target_data_bits <= 7'd63; // 64 bits - 1
                        end else begin
                            // Matematik-trick: (DLC * 8) - 1
                            // I stedet for at trække 1 fra et 7-bit tal, trækker vi 1 fra 
                            // vores lille 4-bit DLC og tilføjer '111' til de tomme pladser.
                            target_data_bits <= { ({1'b0, dlc_sr[1:0], bit_in} - 4'd1), 3'b111 };
                        end
                    end
                    // --- EXTREME HARDWARE OPTIMIZATION END ---
                    
                end else begin
                    bit_counter <= bit_counter + 1'b1;
                end
            end

            S_DATA: begin
                data_sr       <= {data_sr[62:0], bit_in};
                crc_bit_valid <= 1'b1;
                
                if (bit_counter == target_data_bits) begin
                    state       <= S_CRC;
                    bit_counter <= 7'd0;
                    crc_sr      <= 15'd0;
                end else begin
                    bit_counter <= bit_counter + 1'b1;
                end
            end

            S_CRC: begin
                if (bit_counter == 7'd0)
                    crc_at_crc_start <= crc_computed;
                crc_sr <= {crc_sr[13:0], bit_in};
                if (bit_counter == 7'd14) begin
                    state       <= S_CRC_DEL;
                    bit_counter <= 7'd0;
                end else begin
                    bit_counter <= bit_counter + 1'b1;
                end
            end

            S_CRC_DEL: begin
                stuff_enable <= 1'b0;
                if (bit_in != 1'b1) begin
                    state <= S_ERROR;
                end else if (crc_sr != crc_at_crc_start) begin
                    state <= S_ERROR;
                end else begin
                    ack_request <= 1'b1;   
                    state       <= S_ACK;
                end
            end

            S_ACK: begin
                state <= S_ACK_DEL;
            end

            S_ACK_DEL: begin
                if (bit_in != 1'b1) begin
                    state <= S_ERROR;
                end else begin
                    state       <= S_EOF;
                    bit_counter <= 7'd0;
                end
            end

            S_EOF: begin
                if (bit_in != 1'b1) begin
                    state <= S_ERROR;
                end else if (bit_counter == 7'd6) begin
                    rx_valid <= 1'b1;
                    rx_id    <= id_sr;
                    rx_dlc   <= dlc_sr;
                    rx_data  <= data_sr;
                    state    <= S_IDLE;
                end else begin
                    bit_counter <= bit_counter + 1'b1;
                end
            end

            S_ERROR: begin
                stuff_enable <= 1'b0;
                if (bit_in == 1'b1)
                    state <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule
