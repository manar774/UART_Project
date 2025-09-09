// apb_uart_wrapper.v
// APB Wrapper for UART TX and RX
// Assumes addresses are word-aligned: 0x00 CTRL, 0x04 STATS, 0x08 TX_DATA, 0x0C RX_DATA, 0x10 BAUDIV 
// CTRL_REG bits: [0] tx_en (level, master should manage to avoid retrigger), [1] rx_en, [2] tx_rst, [3] rx_rst
// STATS_REG bits: [0] rx_busy, [1] tx_busy, [2] rx_done, [3] tx_done 
// Baud rate fixed, BAUDIV read/write but not used

module apb_uart (
    input wire PCLK,
    input wire PRESETn,
    input wire [31:0] PADDR,
    input wire PSEL,
    input wire PENABLE,
    input wire PWRITE,
    input wire [31:0] PWDATA,
    output reg [31:0] PRDATA,
    output wire PREADY,
    input wire rx,
    output wire tx
);

    // Internal signals
    reg [31:0] ctrl_reg = 32'h0;
    reg [31:0] tx_data_reg = 32'h0;
    reg [31:0] baudiv_reg = 32'h0; 
    

    wire tx_en = ctrl_reg[0];
    wire rx_en = ctrl_reg[1];
    wire tx_rst_soft = ctrl_reg[2];
    wire rx_rst_soft = ctrl_reg[3];

    wire sys_rst = ~PRESETn; // Active high reset

    wire tx_rst = sys_rst | tx_rst_soft;
    wire rx_rst = sys_rst | rx_rst_soft;

    wire [7:0] tx_data_in = tx_data_reg[7:0];

    wire tx_done, tx_busy;
    wire [7:0] rx_data_out;
    wire rx_done, rx_busy;
    TX u_tx (
        .clk(PCLK),
        .rst(tx_rst),
        .data_in(tx_data_in),
        .tx_en(tx_en),
        .done(tx_done),
        .busy(tx_busy),
        .tx(tx)
    );

    rx u_rx (
        .clk(PCLK),
        .rst(rx_rst),
        .rx(rx),
        .rx_en(rx_en),
        .rx_data(rx_data_out),
        .rx_done(rx_done),
        .rx_busy(rx_busy)
    );
    localparam IDLE = 2'd0;
    localparam SETUP = 2'd1;
    localparam ACCESS = 2'd2;

    reg [1:0] state = IDLE;
    reg pready_int = 1'b0;
    reg [31:0] prdata_int;

    always @(posedge PCLK) begin
        if (sys_rst) begin
            state <= IDLE;
            ctrl_reg <= 32'h0;
            tx_data_reg <= 32'h0;
            baudiv_reg <= 32'h0;
            pready_int <= 1'b0;
        end else begin
            pready_int <= 1'b0;
            case (state)
                IDLE: begin
                    if (PSEL && !PENABLE) begin
                        state <= SETUP;
                    end
                end
                SETUP: begin
                    if (PSEL && PENABLE) begin
                        state <= ACCESS;
                    end else begin
                        state <= IDLE;
                    end
                end
                ACCESS: begin
                    pready_int <= 1'b1;
                    state <= IDLE;
                    if (PWRITE) begin
                        case (PADDR[4:0])
                            5'h00: ctrl_reg <= PWDATA;
                            5'h08: tx_data_reg <= PWDATA;
                            5'h10: baudiv_reg <= PWDATA; 
                            default: ; 
                        endcase
                    end else begin
                        case (PADDR[4:0])
                            5'h00: prdata_int <= ctrl_reg;
                            5'h04: prdata_int <= {29'h0, tx_done, rx_done, tx_busy, rx_busy};
                            5'h08: prdata_int <= tx_data_reg;
                            5'h0C: prdata_int <= {24'h0, rx_data_out};
                            5'h10: prdata_int <= baudiv_reg;
                            default: prdata_int <= 32'h0;
                        endcase
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

    assign PREADY = pready_int;
    always @(*) PRDATA = prdata_int;

endmodule