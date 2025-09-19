module top (
    input  wire clk,       // Sistem clock
    input  wire rst_n,     // Asenkron reset (aktif düşük)
    input  wire uart_rx,   // Harici RX pini
    output wire uart_tx    // Harici TX pini
);

    // RX sinyalleri
    wire [7:0] rx_data;
    wire       rx_data_valid;
    reg        rx_data_ready;

    // TX sinyalleri
    reg  [7:0] tx_data;
    reg        tx_data_valid;
    wire       tx_data_ready;

    // State machine için
    localparam IDLE = 2'b00;
    localparam WAIT_TX = 2'b01;
    localparam ACK_RX = 2'b10;
    
    reg [1:0] state, next_state;
    reg [3:0] ack_counter; // RX acknowledge için sayaç

    // RX modülü
    uart_rx #(
        .CLK_FRE(50),
        .BAUD_RATE(115200)
    ) u_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(rx_data),
        .rx_data_valid(rx_data_valid),
        .rx_data_ready(rx_data_ready),
        .rx_pin(uart_rx)
    );

    // TX modülü
    uart_tx #(
        .CLK_FRE(50),
        .BAUD_RATE(115200)
    ) u_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_data(tx_data),
        .tx_data_valid(tx_data_valid),
        .tx_data_ready(tx_data_ready),
        .tx_pin(uart_tx)
    );

    // State machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Next state logic
    always @(*) begin
        case (state)
            IDLE: begin
                if (rx_data_valid && tx_data_ready)
                    next_state = WAIT_TX;
                else
                    next_state = IDLE;
            end
            
            WAIT_TX: begin
                if (!tx_data_ready) // TX başladı
                    next_state = ACK_RX;
                else
                    next_state = WAIT_TX;
            end
            
            ACK_RX: begin
                if (ack_counter == 4'd15) // Birkaç clock cycle bekle
                    next_state = IDLE;
                else
                    next_state = ACK_RX;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // Output logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_data       <= 8'h00;
            tx_data_valid <= 1'b0;
            rx_data_ready <= 1'b0;
            ack_counter   <= 4'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (rx_data_valid && tx_data_ready) begin
                        tx_data       <= rx_data;
                        tx_data_valid <= 1'b1;
                        rx_data_ready <= 1'b0;
                        $display("Loopback: RX data = %02h", rx_data);
                    end else begin
                        tx_data_valid <= 1'b0;
                        rx_data_ready <= 1'b0;
                    end
                    ack_counter <= 4'd0;
                end
                
                WAIT_TX: begin
                    tx_data_valid <= 1'b0; // Tek pulse
                    rx_data_ready <= 1'b0;
                    ack_counter   <= 4'd0;
                end
                
                ACK_RX: begin
                    tx_data_valid <= 1'b0;
                    rx_data_ready <= 1'b1; // RX'e acknowledge
                    ack_counter   <= ack_counter + 1;
                end
                
                default: begin
                    tx_data_valid <= 1'b0;
                    rx_data_ready <= 1'b0;
                    ack_counter   <= 4'd0;
                end
            endcase
        end
    end

endmodule