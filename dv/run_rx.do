vlib work
vlog RX.v  rx_tb.sv +cover -covercells
vsim -voptargs=+acc work.rx_tb -cover
add wave *
coverage save rx_tb.ucdb -onexit
run -all
