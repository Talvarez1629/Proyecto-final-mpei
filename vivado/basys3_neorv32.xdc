## NEORV32 minimal bootloader setup for Digilent Basys 3 rev. B

## 100 MHz oscillator
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports clk_i]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk_i]

## Active-low reset on SW0
## SW0 down = reset; SW0 up = run
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports rstn_i]

## GPIO outputs on LEDs 0..7
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {gpio_o[0]}]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports {gpio_o[1]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {gpio_o[2]}]
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports {gpio_o[3]}]
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {gpio_o[4]}]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports {gpio_o[5]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {gpio_o[6]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {gpio_o[7]}]

## USB-UART bridge
## FPGA TX -> bridge RX; bridge TX -> FPGA RX
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports uart0_txd_o]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports uart0_rxd_i]

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]



