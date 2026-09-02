module RX(
    input clk,
    input rx,
    input reset,
    input [1:0] parity_mode,
    output reg busy,
    output reg data_ready,
    output reg parity_error,
    output reg framing_error,
    output reg [7:0] data_rx

);

localparam IDLE  = 2'b00;
localparam START = 2'b01;
localparam DATA  = 2'b10;
localparam STOP  = 2'b11;

localparam PARITY_NONE = 2'b00;
localparam PARITY_EVEN = 2'b10;
localparam PARITY_ODD  = 2'b01;

parameter  clock_per_bit = 16 ;

reg rx_synq ;
reg rx_unsync;

reg [1:0] state;
reg [1:0] next_state;

reg [8:0] shift_reg;
reg [3:0] bit_counter;
reg [4:0] baud_counter;

/*Even parity uses XOR, odd parity uses XNOR over the 8 data bits.
Does not distinguish PARITY_NONE here -- that's gated separately
below via the parity_mode check before parity_error is set.*/
wire expected_parity = (parity_mode == PARITY_EVEN ? ^shift_reg[7:0] : ~^shift_reg[7:0]);

always @(posedge clk) begin

rx_unsync <= rx;
rx_synq   <= rx_unsync ;

    if (reset) begin
        state <= IDLE;
        bit_counter <= 8;
        baud_counter <= (clock_per_bit >> 1) -2;
        data_rx <= 0;
        shift_reg <= 0;

    end

    else begin
        state <= next_state;
        case (state)

        IDLE : begin
            if (!rx_synq) begin
                /* Load half a bit-period, minus 2 cycles to compensate for the
                2-stage synchronizer delay (rx -> rx_unsync -> rx_synq).
                START then counts this down to 0 and re-samples rx_synq at
                that point, landing on the true midpoint of the incoming
                start bit (as seen on the wire) rather than the midpoint of
                the already-delayed rx_synq signal.*/
                baud_counter <= (clock_per_bit >> 1) - 2;
            end
        end
                

        START : begin
            if (baud_counter == 0 && rx_synq == 0) begin
                baud_counter <= clock_per_bit;
                /* 8 is the starting index for shift_reg[8-bit_counter] during DATA,
                sized to cover 8 data bits plus a 9th slot reserved for the
                optional parity bit.*/
                bit_counter <= 8;
            end

            else baud_counter <= baud_counter - 1;
        end

        DATA : begin
            if (!baud_counter) begin
                baud_counter <= clock_per_bit;
                shift_reg[8 - bit_counter] <= rx_synq;
                bit_counter <= bit_counter - 1;
            end

            else baud_counter <= baud_counter -1;
        end

        STOP : begin
            if (!baud_counter) begin
            /* Deliberately half a bit-period (not a full one) so RX re-arms
            and can detect the next start bit sooner. Any test stimulus
            meant to still read LOW when this state samples framing_error
            must stay low for a full bit period from here, not just half.*/
            baud_counter <= clock_per_bit >> 1;
            data_rx <= shift_reg;
            end
            else 
            baud_counter <= baud_counter - 1;
        end

        default: state <= IDLE;


        endcase

    end
end

always @(*) begin
    next_state = state;
    busy = 0;
    data_ready = 0;
    parity_error = 0;
    framing_error = 0;

    case (state)

    IDLE : begin
        if (!rx_synq) begin
            next_state = START;
            busy = 1'b1;
        end
        else busy = 1'b0;
    end

    START : begin
        busy = 1'b1;
        if (baud_counter == 0) begin
            if (rx_synq == 0)
            next_state = DATA;
        else begin
            busy = 1'b0;
            next_state = IDLE;
        end
    end
    end

    DATA : begin
        busy = 1'b1;
        // Shortens the frame by one shift cycle when parity_mode is NONE,
        // since there's no parity bit to receive after the 8 data bits.
        if (baud_counter == 0 && bit_counter == (parity_mode == PARITY_NONE ? 3'b1 : 3'b0 ))
        next_state = STOP;
    end

    STOP : begin
        busy = 1'b1;
        if (baud_counter == 0) begin
            next_state = IDLE;
            data_ready = 1'b1;
            if (expected_parity != shift_reg[8] && parity_mode != PARITY_NONE)
            parity_error = 1'b1;
            if (rx_synq == 0) 
            // Sampled at the very end of STOP (baud_counter==0), not the middle.
            // Stimulus corrupting the stop bit must remain LOW through this
            // entire window, not just for one nominal bit period.
            framing_error = 1'b1;
        end
    end

    endcase

end
endmodule