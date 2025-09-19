`timescale 1ns/1ps

module uart_testbench();
    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;
    
    // Clock generation - 50MHz
    initial clk = 0;
    always #10 clk = ~clk; // 20ns period = 50MHz
    
    // DUT
    top u_top (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );
    
    // Test sequence
    initial begin
        // Reset
        rst_n = 0;
        uart_rx = 1; // UART idle state
        #1000;
        rst_n = 1;
        #1000;
        
        // Send byte 0x55
        send_uart_byte(8'h55);
        #100000;
        
        // Send byte 0xAA 
        send_uart_byte(8'hAA);
        #100000;
        
        $display("Test completed");
        $finish;
    end
    
    // UART byte sender task
    task send_uart_byte;
        input [7:0] data;
        integer i;
        begin
            $display("Sending byte: 0x%02h at time %t", data, $time);
            
            // Start bit
            uart_rx = 0;
            #8680; // 1/115200 = 8.68us
            
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #8680;
            end
            
            // Stop bit
            uart_rx = 1;
            #8680;
        end
    endtask
    
    // Monitor TX output
    always @(negedge uart_tx) begin
        $display("TX start bit detected at time %t", $time);
    end
    
    // Dump waveforms
    initial begin
        $dumpfile("uart_testbench.vcd");
        $dumpvars(0, uart_testbench);
    end
    
endmodule