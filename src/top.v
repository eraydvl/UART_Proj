module top (
    input  wire clk,       // Sistem clock
    input  wire rst_n,     // Asenkron reset (aktif düşük)
    input  wire uart_rx,   // Harici RX pini
    output wire uart_tx    // Harici TX pini
);

    // UART RX sinyalleri
    wire [7:0] rx_data;
    wire       rx_data_valid;
    reg        rx_data_ready;

    // UART TX sinyalleri
    reg  [7:0] tx_data;
    reg        tx_data_valid;
    wire       tx_data_ready;

    // RLE Encoder sinyalleri
    reg        start_encode;
    reg  [7:0] rle_data_in;
    reg        rle_data_valid;
    reg        rle_data_end;
    wire [7:0] encoded_data;
    wire       encoded_valid;
    wire       encoder_ready;
    wire       encode_complete;

    // Veri depolama (basit buffer)
    reg [7:0]  data_buffer [0:255];  // 256 byte buffer
    reg [7:0]  write_ptr;            // Yazma pointer'ı
    reg [7:0]  read_ptr;             // Okuma pointer'ı
    reg [7:0]  data_count;           // Buffer'daki veri sayısı
    
    // Ana state machine
    localparam IDLE          = 4'd0;
    localparam RECEIVE_DATA  = 4'd1;
    localparam BUFFER_DATA   = 4'd2;
    localparam START_ENCODE  = 4'd3;
    localparam FEED_ENCODER  = 4'd4;
    localparam WAIT_ENCODE   = 4'd5;
    localparam SEND_ENCODED  = 4'd6;
    localparam FINISH_ENCODE = 4'd7;
    localparam ENCODE_DONE   = 4'd8;
    
    reg [3:0] state, next_state;
    
    // Kontrol sinyalleri
    reg receive_complete;        // Veri alma tamamlandı sinyali
    reg [15:0] rx_timeout;       // RX timeout sayacı (daha uzun)
    reg encoding_active;         // Encoding aktif mi?
    reg [3:0] tx_wait_counter;   // TX için bekleme sayacı

    // UART RX modülü
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

    // UART TX modülü
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

    // RLE Encoder modülü
    RLE_Encoding u_rle (
        .clk(clk),
        .rst_n(rst_n),
        .start_encode(start_encode),
        .data_in(rle_data_in),
        .data_valid(rle_data_valid),
        .data_end(rle_data_end),
        .encoded_data(encoded_data),
        .encoded_valid(encoded_valid),
        .encoder_ready(encoder_ready),
        .encode_complete(encode_complete)
    );

    // Ana state machine register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Ana state machine logic
    always @(*) begin
        case (state)
            IDLE: begin
                if (rx_data_valid)
                    next_state = RECEIVE_DATA;
                else
                    next_state = IDLE;
            end
            
            RECEIVE_DATA: begin
                if (rx_data_valid)
                    next_state = BUFFER_DATA;
                else if (receive_complete && data_count > 0)
                    next_state = START_ENCODE;
                else
                    next_state = RECEIVE_DATA;
            end
            
            BUFFER_DATA: begin
                next_state = RECEIVE_DATA;
            end
            
            START_ENCODE: begin
                if (encoder_ready)
                    next_state = FEED_ENCODER;
                else
                    next_state = START_ENCODE;
            end
            
            FEED_ENCODER: begin
                if (read_ptr >= data_count)
                    next_state = FINISH_ENCODE;
                else
                    next_state = FEED_ENCODER;
            end
            
            FINISH_ENCODE: begin
                next_state = WAIT_ENCODE;
            end
            
            WAIT_ENCODE: begin
                if (encode_complete)
                    next_state = ENCODE_DONE;
                else if (encoded_valid)
                    next_state = SEND_ENCODED;
                else
                    next_state = WAIT_ENCODE;
            end
            
            SEND_ENCODED: begin
                if (tx_wait_counter >= 4'd10) // TX tamamlanma beklemesi
                    next_state = WAIT_ENCODE;
                else
                    next_state = SEND_ENCODED;
            end
            
            ENCODE_DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // RX timeout sayacı (veri alma bittiğini anlamak için)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_timeout <= 16'd0;
            receive_complete <= 1'b0;
        end else begin
            if (rx_data_valid) begin
                rx_timeout <= 16'd0;
                receive_complete <= 1'b0;
            end else if (state == RECEIVE_DATA || state == BUFFER_DATA) begin
                if (rx_timeout < 16'd50000) begin // ~1ms @ 50MHz
                    rx_timeout <= rx_timeout + 1;
                end else begin
                    receive_complete <= 1'b1; // Timeout oldu, veri alma bitti
                end
            end else begin
                rx_timeout <= 16'd0;
                receive_complete <= 1'b0;
            end
        end
    end

    // Buffer yönetimi ve kontrol sinyalleri
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= 8'd0;
            read_ptr <= 8'd0;
            data_count <= 8'd0;
            rx_data_ready <= 1'b0;
            start_encode <= 1'b0;
            rle_data_in <= 8'd0;
            rle_data_valid <= 1'b0;
            rle_data_end <= 1'b0;
            tx_data <= 8'd0;
            tx_data_valid <= 1'b0;
            encoding_active <= 1'b0;
            tx_wait_counter <= 4'd0;
        end else begin
            case (state)
                IDLE: begin
                    write_ptr <= 8'd0;
                    read_ptr <= 8'd0;
                    data_count <= 8'd0;
                    rx_data_ready <= 1'b0;
                    start_encode <= 1'b0;
                    rle_data_valid <= 1'b0;
                    rle_data_end <= 1'b0;
                    tx_data_valid <= 1'b0;
                    encoding_active <= 1'b0;
                    tx_wait_counter <= 4'd0;
                    
                    if (rx_data_valid) begin
                        rx_data_ready <= 1'b1; // RX'den veriyi al
                        $display("[TOP] Starting data reception");
                    end
                end
                
                RECEIVE_DATA: begin
                    start_encode <= 1'b0;
                    rle_data_valid <= 1'b0;
                    rle_data_end <= 1'b0;
                    tx_data_valid <= 1'b0;
                    tx_wait_counter <= 4'd0;
                    
                    if (rx_data_valid) begin
                        rx_data_ready <= 1'b1; // Veri geldiğinde hazır sinyali ver
                    end else begin
                        rx_data_ready <= 1'b0;
                    end
                end
                
                BUFFER_DATA: begin
                    if (write_ptr < 8'd255) begin
                        data_buffer[write_ptr] <= rx_data;
                        write_ptr <= write_ptr + 1;
                        data_count <= data_count + 1;
                        $display("[TOP] Buffered data[%0d] = 0x%02h ('%c')", write_ptr, rx_data, rx_data);
                    end
                    rx_data_ready <= 1'b0; // Acknowledge tamamlandı
                end
                
                START_ENCODE: begin
                    if (encoder_ready) begin
                        start_encode <= 1'b1;
                        encoding_active <= 1'b1;
                        read_ptr <= 8'd0;
                        $display("[TOP] Starting RLE encoding with %0d bytes", data_count);
                    end
                    rx_data_ready <= 1'b0;
                    rle_data_end <= 1'b0;
                end
                
                FEED_ENCODER: begin
                    start_encode <= 1'b0;
                    
                    if (read_ptr < data_count) begin
                        rle_data_in <= data_buffer[read_ptr];
                        rle_data_valid <= 1'b1;
                        read_ptr <= read_ptr + 1;
                        $display("[TOP] Feeding encoder: data[%0d] = 0x%02h", read_ptr, data_buffer[read_ptr]);
                        
                        // Son veri mi kontrol et
                        if (read_ptr + 1 >= data_count) begin
                            rle_data_end <= 1'b1;
                            $display("[TOP] Last data fed to encoder");
                        end
                    end else begin
                        rle_data_valid <= 1'b0;
                    end
                end
                
                FINISH_ENCODE: begin
                    rle_data_valid <= 1'b0;
                    rle_data_end <= 1'b1; // Son veri sinyali
                    $display("[TOP] Finishing encode phase");
                end
                
                WAIT_ENCODE: begin
                    rle_data_valid <= 1'b0;
                    start_encode <= 1'b0;
                    
                    // TX işlemi için bekleme sayacını sıfırla
                    if (encoded_valid && next_state == SEND_ENCODED) begin
                        tx_wait_counter <= 4'd0;
                    end
                end
                
                SEND_ENCODED: begin
                    if (encoded_valid && tx_data_ready && tx_wait_counter == 4'd0) begin
                        tx_data <= encoded_data;
                        tx_data_valid <= 1'b1;
                        tx_wait_counter <= tx_wait_counter + 1;
                        $display("[TOP] Sending encoded data: 0x%02h ('%c')", encoded_data, encoded_data);
                    end else if (tx_wait_counter > 4'd0 && tx_wait_counter < 4'd10) begin
                        tx_data_valid <= 1'b0; // Pulse tamamlandı
                        tx_wait_counter <= tx_wait_counter + 1;
                    end else if (tx_wait_counter >= 4'd10) begin
                        tx_wait_counter <= 4'd0;
                        tx_data_valid <= 1'b0;
                    end
                end
                
                ENCODE_DONE: begin
                    rle_data_valid <= 1'b0;
                    rle_data_end <= 1'b0;
                    tx_data_valid <= 1'b0;
                    encoding_active <= 1'b0;
                    tx_wait_counter <= 4'd0;
                    $display("[TOP] RLE encoding completed, returning to IDLE");
                end
                
                default: begin
                    rx_data_ready <= 1'b0;
                    start_encode <= 1'b0;
                    rle_data_valid <= 1'b0;
                    rle_data_end <= 1'b0;
                    tx_data_valid <= 1'b0;
                    tx_wait_counter <= 4'd0;
                end
            endcase
        end
    end

endmodule