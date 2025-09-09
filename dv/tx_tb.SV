module tx_tb();
    parameter COUNT_CYCLES = 100_000_000 / 9600;
    parameter CLK_PERIOD   = 10; // 100 MHz

    logic clk, rst, tx_en;
    logic [7:0] data_in;
    logic done, busy, tx;
    int error_counter, correct_counter;
    TX DUT (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .tx_en(tx_en),
        .done(done),
        .busy(busy),
        .tx(tx)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end


    initial begin
        error_counter   = 0;
        correct_counter = 0;
        tx_en = 0;
        data_in  = 8'h00;

        // reset
        assert_rst();

        // send byte 0x00 (10100101)
        @(negedge clk);
        data_in  = 8'hA5;
        tx_en = 1;
        @(posedge clk);  // keep tx_en high for 1 cycle

        // check start bit
        wait_for_baud_cycles(1);
        check_result(1'b0, 1'b1, 1'b0, "Start bit");

        // check data bits LSB-first
        check_data_bits(8'hA5);

        // check stop bit
        wait_for_baud_cycles(1);
        check_result(1'b1, 1'b1, 1'b1, "Stop bit");

        // wait for done pulse
        @(posedge clk);
        if (done !== 1) begin
            $display("Error: done not pulsed");
            error_counter++;
        end else begin
            correct_counter++;
        end

        // idle after stop
        @(posedge clk);
        check_result(1'b1, 1'b0, 1'b0, "Idle state");

        $display("error_counter = %0d, correct_counter = %0d",
                 error_counter, correct_counter);
               #100
        $stop;
    end

    // reset task
    task assert_rst();
        rst = 1;
        @(posedge clk);
        rst = 0;
        @(posedge clk);
        check_result(1'b1, 1'b0, 1'b0, "Reset");
    endtask

    // result check
    task check_result(input logic expected_tx,
                      input logic expected_busy,
                      input logic expected_done,
                      string test_name);
        if (tx !== expected_tx ||
            busy   !== expected_busy ||
            done   !== expected_done) begin
            error_counter++;
            $display("%s FAIL: tx=%b (exp %b), busy=%b (exp %b), done=%b (exp %b)",
                     test_name, tx, expected_tx, busy, expected_busy, done, expected_done);
        end else begin
            correct_counter++;
        end
    endtask

    // wait baud cycles
    task wait_for_baud_cycles(input int cycles);
        repeat (cycles * COUNT_CYCLES) @(posedge clk);
    endtask

    // check all 8 data bits
    task check_data_bits(input [7:0] data);
        for (int i = 0; i < 8; i++) begin
            wait_for_baud_cycles(1);
            check_result(data[i], 1'b1, 1'b0, $sformatf("Data bit %0d", i));
        end
    endtask
    initial begin
    // Monitor signals continuously
$monitor("t=%0t | rst=%b tx_en=%b data_in=%h | tx=%b busy=%b done=%b",
         $time, rst, tx_en, data_in, tx, busy, done);
    end
endmodule
