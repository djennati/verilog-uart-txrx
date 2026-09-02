`timescale 1ns/1ps

module TX_testbench;
    reg clk;
    reg reset;
    reg tx_start;
    reg [7:0] data_in;
    reg [1:0] parity_mode;
    wire tx;
    wire busy; 

    initial clk = 0;
    always #5 clk = ~clk;

    TX #(.clock_per_bit(4)) dut (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_start),
        .data_in(data_in),
        .parity_mode(parity_mode),
        .tx(tx),
        .busy(busy)
    );
/*
    initial begin
        $dumpfile("TX_waves.vcd");
        $dumpvars(0,TX_testbench);
    end*/

    initial begin
        $monitor("t=%0t reset=%b tx_start=%b data_in=%h Parity_bit=%b| state=%b tx=%b busy=%b | bit_cnt=%d baud_cnt=%d shift_reg=%h",
        $time, reset, tx_start, data_in,dut.parity_bit, dut.state, tx, busy, dut.bit_counter, dut.baud_counter,
         dut.shift_reg);
        reset = 1'b1;
        @(posedge clk);
        reset = 1'b0;
        data_in = 8'b11011010;
        parity_mode = 2'b01;
        tx_start = 1'b1;
        @(posedge clk);
        #1;
        tx_start = 1'b0;
        
       
       /*

       // ** Reset test during tranmission **
        wait(busy == 0);
        data_in = 8'b11001101;
        tx_start = 1'b1;
        @(posedge clk);
        tx_start = 1'b0;
        wait(dut.state == 2'b10 && dut.bit_counter == 3'd4);
        reset = 1'b1;
        @(posedge clk);
        #1;
        reset = 1'b0;
        

        wait(busy == 0);
        data_in = 8'b01010101;
        tx_start = 1'b1;
        @(posedge clk);
        #1;
        tx_start = 1'b0;
        */
        
        wait(busy == 0);
        $finish;
    
    end
    endmodule