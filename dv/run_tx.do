vlib work
vlog TX.v  tx_tb.sv +cover -covercells
vsim -voptargs=+acc work.tx_tb -cover
add wave *
coverage save  tx_tb.ucdb -onexit
run -all
