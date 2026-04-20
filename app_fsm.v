// app_fsm.v — applikations-lag: "echo-slave"
//
// Spejl af can_pico_slave.ino:
//   hvis rx_id == 0x125 og dlc >= 2:
//     svar med id 0x126, dlc 2, data = echo(rx_data[0..1])
//
// Desuden: LED 0 toggler ved rx, LED 1 toggler ved tx.

module app_fsm #(
    parameter [10:0] LISTEN_ID   = 11'h125,
    parameter [10:0] RESPONSE_ID = 11'h126
) (
    input  wire         clk,
    input  wire         rst,

    // RX-interface fra rx_frame_fsm
    input  wire         rx_valid,
    input  wire [10:0]  rx_id,
    input  wire [3:0]   rx_dlc,
    input  wire [63:0]  rx_data,

    // TX-interface til tx_engine
    input  wire         tx_busy,        // tx_active fra tx_engine
    output reg          tx_start,
    output reg  [10:0]  tx_id,
    output reg  [3:0]   tx_dlc,
    output reg  [63:0]  tx_data,

    // LED-blinkere
    output reg          led_rx,
    output reg          led_tx
);

    always @(posedge clk) begin
        tx_start <= 1'b0;   // default puls

        if (rst) begin
            tx_id   <= 11'd0;
            tx_dlc  <= 4'd0;
            tx_data <= 64'd0;
            led_rx  <= 1'b0;
            led_tx  <= 1'b0;
        end else begin
            // Ved modtaget frame med matching ID og mindst 2 databytes:
            if (rx_valid && rx_id == LISTEN_ID && rx_dlc >= 4'd2 && !tx_busy) begin
                tx_id   <= RESPONSE_ID;
                tx_dlc  <= 4'd2;
                // Echo: rx_data er MSB-first i [63:48] hvis dlc=2.
                // Vi placerer bare samme byte-layout i tx_data.
                tx_data <= rx_data;      // tx_engine tager kun de øverste 16 bits
                tx_start <= 1'b1;
                led_rx  <= ~led_rx;
            end
            if (tx_busy)
                led_tx <= 1'b1;
            // Men hold LED tx høj et øjeblik — simpel blink vises senere
            // via top-level LED-driver (tæller frames over 1s, ligesom master).
        end
    end

endmodule
