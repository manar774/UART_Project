module apb_uart_tb();
    parameter COUNT_CYCLES = 100_000_000 / 9600;
    parameter HALF_CYCLES = COUNT_CYCLES / 2;
    parameter CLK_PERIOD   = 10; // 100 MHz
    parameter ADDR_CTRL    = 32'h00000000;
    parameter ADDR_STATS   = 32'h00000004;
    parameter ADDR_TX_DATA = 32'h00000008;
    parameter ADDR_RX_DATA = 32'h0000000C;
    parameter ADDR_BAUDIV  = 32'h00000010;

    logic        PCLK;
    logic        PRESETn;
    logic [31:0] PADDR;
    logic        PSEL;
    logic        PENABLE;
    logic        PWRITE;
    logic [31:0] PWDATA;
    logic [31:0] PRDATA;
    logic        PREADY;
    logic        rx;
    logic        tx;

    int error_counter, correct_counter;

    // DUT
    apb_uart DUT (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .PADDR(PADDR),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PWRITE(PWRITE),
        .PWDATA(PWDATA),
        .PRDATA(PRDATA),
        .PREADY(PREADY),
        .rx(rx),
        .tx(tx)
    );

    // clock
    initial begin
        PCLK = 0;
        forever #(CLK_PERIOD/2) PCLK = ~PCLK;
    end

    // test sequence
    initial begin
        error_counter   = 0;
        correct_counter = 0;
        PRESETn = 1;
        PADDR   = 0;
        PSEL    = 0;
        PENABLE = 0;
        PWRITE  = 0;
        PWDATA  = 0;
        rx      = 1; // idle

        // reset
        assert_rst();

        // Test TX
        // 1. Soft reset TX
        apb_write(ADDR_CTRL, 32'h00000004); // tx_rst=1
        apb_write(ADDR_CTRL, 32'h00000000); // tx_rst=0

        // 2. Write TX_DATA
        apb_write(ADDR_TX_DATA, 32'h000000A5);

        // 3. Assert tx_en
        apb_write(ADDR_CTRL, 32'h00000001); // tx_en=1

        // Check tx_busy
        apb_read(ADDR_STATS);
        if (PRDATA[1] !== 1'b1) begin
            $display("Error: tx_busy not set after tx_en");
            error_counter++;
        end else begin
            correct_counter++;
        end

        // Check start bit on tx
        wait_n_cycles(HALF_CYCLES);
        check_tx_result(1'b0, "TX Start bit");

        // Check data bits LSB-first
        check_tx_data_bits(8'hA5);

        // Check stop bit
        wait_n_cycles(COUNT_CYCLES);
        check_tx_result(1'b1, "TX Stop bit");

        // Check tx_done
        apb_read(ADDR_STATS);
        if (PRDATA[3] !== 1'b1) begin
            $display("Error: tx_done not set after transmission");
            error_counter++;
        end else begin
            correct_counter++;
        end

        // Clear tx_en
        apb_write(ADDR_CTRL, 32'h00000000);

        // Check idle
        wait_n_cycles(COUNT_CYCLES);
        check_tx_result(1'b1, "TX Idle state");

        // Test RX
        // 5. Soft reset RX and assert rx_en
        apb_write(ADDR_CTRL, 32'h00000008); // rx_rst=1
        apb_write(ADDR_CTRL, 32'h00000002); // rx_en=1, rx_rst=0

        // Send start bit
        rx = 0;
        wait_n_cycles(HALF_CYCLES);

        // Check rx_busy during reception
        apb_read(ADDR_STATS);
        if (PRDATA[0] !== 1'b1) begin
            $display("Error: rx_busy not set during reception");
            error_counter++;
        end else begin
            correct_counter++;
        end

        wait_n_cycles(COUNT_CYCLES - HALF_CYCLES);

        // Send data bits
        send_data_bits(8'hA5);

        // Send stop bit
        rx = 1;
        wait_n_cycles(COUNT_CYCLES);

        // Check rx_done
        apb_read(ADDR_STATS);
        if (PRDATA[2] !== 1'b1) begin
            $display("Error: rx_done not set after reception");
            error_counter++;
        end else begin
            correct_counter++;
        end

        // Read RX_DATA
        apb_read(ADDR_RX_DATA);
        if (PRDATA[7:0] !== 8'hA5) begin
            $display("Error: Received data %h does not match expected 0xA5", PRDATA[7:0]);
            error_counter++;
        end else begin
            correct_counter++;
        end

        // Soft reset RX to clear done
        apb_write(ADDR_CTRL, 32'h0000000A); // rx_en=1, rx_rst=1
        apb_write(ADDR_CTRL, 32'h00000002); // rx_en=1, rx_rst=0

        // Check rx_done cleared
        apb_read(ADDR_STATS);
        if (PRDATA[2] !== 1'b0) begin
            $display("Error: rx_done not cleared after soft reset");
            error_counter++;
        end else begin
            correct_counter++;
        end

        $display("error_counter = %0d, correct_counter = %0d",
                 error_counter, correct_counter);
        #100;
        $stop;
    end

    // reset task
    task assert_rst();
        PRESETn = 0;
        @(posedge PCLK);
        PRESETn = 1;
        @(posedge PCLK);
        if (tx !== 1'b1 || PREADY !== 1'b0) begin
            $display("Error: Reset failed");
            error_counter++;
        end else begin
            correct_counter++;
        end
    endtask

    // APB write task
    task apb_write(input [31:0] addr, input [31:0] data);
        @(posedge PCLK);
        PADDR  = addr;
        PWDATA = data;
        PWRITE = 1;
        PSEL   = 1;
        PENABLE = 0;
        @(posedge PCLK);
        PENABLE = 1;
        wait(PREADY == 1);
        @(posedge PCLK);
        PSEL   = 0;
        PENABLE = 0;
        PWRITE = 0;
    endtask

    // APB read task
    task apb_read(input [31:0] addr);
        @(posedge PCLK);
        PADDR  = addr;
        PWRITE = 0;
        PSEL   = 1;
        PENABLE = 0;
        @(posedge PCLK);
        PENABLE = 1;
        wait(PREADY == 1);
        // PRDATA is valid here
        @(posedge PCLK);
        PSEL   = 0;
        PENABLE = 0;
    endtask

    // wait n clock cycles
    task wait_n_cycles(input int n);
        repeat (n) @(posedge PCLK);
    endtask

    // check tx bit
    task check_tx_result(input logic expected_tx, string test_name);
        if (tx !== expected_tx) begin
            error_counter++;
            $display("%s FAIL: tx=%b (exp %b)", test_name, tx, expected_tx);
        end else begin
            correct_counter++;
        end
    endtask

    // check all 8 data bits on tx
    task check_tx_data_bits(input [7:0] data);
        for (int i = 0; i < 8; i++) begin
            wait_n_cycles(COUNT_CYCLES);
            check_tx_result(data[i], $sformatf("TX Data bit %0d", i));
        end
    endtask

    // Send data bits on rx
    task send_data_bits(input [7:0] data);
        for (int i = 0; i < 8; i++) begin
            rx = data[i];
            wait_n_cycles(COUNT_CYCLES);
        end
    endtask

    initial begin
        // Monitor signals continuously
        $monitor("t=%0t | PRESETn=%b PSEL=%b PENABLE=%b PWRITE=%b PADDR=%h PWDATA=%h | PRDATA=%h PREADY=%b tx=%b rx=%b",
                 $time, PRESETn, PSEL, PENABLE, PWRITE, PADDR, PWDATA, PRDATA, PREADY, tx, rx);
    end
endmodule