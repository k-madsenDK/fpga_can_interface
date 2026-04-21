// can_slave.v — komplet CAN-node uden applikationslag.
// Parametriseret bit-timing: TQ_PER_BIT og SAMPLE_TQ kan vælges pr. bitrate.

module can_slave #(
    parameter SYS_CLK_HZ = 100_000_000,
    parameter BITRATE    = 125_000,
    parameter TQ_PER_BIT = 16,
    parameter SAMPLE_TQ  = 12
) (
    input  wire clk,
    input  wire rst,
    input  wire can_rx,
    output wire can_tx,

    output wire         rx_valid,
    output wire [10:0]  rx_id,
    output wire [3:0]   rx_dlc,
    output wire [63:0]  rx_data,

    input  wire         tx_start,
    input  wire [10:0]  tx_id,
    input  wire [3:0]   tx_dlc,
    input  wire [63:0]  tx_data,
    output wire         tx_busy
);

    // 2-flop synchronizer på can_rx
    reg [1:0] rx_sync;
    always @(posedge clk) begin
        if (rst) rx_sync <= 2'b11;
        else     rx_sync <= {rx_sync[0], can_rx};
    end
    wire rx_bit_sync = rx_sync[1];

    wire tx_engine_bit, tx_active, tx_done;
    wire ack_drive, ack_request;
    wire sample_pulse, tx_pulse, rx_sampled;
    wire unstuf_tick, unstuf_bit, stuff_error, stuff_enable;
    wire        crc_init, crc_bit_valid, crc_bit_in;
    wire [14:0] crc_computed;
    wire        bus_idle;

    wire rx_rst = rst | tx_active;

    bit_timing #(
        .SYS_CLK_HZ(SYS_CLK_HZ),
        .BITRATE(BITRATE),
        .TQ_PER_BIT(TQ_PER_BIT),
        .SAMPLE_TQ(SAMPLE_TQ)
    ) u_bt (
        .clk(clk), .rst(rst),
        .rx_bit(rx_bit_sync),
        .tx_active(tx_active),
        .sample_pulse(sample_pulse),
        .tx_pulse(tx_pulse),
        .rx_sample(rx_sampled)
    );

    bus_idle #(.IDLE_BITS(11)) u_idle (
        .clk(clk), .rst(rst),
        .sample_pulse(sample_pulse),
        .rx_sample(rx_sampled),
        .bus_idle(bus_idle)
    );

    rx_destuff u_destuff (
        .clk(clk), .rst(rx_rst),
        .bit_tick(sample_pulse),
        .bit_in(rx_sampled),
        .stuff_enable(stuff_enable),
        .out_tick(unstuf_tick),
        .out_bit(unstuf_bit),
        .stuff_error(stuff_error)
    );

    crc15 u_crc (
        .clk(clk), .rst(rx_rst),
        .init(crc_init),
        .bit_valid(crc_bit_valid),
        .bit_in(crc_bit_in),
        .crc(crc_computed)
    );

    rx_frame_fsm u_fsm (
        .clk(clk), .rst(rx_rst),
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

    ack_driver #(
        .SYS_CLK_HZ(SYS_CLK_HZ),
        .BITRATE(BITRATE)
    ) u_ack (
        .clk(clk), .rst(rx_rst),
        .ack_request(ack_request),
        .ack_drive(ack_drive)
    );

    // TX pending-latch
    reg tx_pending;
    always @(posedge clk) begin
        if (rst)            tx_pending <= 1'b0;
        else if (tx_start)  tx_pending <= 1'b1;
        else if (tx_active) tx_pending <= 1'b0;
    end

    wire tx_start_gated = tx_pending & bus_idle & ~tx_active;

    tx_engine u_tx (
        .clk(clk), .rst(rst),
        .tx_pulse(tx_pulse),
        .tx_start(tx_start_gated),
        .tx_id(tx_id),
        .tx_dlc(tx_dlc),
        .tx_data(tx_data),
        .tx_bit(tx_engine_bit),
        .tx_active(tx_active),
        .tx_done(tx_done)
    );

    assign tx_busy = tx_active | tx_pending;

    assign can_tx = tx_active ? tx_engine_bit
                  : ack_drive ? 1'b0
                  :             1'b1;
endmodule
