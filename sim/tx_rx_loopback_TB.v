`timescale 1ps/1ps

module tx_rx_loopback_TB;
    reg clk;
    reg reset;
    reg tx_start;
    reg [1:0] parity_mode;
    reg [7:0] data_to_send;
    
    wire tx;
    wire busy_tx;
    wire busy_rx;
    wire data_ready;
    wire parity_error;
    wire framing_error;
    wire [7:0] data_received;
    
    // Clock: 10ns period (100 MHz)
    initial clk = 0;
    always #5 clk = ~clk;
    
    // Instantiate TX and RX
    TX #(.clock_per_bit(16)) tx_inst (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_start),
        .parity_mode(parity_mode),
        .data_in(data_to_send),
        .tx(tx),
        .busy(busy_tx)
    );
    
    RX #(.clock_per_bit(16)) rx_inst (
        .clk(clk),
        .rx(tx),  // <-- Loopback: TX output drives RX input
        .reset(reset),
        .parity_mode(parity_mode),
        .busy(busy_rx),
        .data_ready(data_ready),
        .parity_error(parity_error),
        .framing_error(framing_error),
        .data_rx(data_received)
    );
    
    
    // Catch error flags when they pulse
    always @(parity_error or framing_error) begin
        if (parity_error) $display("FAIL: parity_error at t=%0t", $time);
        if (framing_error) $display("FAIL: framing_error at t=%0t", $time);
    end
    
    // Test sequence
    initial begin
        reset = 1;
        tx_start = 0;
        data_to_send = 8'h00;
        @(posedge clk);
        reset = 0;
        
        // Test: Send a byte with correct odd parity
        parity_mode = 2'b01;
        data_to_send = 8'h55;  // 01010101, parity bit should be 1 for odd
        tx_start = 1;
        @(posedge clk);
        tx_start = 0;
        
        // Wait for reception to complete
        wait (data_ready);
        @(posedge clk);
        
        
        
        // Wait for both to be idle before next test
        wait (!busy_tx && !busy_rx);

        // Verify data matches
        if (data_received !== data_to_send)
            $display("FAIL: data mismatch, sent=%h, received=%h at t=%0t", 
                     data_to_send, data_received, $time);
        else
            $display("PASS: data_to_send=%h, data_received=%h at t=%0t",
                     data_to_send, data_received, $time);
       
        $finish;
    end
endmodule