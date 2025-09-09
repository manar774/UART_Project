vlib work
vlog RX.v TX.v apb_uart.v apb_uart_tb.sv +cover -covercells
vsim -voptargs=+acc work.apb_uart_tb -cover
add wave *
coverage save  apb_uart_tb.ucdb -onexit
run -all
