## ==============================
## Basys3 Constraints for apb_uart
## ==============================

## Clock (100 MHz onboard oscillator)
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports {PCLK}]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports {PCLK}]

## Reset (use center button, active low in design)
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {PRESETn}]

## UART interface (USB-UART bridge)
# FPGA → PC
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports {tx}]
# PC → FPGA
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports {rx}]

## Required FPGA configuration options
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
