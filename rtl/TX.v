module TX(
    input clk,
    input reset,
    input tx_start,
    input [1:0] parity_mode,
    input [7:0] data_in,
    output reg tx,
    output reg busy 
);

localparam IDLE  = 2'b00;
localparam START = 2'b01;
localparam DATA  = 2'b10;
localparam STOP  = 2'b11;

localparam PARITY_NONE = 2'b00;
localparam PARITY_EVEN = 2'b10;
localparam PARITY_ODD  = 2'b01;

parameter  clock_per_bit = 16 ;

reg [1:0] state;
reg [1:0] next_state;

reg [8:0] shift_reg;
reg [3:0] bit_counter;
reg [4:0] baud_counter;

// Same EVEN/ODD convention as RX: XOR for even, XNOR for odd.
// PARITY_NONE isn't handled here, the transmitted parity bit value
// is simply ignored by a receiver configured for no parity.
wire parity_bit = (parity_mode == PARITY_EVEN) ? ^data_in : ~^data_in;


always @(posedge clk ) begin
    if (reset) begin
        state <= IDLE;
        shift_reg   <= 0;
        bit_counter <= 8;
        baud_counter <= clock_per_bit;
    end
    else begin
        state <= next_state;
        case(state)

        IDLE: begin
            if (tx_start) begin 
            baud_counter <= clock_per_bit;
            
            end
        end

        START: begin
            if (baud_counter == 0) begin
            baud_counter <= clock_per_bit;
            bit_counter <= 8; 
            // 9-bit frame: {parity_bit, data_in}. Bits are shifted out LSB-first
            // from data_in; parity_bit occupies the 9th slot and is sent last.
            shift_reg <= {parity_bit, data_in};
            end
            else baud_counter <= baud_counter - 1;
        end

        DATA: begin
            if (baud_counter == 0) begin
            bit_counter <= bit_counter - 1; 
            baud_counter <= clock_per_bit;
            end
            
            else baud_counter <= baud_counter - 1;
        end

        STOP: begin
            if (baud_counter == 0)
            baud_counter <= clock_per_bit;
            else baud_counter <= baud_counter - 1;
        end

        default: state <= IDLE;

        endcase
    end
end

always @(*) begin
    next_state = state;
    tx = 1'b1;
    busy =1'b0;
    case(state)

    IDLE: begin
    if (tx_start) begin
        next_state = START;
        busy = 1'b1;
    end
    else begin
        tx = 1'b1;
        busy =1'b0;
    end
    end

    START: begin
        tx = 1'b0;
        busy = 1'b1;
        if (!baud_counter)
        next_state = DATA;
    end

    DATA : begin
        tx = shift_reg [8 - bit_counter];
        busy = 1'b1;
        // Shortens the frame by one shift cycle when parity_mode is NONE,
        // since there's no parity bit to transmit after the 8 data bits.
        if (!baud_counter && bit_counter == (parity_mode == PARITY_NONE ? 3'b1 : 3'b0))  next_state = STOP;
        
    end

    STOP: begin
            tx = 1'b1;
            busy = 1'b1;
        if (!baud_counter) next_state = IDLE;
        end

    

    default : next_state = IDLE;
    endcase
end
endmodule