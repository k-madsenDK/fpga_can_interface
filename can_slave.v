// can_slave.v — komplet CAN-node uden applikationslag.
// App-lag kobles udefra til tx_start / tx_id / tx_dlc / tx_data.
//
// Nøgle-designvalg (vigtige for hardware-drift):
//   * RX-pipeline (destuff/crc/fsm/ack) holdes i reset mens tx_active er høj.
//     Det forhindrer at vi ACKer vores egen frame og kolliderer med tx_engine.
//   * bit_timing får tx_active-input så hard-sync ikke trigges på vores egne
//     TX-flanker.
//   * tx_start gates af bus_idle (11 recessive bits set) — matcher can2040's
//     "may transmit"-regel (7 EOF + 3 IFS).
//   * tx_start (som er en 1-cycle puls) latches i tx_pending indtil tx_engine
//     accepterer (tx_active høj), så pulsen ikke går tabt hvis bussen var
//     optaget netop i den cycle.

module can_slave #(
    parameter SYS_CLK_HZ = 100_000_000,
    parameter BITRATE    = 125_000
) (
    input  wire clk,
    input  wire rst,

    // Bus
    input  wire can_rx,
    output wire can_tx,             // 1 = recessive, 0 = dominant

    // RX decoded
    output wire         rx_valid,
    output wire [10:0]  rx_id,
    output wire [3:0]   rx_dlc,
    output wire [63:0]  rx_data,

    // TX request (fra app_fsm)
    input  wire         tx_start,
    input  wire [10:0]  tx_id,
    input  wire [3:0]   tx_dlc,
    input  wire [63:0]  tx_data,
    output wire         tx_busy
);

    // ------------------------------------------------------------------
    // 2-flop synchronizer på can_rx
    // ------------------------------------------------------------------
    reg [1:0] rx_sync;
    always @(posedge clk) begin
        if (rst) rx_sync <= 2'b11;
        else     rx_sync <= {rx_sync[0], can_rx};
    end
    wire rx_bit_sync = rx_sync[1];

    // ------------------------------------------------------------------
    // Forward-deklarerede wires (drives længere nede)
    // ------------------------------------------------------------------
    wire tx_engine_bit;
    wire tx_active;
    wire tx_done;
    wire ack_drive;
    wire ack_request;
    wire sample_pulse, tx_pulse, rx_sampled;
    wire unstuf_tick, unstuf_bit, stuff_error, stuff_enable;
    wire        crc_init, crc_bit_valid, crc_bit_in;
    wire [14:0] crc_computed;
    wire        bus_idle;

    // RX-pipeline reset: hold RX-state i reset mens vi selv sender
    wire rx_rst = rst | tx_active;

    // ------------------------------------------------------------------
    // Bit timing
    // ------------------------------------------------------------------
    bit_timing #(
        .SYS_CLK_HZ(SYS_CLK_HZ),
        .BITRATE(BITRATE)
    ) u_bt (
        .clk(clk),
        .rst(rst),
        .rx_bit(rx_bit_sync),
        .tx_active(tx_active),
        .sample_pulse(sample_pulse),
        .tx_pulse(tx_pulse),
        .rx_sample(rx_sampled)
    );

    // ------------------------------------------------------------------
    // Bus idle tracker (11 recessive bits ≈ EOF + IFS)
    // ------------------------------------------------------------------
    bus_idle #(.IDLE_BITS(11)) u_idle (
        .clk(clk),
        .rst(rst),
        .sample_pulse(sample_pulse),
        .rx_sample(rx_sampled),
        .bus_idle(bus_idle)
    );

    // ------------------------------------------------------------------
    // Destuff
    // ------------------------------------------------------------------
    rx_destuff u_destuff (
        .clk(clk),
        .rst(rx_rst),
        .bit_tick(sample_pulse),
        .bit_in(rx_sampled),
        .stuff_enable(stuff_enable),
        .out_tick(unstuf_tick),
        .out_bit(unstuf_bit),
        .stuff_error(stuff_error)
    );

    // ------------------------------------------------------------------
    // CRC
    // ------------------------------------------------------------------
    crc15 u_crc (
        .clk(clk),
        .rst(rx_rst),
        .init(crc_init),
        .bit_valid(crc_bit_valid),
        .bit_in(crc_bit_in),
        .crc(crc_computed)
    );

    // ------------------------------------------------------------------
    // Frame FSM (RX parser)
    // ------------------------------------------------------------------
    rx_frame_fsm u_fsm (
        .clk(clk),
        .rst(rx_rst),
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

    // ------------------------------------------------------------------
    // ACK driver
    // ------------------------------------------------------------------
    ack_driver #(
        .SYS_CLK_HZ(SYS_CLK_HZ),
        .BITRATE(BITRATE)
    ) u_ack (
        .clk(clk),
        .rst(rx_rst),
        .ack_request(ack_request),
        .ack_drive(ack_drive)
    );
    // ------------------------------------------------------------------
    // TX request pending-latch + gating
    // ------------------------------------------------------------------
    // tx_start er en 1-cycle puls fra app_fsm. Latch den til tx_pending indtil
    // tx_engine accepterer (dvs. tx_active går høj).
    reg tx_pending;
    always @(posedge clk) begin
        if (rst)            tx_pending <= 1'b0;
        else if (tx_start)  tx_pending <= 1'b1;
        else if (tx_active) tx_pending <= 1'b0;
    end

    // Gate: må kun fyres hvis pending, bus er idle, og vi ikke allerede sender
    wire tx_start_gated = tx_pending & bus_idle & ~tx_active;

    // ------------------------------------------------------------------
    // TX engine
    // ------------------------------------------------------------------
    tx_engine u_tx (
        .clk(clk),
        .rst(rst),
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

    // ------------------------------------------------------------------
    // TX MUX
    //   1. tx_active → driv tx_engine_bit (fuld frame)
    //   2. ack_drive → driv 0 (dominant ACK puls)
    //   3. ellers    → 1 (recessive idle)
    // ------------------------------------------------------------------
    assign can_tx = tx_active ? tx_engine_bit
                  : ack_drive ? 1'b0
                  :             1'b1;

endmodule
