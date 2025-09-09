// uart_tx.v
// UART Transmitter Module
// 9600 baud @ 100 MHz clock
// 8 data bits, no parity, 1 stop bit

module TX ( clk, rst, data_in, tx_en, done, busy, tx );
    input clk;       // System clock (100 MHz)
    input rst;       // Synchronous reset (active high)
    input [7:0] data_in;   // Data to transmit
    input tx_en;  // Start transmission (level)
    output done;      // Transmission done (level)
    output busy;      // Transmitter busy
    output reg tx;    // TX serial output

    parameter COUNT_CYCLES = 100_000_000 / 9600; // ~10417

    // FSM states
    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;
    localparam CLEAN_UP = 3'd4;

    reg [2:0] CS = 0;
    reg [15:0] r_Clock_Count = 0;  
    reg [2:0] r_Bit_Index = 0;
    reg [7:0] r_Tx_Data = 0;
    reg r_Tx_Done = 0;
    reg r_Tx_busy = 0;

    // Sequential
    always @(posedge clk) begin
        if (rst) begin
          CS <= IDLE;
          r_Clock_Count <= 0;
          r_Bit_Index <= 0;
          r_Tx_Data <= 0;
          r_Tx_Done <= 0; 
          r_Tx_busy <= 0;
          tx <= 1'b1; // idle state
        end else begin
            case(CS)
                IDLE: begin
                    tx <= 1'b1; // idle state
                    r_Clock_Count <= 0;
                    r_Bit_Index <= 0;
                    r_Tx_Done <= 0;
                    if(tx_en == 1'b1) begin
                        r_Tx_busy <= 1'b1;
                        r_Tx_Data <= data_in;
                        CS <= START;
                    end else begin
                        CS <= IDLE;
                    end
                end
                START: begin
                    tx <= 1'b0; // start bit
                    if(r_Clock_Count < (COUNT_CYCLES - 1)) begin
                        r_Clock_Count <= r_Clock_Count + 1;
                        CS <= START;
                    end else begin
                        r_Clock_Count <= 0;
                        CS <= DATA;
                    end
                end
                DATA: begin
                    tx <= r_Tx_Data[r_Bit_Index]; // send data bit
                    if(r_Clock_Count < (COUNT_CYCLES - 1)) begin
                        r_Clock_Count <= r_Clock_Count + 1;
                        CS <= DATA;
                    end else begin
                        r_Clock_Count <= 0;
                        if(r_Bit_Index < 7) begin
                            r_Bit_Index <= r_Bit_Index + 1;
                            CS <= DATA;
                        end else begin
                            r_Bit_Index <= 0;
                            CS <= STOP;
                        end
                    end
                end
                STOP: begin
                    tx <= 1'b1; // stop bit
                    r_Tx_Done <= 1'b1;
                    if(r_Clock_Count < (COUNT_CYCLES - 1)) begin
                        r_Clock_Count <= r_Clock_Count + 1;
                        CS <= STOP;
                    end else begin
                        r_Tx_busy <= 1'b0;
                        r_Clock_Count <= 0;
                        CS <= CLEAN_UP;
                    end
                end
                CLEAN_UP: begin
                    CS <= IDLE;
                    r_Tx_Done <= 0;
                    r_Tx_busy <= 1'b0;
                end
            endcase
        end
    end
    // Output assignments
    assign busy = r_Tx_busy;
    assign done = r_Tx_Done;

endmodule