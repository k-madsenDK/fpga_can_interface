// can_slave_rx.v — "Half-slave": kan modtage frames og ACKe, men ikke sende svar
//
// Dette er den første hardware-milestone: wire alle fem RX-blokke sammen
// og eksponér ack_drive + rx_valid/rx_id/rx_dlc/rx_data.
//
// Output can_tx skal muxes i toppen:
//    can_tx = ack_drive ? 1'b0 : 1'b1
// (i fuld design: også med tx_sending fra TX-path når den er klar)

module can_slave_rx #(
    parameter SYS_CLK_HZ = 100_000_000,
    parameter BITRATE    = 125_000
) (
    input  wire clk,
    input  wire rst,

    input  wire can_rx,           // raw RXD fra transceiver

    // Decoded output
    output wire         rx_valid,
    output wire [10:0]  rx_id,
    output wire [3:0]   rx_dlc,
    output wire [63:0]  rx_data,

    // TX control (to be muxed with future TX path)
    output wire ack_drive         // høj → drive bussen dominant
);

    // --- Synkroniser can_rx til clk-domæne (2-flop synchronizer) ---
    reg [1:0] rx_sync;
    always @(posedge clk) begin
        if (rst) rx_sync <= 2'b11;
        else     rx_sync <= {rx_sync[0], can_rx};
    end
    wire rx_bit_sync = rx_sync[1];

    // --- Bit timing ---
    wire sample_pulse, tx_pulse, rx_sampled;
    bit_timing #(
        .SYS_CLK_HZ(SYS_CLK_HZ),
        .BITRATE(BITRATE)
    ) u_bt (
        .clk(clk), .rst(rst),
        .rx_bit(rx_bit_sync),
        .sample_pulse(sample_pulse),
        .tx_pulse(tx_pulse),
        .rx_sample(rx_sampled)
    );

    // --- Bit destuffing ---
    wire        unstuf_tick;
    wire        unstuf_bit;
    wire        stuff_error;
    wire        stuff_enable;      // styret af frame_fsm
    rx_destuff u_destuff (
        .clk(clk), .rst(rst),
        .bit_tick(sample_pulse),
        .bit_in(rx_sampled),
        .stuff_enable(stuff_enable),
        .out_tick(unstuf_tick),
        .out_bit(unstuf_bit),
        .stuff_error(stuff_error)
    );

    // --- CRC-15 ---
    wire        crc_init;
    wire        crc_bit_valid;
    wire        crc_bit_in;
    wire [14:0] crc_computed;
    crc15 u_crc (
        .clk(clk), .rst(rst),
        .init(crc_init),
        .bit_valid(crc_bit_valid),
        .bit_in(crc_bit_in),
        .crc(crc_computed)
    );

    // --- Frame parser FSM ---
    wire ack_request;
    rx_frame_fsm u_fsm (
        .clk(clk), .rst(rst),
        .bit_tick(unstuf_tick),
        .bit_in(unstuf_bit),
        .stuff_error(stuff_error),
        .crc_init(crc_init),
        .crc_bit_valid(crc_bit_valid),
        .crc_bit_in(crc_bit_in),
        .crc_computed(crc_computed),
        .stuff_enable(stuff_enable),
        .ack_request(ack_request),
        .rx_valid(rx_valid),
        .rx_id(rx_id),
        .rx_dlc(rx_dlc),
        .rx_data(rx_data)
    );

    // --- ACK driver ---
    ack_driver u_ack (
        .clk(clk), .rst(rst),
        .ack_request(ack_request),
        .ack_drive(ack_drive)
    );

endmodule
