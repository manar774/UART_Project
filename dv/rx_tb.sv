module rx_tb();
    parameter COUNT_CYCLES = 100_000_000 / 9600; // 10417 cycles per bit
    parameter HALF_CYCLES = COUNT_CYCLES / 2;    // Middle of bit for sampling
    parameter CLK_PERIOD = 10; // 100 MHz clock

    logic clk, rst, rx_en;
    logic rx;
    logic [7:0] rx_data;
    logic rx_done, rx_busy;
    int error_counter, correct_counter;

    // DUT
    rx DUT (
        .clk(clk),
        .rst(rst),
        .rx_en(rx_en),
        .rx(rx),
        .rx_data(rx_data),
        .rx_done(rx_done),
        .rx_busy(rx_busy)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test sequence
    initial begin
        error_counter = 0;
        correct_counter = 0;
        rx_en = 0;
        rx = 1; // Idle state

        // Reset
        assert_rst();

        // Send a frame: Start bit + 0xA5 (10100101) + Stop bit + cleanup
        @(negedge clk);
        rx_en = 1;
        send_frame(8'hA5);

        // Wait for reception to complete
        wait_for_baud_cycles(COUNT_CYCLES * 10);
        if (rx_done !== 0 || rx_busy !== 0) begin
            $display("Error: rx_done not cleared or rx_busy not cleared, rx_done=%b, rx_busy=%b", rx_done, rx_busy);
            error_counter++;
        end else if (rx_data !== 8'hA5) begin
            $display("Error: Received data %h does not match expected 0xA5", rx_data);
            error_counter++;
        end else begin
            correct_counter++;
        end

        // Check idle state
        @(negedge clk);
        if (rx !== 1 || rx_busy !== 0 || rx_done !== 0) begin
            $display("Error: Not in idle state after reception, rx=%b, rx_busy=%b, rx_done=%b", rx, rx_busy, rx_done);
            error_counter++;
        end else begin
            correct_counter++;
        end

        $display("error_counter = %0d, correct_counter = %0d", error_counter, correct_counter);
        #100 $stop;
    end

    // Reset task
    task assert_rst();
        rst = 1;
        @(negedge clk);
        rst = 0;
        @(negedge clk);
        if (rx_busy !== 0 || rx_done !== 0) begin
            $display("Error: Reset failed");
            error_counter++;
        end else begin
            correct_counter++;
        end
    endtask

    // Send a UART frame
    task send_frame(input [7:0] data);
        // Start bit
        rx = 0;
        wait_for_baud_cycles(HALF_CYCLES);
        if (rx_busy !== 1 || rx_done !== 0) begin
            $display("Error: rx_busy not asserted during start bit, rx_busy=%b, rx_done=%b", rx_busy, rx_done);
            error_counter++;
        end else begin
            correct_counter++;
        end

        // Data bits (LSB first)
        for (int i = 0; i < 8; i++) begin
            wait_for_baud_cycles(COUNT_CYCLES);
            rx = data[i];
        end

        // Stop bit
        rx = 1;
        wait_for_baud_cycles(COUNT_CYCLES);
        if (rx_busy !== 1||rx_done !== 1) begin
            $display("Error: rx_busy not asserted during stop bit, rx_busy=%b, rx_done=%b", rx_busy, rx_done);
            error_counter++;
        end else begin
            correct_counter++;
        end
    endtask

    // Wait for baud cycles
    task wait_for_baud_cycles(input int cycles);
        repeat (cycles) @(negedge clk);
    endtask

    // Monitor signals
    initial begin
        $monitor("t=%0t | rst=%b rx_en=%b rx=%b | rx_data=%h rx_busy=%b rx_done=%b",
                 $time, rst, rx_en, rx, rx_data, rx_busy, rx_done);
    end
endmodule