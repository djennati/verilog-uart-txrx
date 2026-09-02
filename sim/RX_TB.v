`timescale 1ps/1ps

module rx_TB;
reg clk;
reg rx;
reg reset;
reg [1:0] parity_mode;

wire busy;
wire data_ready;
wire parity_error;
wire framing_error;
wire [7:0] data_rx;

initial clk = 0;
always #5 clk = ~clk;

RX #(.clock_per_bit(16)) dut (
    .clk(clk),
    .rx(rx),
    .reset(reset),
    .busy(busy),
    .data_ready(data_ready),
    .parity_error(parity_error),
    .framing_error(framing_error),
    .data_rx(data_rx),
    .parity_mode(parity_mode)
) ;

/*initial begin
    $dumpfile("rx_waves.vcd");
    $dumpvars(0,rx_TB);
end*/

task send_byte;
    input [8:0] data;
    integer i;
    begin
        rx = 1'b0;
        #160;

        for (i=0;i<9;i=i+1) begin
            rx = data[i];
            #160;
        end

        // -- Corrupted STOP bit --
        // 180ns chosen empirically to outlast RX's STOP sampling window
        // (which reloads baud_counter to half a bit period). Not derived
        // from a formula -- if clock_per_bit changes, recalculate this.
        //rx = 1'b0;
        //#180;

        rx = 1'b1;
        #160;
    end
endtask

initial begin
    $monitor("t=%0t rx_synq=%b state=%b busy=%b data_ready=%b parity_error=%b framing_error=%b baud_cnt=%0d shift_reg=%b data_rx=%b", 
    $time, dut.rx_synq, dut.state, busy, data_ready, parity_error,framing_error, dut.baud_counter, dut.shift_reg, data_rx);
    
    reset = 1'b1;
    @(posedge clk);
    reset = 1'b0;
    #5;
    parity_mode = 2'b10;
    send_byte(9'b110111100);
 
    wait(!busy);
    $finish;
    
end

// Uses event sensitivity instead of @(posedge clk) because
// data_ready/parity_error/framing_error are combinational outputs
// that pulse for a single delta cycle and would already be cleared
// by the next clock edge.
always @(framing_error or parity_error) begin
    if (framing_error) $display("FAIL : framing error FLAG at time %0t", $time);
    if (parity_error) $display("FAIL : parity error FLAG at time %0t", $time);
    end

endmodule