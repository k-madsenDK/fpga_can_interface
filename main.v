// main.v — CAN slave 0x123 → 0x124 @ 1 Mbit/s

module main (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       can_rx,
    output wire       can_tx,
    output wire [7:0] led
);
    reg [15:0] por_ctr = 0;
    reg        por_rst = 1'b1;
    always @(posedge clk) begin
        if (por_ctr == 16'hFFFF) por_rst <= 1'b0;
        else begin por_ctr <= por_ctr + 1; por_rst <= 1'b1; end
    end
    reg [2:0] rst_sync = 3'b111;
    always @(posedge clk) rst_sync <= {rst_sync[1:0], ~rst_n};
    wire rst = por_rst | rst_sync[2];

    wire        rx_valid;
    wire [10:0] rx_id;
    wire [3:0]  rx_dlc;
    wire [63:0] rx_data;
    wire        tx_start;
    wire [10:0] tx_id;
    wire [3:0]  tx_dlc;
    wire [63:0] tx_data;
    wire        tx_busy;

    // 1 Mbit/s timing: TQ_PER_BIT=10, SAMPLE_TQ=8 (80% sample)
    // CLKS_PER_TQ = 100M / (1M * 10) = 10 eksakt
    can_slave #(
        .SYS_CLK_HZ(100_000_000),
        .BITRATE(1_000_000),
        .TQ_PER_BIT(10),
        .SAMPLE_TQ(8)
    ) u_slave (
        .clk(clk), .rst(rst),
        .can_rx(can_rx), .can_tx(can_tx),
        .rx_valid(rx_valid), .rx_id(rx_id),
        .rx_dlc(rx_dlc), .rx_data(rx_data),
        .tx_start(tx_start), .tx_id(tx_id),
        .tx_dlc(tx_dlc), .tx_data(tx_data),
        .tx_busy(tx_busy)
    );

    app_fsm #(.LISTEN_ID(11'h123), .RESPONSE_ID(11'h124)) u_app (
        .clk(clk), .rst(rst),
        .rx_valid(rx_valid), .rx_id(rx_id),
        .rx_dlc(rx_dlc), .rx_data(rx_data),
        .tx_busy(tx_busy),
        .tx_start(tx_start), .tx_id(tx_id),
        .tx_dlc(tx_dlc), .tx_data(tx_data)
    );

    reg latch_rx = 0, latch_tx = 0;
    always @(posedge clk) begin
        if (rst) begin latch_rx <= 0; latch_tx <= 0; end
        else begin
            if (rx_valid && rx_id == 11'h123) latch_rx <= 1'b1;
            if (tx_start) latch_tx <= 1'b1;
        end
    end

    reg [25:0] hb = 0;
    always @(posedge clk) hb <= hb + 1;

    reg [7:0] rx_cnt = 0;
    always @(posedge clk)
        if (rx_valid && rx_id == 11'h123) rx_cnt <= rx_cnt + 1;

    assign led[0] = latch_rx;
    assign led[1] = latch_tx;
    assign led[2] = hb[25];
    assign led[3] = can_rx;
    assign led[7:4] = rx_cnt[3:0];
endmodule
