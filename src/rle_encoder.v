module rle_encoder(
    input                        clk,
    input                        rst_n,
    input                        start_encode,
    input [7:0]                  data_in,
    input                        data_valid,
    output reg [7:0]             encoded_data,
    output reg                   encoded_valid,
    output reg                   encoder_ready,
    output reg                   encode_done
);

// State machine
localparam IDLE = 3'd0;
localparam READ_DATA = 3'd1;
localparam COMPARE = 3'd2;
localparam OUTPUT_COUNT = 3'd3;
localparam OUTPUT_DATA = 3'd4;
localparam DONE = 3'd5;

reg [2:0] state;
reg [2:0] next_state;

// Data storage
reg [7:0] current_data;
reg [7:0] previous_data;
reg [7:0] run_count;
reg [7:0] max_run_length;

// Control signals
reg data_ready;
reg count_ready;

assign data_ready = data_valid;
assign count_ready = (run_count > 8'd0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        encoded_data <= 8'd0;
        encoded_valid <= 1'b0;
        encoder_ready <= 1'b1;
        encode_done <= 1'b0;
        current_data <= 8'd0;
        previous_data <= 8'd0;
        run_count <= 8'd0;
        max_run_length <= 8'd255; // Maximum run length
    end else begin
        state <= next_state;
        
        case (state)
            IDLE: begin
                encoded_valid <= 1'b0;
                encode_done <= 1'b0;
                encoder_ready <= 1'b1;
                run_count <= 8'd0;
                if (start_encode) begin
                    encoder_ready <= 1'b0;
                end
            end
            
            READ_DATA: begin
                if (data_ready) begin
                    current_data <= data_in;
                    if (current_data == previous_data) begin
                        run_count <= run_count + 8'd1;
                    end else begin
                        // Output previous run if exists
                        if (run_count > 8'd0) begin
                            encoded_valid <= 1'b1;
                            encoded_data <= run_count;
                        end
                        run_count <= 8'd1;
                    end
                    previous_data <= current_data;
                end
            end
            
            COMPARE: begin
                if (current_data == previous_data && run_count < max_run_length) begin
                    run_count <= run_count + 8'd1;
                end else begin
                    // Output count and data
                    encoded_valid <= 1'b1;
                    encoded_data <= run_count;
                end
            end
            
            OUTPUT_COUNT: begin
                encoded_valid <= 1'b1;
                encoded_data <= run_count;
            end
            
            OUTPUT_DATA: begin
                encoded_valid <= 1'b1;
                encoded_data <= previous_data;
            end
            
            DONE: begin
                encoded_valid <= 1'b0;
                encode_done <= 1'b1;
                encoder_ready <= 1'b1;
            end
        endcase
    end
end

always @(*) begin
    case (state)
        IDLE: begin
            if (start_encode)
                next_state = READ_DATA;
            else
                next_state = IDLE;
        end
        
        READ_DATA: begin
            if (data_ready)
                next_state = COMPARE;
            else
                next_state = READ_DATA;
        end
        
        COMPARE: begin
            if (current_data == previous_data && run_count < max_run_length)
                next_state = READ_DATA;
            else
                next_state = OUTPUT_COUNT;
        end
        
        OUTPUT_COUNT: begin
            next_state = OUTPUT_DATA;
        end
        
        OUTPUT_DATA: begin
            if (run_count > 8'd0)
                next_state = READ_DATA;
            else
                next_state = DONE;
        end
        
        DONE: begin
            next_state = IDLE;
        end
        
        default: next_state = IDLE;
    endcase
end

endmodule
