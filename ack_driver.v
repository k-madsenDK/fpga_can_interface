// ack_driver.v — holder ack_drive høj i præcis ét bit-interval,
// aligned til ACK-slot start.
//
// ack_request fyrer ved 75% af CRC-DEL slot (sample_pulse). Vi venter
// BIT_CLKS/4 klokslag (= 25% bit = ~2µs @ 125kbit/s) så vi rammer start
// af ACK-slot, og holder dominant i præcis 1 bit (BIT_CLKS klokslag).

module ack_driver #(
    parameter SYS_CLK_HZ = 100_000_000,
    parameter BITRATE    = 125_000
) (
    input  wire clk,
    input  wire rst,
    input  wire ack_request,     // 1-cycle puls fra rx_frame_fsm
    output reg  ack_drive
);
    localparam integer BIT_CLKS   = SYS_CLK_HZ / BITRATE;    // 800
    localparam integer DELAY_CLKS = BIT_CLKS / 4;            // 200 = 25% af bit
    localparam integer CW         = $clog2(BIT_CLKS*2 + 1);

    reg [CW-1:0] cnt;
    reg [1:0]    phase;  // 0=idle, 1=delay, 2=drive
    localparam P_IDLE  = 2'd0;
    localparam P_DELAY = 2'd1;
    localparam P_DRIVE = 2'd2;

    always @(posedge clk) begin
        if (rst) begin
            cnt       <= 0;
            phase     <= P_IDLE;
            ack_drive <= 1'b0;
        end else begin
            case (phase)
            P_IDLE: begin
                ack_drive <= 1'b0;
                if (ack_request) begin
                    phase <= P_DELAY;
                    cnt   <= 0;
                end
            end

            P_DELAY: begin
                if (cnt == DELAY_CLKS - 1) begin
                    phase     <= P_DRIVE;
                    ack_drive <= 1'b1;
                    cnt       <= 0;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end

            P_DRIVE: begin
                if (cnt == BIT_CLKS - 1) begin
                    phase     <= P_IDLE;
                    ack_drive <= 1'b0;
                    cnt       <= 0;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end

            default: phase <= P_IDLE;
            endcase
        end
    end
endmodule
