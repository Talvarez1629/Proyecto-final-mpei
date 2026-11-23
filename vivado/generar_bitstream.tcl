source [file join [file dirname [info script]] crear_proyecto.tcl]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Sintesis incompleta" }
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementacion incompleta" }
open_run impl_1
report_timing_summary -file [file join $out timing_summary.rpt]
report_drc -file [file join $out drc.rpt]
report_utilization -file [file join $out utilization.rpt]
puts "Bitstream: [file join $out mpei_basys3.runs impl_1 neorv32_tcu_top.bit]"
