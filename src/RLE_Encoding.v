module RLE_Encoding(
    input                        clk,
    input                        rst_n,
    input                        start_encode,
    input [7:0]                  data_in,
    input                        data_valid,
    input                        data_end,         // Son veri sinyali
    output reg [7:0]             encoded_data,
    output reg                   encoded_valid,
    output reg                   encoder_ready,
    output reg                   encode_complete
);

    // State machine parametreleri
    localparam IDLE         = 3'd0;
    localparam WAIT_DATA    = 3'd1;
    localparam COUNT_RUN    = 3'd2;
    localparam OUTPUT_COUNT = 3'd3;
    localparam OUTPUT_DATA  = 3'd4;
    localparam COMPLETE     = 3'd5;

    reg [2:0] state, next_state;

    // Veri depolama registerleri
    reg [7:0] current_data;
    reg [7:0] previous_data;
    reg [7:0] run_count;
    reg       first_data;
    reg       output_phase;  // 0: count çıkışı, 1: data çıkışı
    
    // Kontrol sinyalleri
    reg data_consumed;
    reg run_complete;

    // State register
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
                if (start_encode)
                    next_state = WAIT_DATA;
                else
                    next_state = IDLE;
            end
            
            WAIT_DATA: begin
                if (data_valid)
                    next_state = COUNT_RUN;
                else if (data_end && run_count > 0)
                    next_state = OUTPUT_COUNT;
                else
                    next_state = WAIT_DATA;
            end
            
            COUNT_RUN: begin
                if (data_valid && (data_in != current_data || run_count >= 8'd255))
                    next_state = OUTPUT_COUNT;
                else if (data_end)
                    next_state = OUTPUT_COUNT;
                else
                    next_state = WAIT_DATA;
            end
            
            OUTPUT_COUNT: begin
                next_state = OUTPUT_DATA;
            end
            
            OUTPUT_DATA: begin
                if (data_valid && !data_end)
                    next_state = COUNT_RUN;
                else if (data_end)
                    next_state = COMPLETE;
                else
                    next_state = WAIT_DATA;
            end
            
            COMPLETE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // Output logic ve data processing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            encoded_data <= 8'd0;
            encoded_valid <= 1'b0;
            encoder_ready <= 1'b1;
            encode_complete <= 1'b0;
            current_data <= 8'd0;
            previous_data <= 8'd0;
            run_count <= 8'd0;
            first_data <= 1'b1;
            output_phase <= 1'b0;
            data_consumed <= 1'b0;
            run_complete <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    encoded_valid <= 1'b0;
                    encoder_ready <= 1'b1;
                    encode_complete <= 1'b0;
                    run_count <= 8'd0;
                    first_data <= 1'b1;
                    output_phase <= 1'b0;
                    data_consumed <= 1'b0;
                    run_complete <= 1'b0;
                    
                    if (start_encode) begin
                        encoder_ready <= 1'b0;
                        $display("[RLE] Encoding started");
                    end
                end
                
                WAIT_DATA: begin
                    encoded_valid <= 1'b0;
                    data_consumed <= 1'b0;
                    
                    if (data_valid) begin
                        if (first_data) begin
                            current_data <= data_in;
                            previous_data <= data_in;
                            run_count <= 8'd1;
                            first_data <= 1'b0;
                            data_consumed <= 1'b1;
                            $display("[RLE] First data: 0x%02h", data_in);
                        end
                    end
                end
                
                COUNT_RUN: begin
                    data_consumed <= 1'b0;
                    
                    if (data_valid) begin
                        if (data_in == current_data && run_count < 8'd255) begin
                            run_count <= run_count + 8'd1;
                            data_consumed <= 1'b1;
                            $display("[RLE] Same data, count: %d", run_count + 1);
                        end else begin
                            // Farklı veri geldi veya max count'a ulaşıldı
                            run_complete <= 1'b1;
                            $display("[RLE] Run complete - Count: %d, Data: 0x%02h", run_count, current_data);
                        end
                    end else if (data_end && run_count > 0) begin
                        run_complete <= 1'b1;
                        $display("[RLE] Final run - Count: %d, Data: 0x%02h", run_count, current_data);
                    end
                end
                
                OUTPUT_COUNT: begin
                    encoded_data <= run_count;
                    encoded_valid <= 1'b1;
                    output_phase <= 1'b0;
                    run_complete <= 1'b0;
                    $display("[RLE] Output count: %d", run_count);
                end
                
                OUTPUT_DATA: begin
                    encoded_data <= current_data;
                    encoded_valid <= 1'b1;
                    output_phase <= 1'b1;
                    $display("[RLE] Output data: 0x%02h", current_data);
                    
                    // Bir sonraki veri için hazırlık
                    if (data_valid && !data_end) begin
                        current_data <= data_in;
                        previous_data <= current_data;
                        run_count <= 8'd1;
                        data_consumed <= 1'b1;
                        $display("[RLE] Next data loaded: 0x%02h", data_in);
                    end else if (data_end) begin
                        run_count <= 8'd0;
                    end else begin
                        run_count <= 8'd0;
                    end
                end
                
                COMPLETE: begin
                    encoded_valid <= 1'b0;
                    encode_complete <= 1'b1;
                    encoder_ready <= 1'b1;
                    $display("[RLE] Encoding complete");
                end
                
                default: begin
                    encoded_valid <= 1'b0;
                    data_consumed <= 1'b0;
                end
            endcase
        end
    end

endmodule