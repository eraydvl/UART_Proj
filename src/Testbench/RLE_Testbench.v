`timescale 1ns/1ps

module RLE_Testbench();
    
    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;
    
    // 50MHz clock
    initial clk = 0;
    always #10 clk = ~clk;
    
    // DUT
    top u_top (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );
    
    // Test
    initial begin
        // Reset
        rst_n = 0;
        uart_rx = 1;
        #1000;
        rst_n = 1;
        #2000;
        
        $display("=== RLE Test Start ===");
        
        // Send "AAA"
        send_byte(8'h41); // 'A'
        send_byte(8'h45); // 'E'  
        send_byte(8'h49); // 'I'
        
        // Wait for processing
        #500000;
        
        $display("=== Test Complete ===");
        $finish;
    end
    
    // UART send task
    task send_byte;
        input [7:0] data;
        integer i;
        begin
            $display("Sending: 0x%02h", data);
            
            uart_rx = 0; // Start bit
            #8680;
            
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #8680;
            end
            
            uart_rx = 1; // Stop bit
            #8680;
            #10000; // Gap between bytes
        end
    endtask
    
    // Monitor TX output
    always @(negedge uart_tx) begin
        $display("TX activity at time %0t", $time);
    end
    
    // Monitor states
    always @(posedge clk) begin
        if (u_top.state != u_top.next_state) begin
            $display("State: %0d -> %0d", u_top.state, u_top.next_state);
        end
    end
    
    // VCD dump
    initial begin
        $dumpfile("RLE_Testbench.vcd");
        $dumpvars(0, RLE_Testbench);
    end
    
endmodule